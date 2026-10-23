defmodule SamgitaCodexDriver.NativeProjectProfilesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_project "67e55044-10b1-426f-9247-bb680e5fe0c8"

  setup tags do
    ctx = TurnFixture.setup(tags)
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    case tags[:store] do
      :in_memory ->
        id =
          "00000000-0000-4000-8000-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)

        File.write!(
          config,
          "experimental_thread_store = { type = \"in_memory\", id = \"#{id}\" }\n" <>
            File.read!(config)
        )

      :sqlite_false ->
        File.write!(config, "\n[features]\nsqlite = false\n", [:append])

      _ ->
        :ok
    end

    ctx
  end

  for negotiation <- [:absent, false] do
    @tag negotiation: negotiation
    test "all project methods reach native experimental rejection, negotiation=#{negotiation}",
         ctx do
      pid = start_profile(ctx, ctx.negotiation)

      for {method, params} <- project_operations() do
        # Bypass local method gating so this assertion observes the real server.
        error = upstream_error(pid, method, params, validation: :wire)

        assert error == %{
                 "code" => -32_600,
                 "message" => "#{method} requires experimentalApi capability"
               }

        assert_no_project_events(pid)
      end

      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
      assert :ok = Session.close(pid)
      enabled = start_profile(ctx, true)
      assert projects(enabled) == []
      assert_no_project_events(enabled)
      assert ModelFixture.requests(ctx.fixture) == []
    end
  end

  @tag store: :in_memory
  test "in-memory thread storage rejects every project operation without blocking ordinary threads",
       ctx do
    pid = start_profile(ctx, true)

    for {method, params} <- project_operations() do
      assert upstream_error(pid, method, params) == %{
               "code" => -32_601,
               "message" => "#{method} is unavailable without sqlite state"
             }

      assert_no_project_events(pid)
    end

    assert upstream_error(pid, "thread/list", %{"projectId" => nil}) == %{
             "code" => -32_601,
             "message" => "projects is not supported yet"
           }

    id = thread(ctx, pid)
    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["projectId"] == nil
    assert_no_project_events(pid)
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  @tag store: :sqlite_false
  test "the removed sqlite flag does not disable the default local project store", ctx do
    pid = start_profile(ctx, true)
    params = create_params("Removed sqlite flag", "sqlite-removed")
    created = call(pid, "project/create", params)["project"]
    assert project_events(pid) == [changed(created, "created")]
    assert projects(pid) == [created]
    assert :ok = Session.close(pid)
    resumed = start_profile(ctx, true)
    assert call(resumed, "project/read", %{"projectId" => created["id"]})["project"] == created
    assert call(resumed, "project/create", params)["project"] == created
    assert projects(resumed) == [created]
    assert_no_project_events(resumed)
    assert ModelFixture.requests(ctx.fixture) == []
  end

  test "512-byte UTF8 idempotency survives cold and cross-method replay while 513 bytes fails",
       ctx do
    pid = start_profile(ctx, true)
    key = String.duplicate("é", 256)
    assert byte_size(key) == 512
    assert String.length(key) == 256
    params = create_params("  UTF8 é🙂 Project  ", key)
    created = call(pid, "project/create", params)["project"]
    assert created["name"] == "UTF8 é🙂 Project"
    assert created["metadata"] == %{}
    assert project_events(pid) == [changed(created, "created")]

    rejected = Map.put(params, "idempotencyKey", key <> "a")
    assert byte_size(rejected["idempotencyKey"]) == 513

    assert upstream_error(pid, "project/create", rejected) == %{
             "code" => -32_602,
             "message" => "idempotencyKey must be at most 512 bytes"
           }

    # Create/import share the durable key namespace. A valid replay returns the
    # original before attempting assignment of the supplied nonexistent thread.
    replay = %{
      "name" => "Ignored cross-method replay",
      "roots" => [],
      "metadata" => nil,
      "threads" => [@missing_project],
      "idempotencyKey" => key
    }

    assert call(pid, "project/import", replay)["project"] == created
    assert projects(pid) == [created]
    assert_no_project_events(pid)
    assert :ok = Session.close(pid)
    resumed = start_profile(ctx, true)
    assert call(resumed, "project/import", replay)["project"] == created

    assert call(resumed, "project/create", Map.put(params, "name", "Ignored cold replay"))[
             "project"
           ] == created

    assert projects(resumed) == [created]
    assert_no_project_events(resumed)
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
  end

  test "import omission null and empty collections preserve the native defaults on replay", ctx do
    pid = start_profile(ctx, true)

    created =
      for {suffix, fields} <- [
            {"omitted", %{}},
            {"null", %{"threads" => nil, "metadata" => nil}},
            {"empty", %{"threads" => [], "metadata" => %{}}}
          ] do
        params = Map.merge(create_params("Import #{suffix}", "presence-#{suffix}"), fields)
        created = call(pid, "project/import", params)["project"]
        assert created["roots"] == []
        assert created["metadata"] == %{}
        assert project_events(pid) == [changed(created, "created")]

        assert call(
                 pid,
                 "project/import",
                 Map.merge(params, %{"threads" => [], "metadata" => %{}})
               )[
                 "project"
               ] == created

        assert_no_project_events(pid)
        created
      end

    assert projects(pid) == created
    assert ModelFixture.requests(ctx.fixture) == []
  end

  test "deleted project keys remain reserved after cold restart without recreating a project",
       ctx do
    pid = start_profile(ctx, true)
    params = create_params("Deleted reservation", "reserved-after-delete")
    created = call(pid, "project/create", params)["project"]
    assert project_events(pid) == [changed(created, "created")]
    assert call(pid, "project/delete", %{"projectId" => created["id"]}) == %{}
    assert project_events(pid) == [changed(created, "deleted")]
    assert projects(pid) == []
    assert :ok = Session.close(pid)
    resumed = start_profile(ctx, true)

    for method <- ["project/create", "project/import"] do
      assert upstream_error(resumed, method, params) == %{
               "code" => -32_602,
               "message" => "idempotency key refers to deleted project: reserved-after-delete"
             }

      assert projects(resumed) == []
      assert_no_project_events(resumed)
    end

    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
  end

  defp start_profile(ctx, negotiation) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: ctx.fixture.workspace,
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "RUST_LOG" => "off",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    params = %{"clientInfo" => %{"name" => "samgita_project_profile", "version" => "0.1.0"}}

    params =
      if negotiation == :absent,
        do: params,
        else: Map.put(params, "capabilities", %{"experimentalApi" => negotiation})

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.request_native(pid, %{
               "id" => "initialize-profile",
               "method" => "initialize",
               "params" => params
             })

    pid
  end

  defp project_operations do
    [
      {"project/create", create_params("Rejected create", "rejected-create")},
      {"project/import",
       Map.put(create_params("Rejected import", "rejected-import"), "threads", [])},
      {"project/list", %{}},
      {"project/read", %{"projectId" => @missing_project}},
      {"project/update", %{"projectId" => @missing_project, "name" => "Rejected update"}},
      {"project/move", %{"projectId" => @missing_project, "beforeProjectId" => nil}},
      {"project/delete", %{"projectId" => @missing_project}}
    ]
  end

  defp create_params(name, key), do: %{"name" => name, "roots" => [], "idempotencyKey" => key}
  defp projects(pid), do: call(pid, "project/list", %{})["data"]

  defp project_events(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] == "error"))

    for event <- events, event.wire["method"] in ["project/changed", "thread/project/updated"] do
      Map.take(event.wire, ["method", "params"])
    end
  end

  defp assert_no_project_events(pid), do: assert(project_events(pid) == [])

  defp changed(project, type),
    do: %{
      "method" => "project/changed",
      "params" => %{"projectId" => project["id"], "changeType" => type}
    }
end
