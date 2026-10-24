defmodule SamgitaCodexDriver.NativePermissionNestedTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/permission_variants_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @sentinel "Owned permission conversion sentinel.\n"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-permission-nested-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    ctx = %{root: root, fixture: fixture, binary: binary}
    TurnFixture.configure_model(ctx, %{})

    # This fixture already owns one features table. Disable external plugin/app
    # startup inside that table before starting the disposable native process.
    config = Path.join(fixture.codex_home, "config.toml")
    source = File.read!(config)
    assert length(String.split(source, "[features]\n")) == 2

    File.write!(
      config,
      String.replace(
        source,
        "[features]\n",
        "[features]\napps = false\nplugins = false\nrecommended_plugins = false\n",
        global: false
      )
    )

    File.mkdir!(Path.join(root, "tmp"))

    for path <- ["readable", "writable", "writable/secrets"],
        do: File.mkdir_p!(Path.join(fixture.workspace, path))

    File.write!(Path.join(fixture.workspace, "readable/sentinel.txt"), @sentinel)
    Map.put(ctx, :special_subpath, tags[:special_subpath])
  end

  @tag scenario: "network_allow"
  test "native enabled null object intersects to no network grant", ctx do
    {pid, id, turn, approval, events} = pending(ctx)

    assert approval.wire["params"]["permissions"] == %{
             "network" => %{"enabled" => true},
             "fileSystem" => nil
           }

    reply_and_assert(
      ctx,
      pid,
      id,
      turn,
      approval,
      events,
      %{"network" => %{"enabled" => nil}},
      nil
    )
  end

  @tag scenario: "read_only"
  test "native null legacy roots and canonical entries yield an empty grant", ctx do
    {pid, id, turn, approval, events} = pending_read(ctx)

    reply_and_assert(
      ctx,
      pid,
      id,
      turn,
      approval,
      events,
      %{
        "fileSystem" => %{
          "read" => nil,
          "write" => nil,
          "entries" => nil,
          "globScanMaxDepth" => nil
        }
      },
      nil
    )
  end

  @tag scenario: "read_only"
  test "native empty legacy roots and canonical entries yield an empty grant", ctx do
    {pid, id, turn, approval, events} = pending_read(ctx)

    reply_and_assert(
      ctx,
      pid,
      id,
      turn,
      approval,
      events,
      %{
        "fileSystem" => %{"read" => [], "write" => [], "entries" => []}
      },
      nil
    )
  end

  @tag scenario: "read_only"
  test "native empty entries take precedence over nonempty legacy read roots", ctx do
    {pid, id, turn, approval, events} = pending_read(ctx)

    reply_and_assert(
      ctx,
      pid,
      id,
      turn,
      approval,
      events,
      %{
        "fileSystem" => %{"read" => [readable(ctx)], "write" => [], "entries" => []}
      },
      nil
    )
  end

  @tag scenario: "read_only"
  test "native null entries fall back to nonempty legacy read roots", ctx do
    {pid, id, turn, approval, events} = pending_read(ctx)

    reply_and_assert(
      ctx,
      pid,
      id,
      turn,
      approval,
      events,
      %{
        "fileSystem" => %{"read" => [readable(ctx)], "write" => [], "entries" => nil}
      },
      %{"read" => [readable(ctx)]}
    )
  end

  for subpath <- [:string, :null, :omitted] do
    @subpath subpath
    @tag scenario: "read_only", special_subpath: subpath
    test "native project_roots with #{@subpath} subpath materializes only the owned read root",
         ctx do
      {pid, id, turn, approval, events} = pending_read(ctx)

      value =
        case @subpath do
          :string -> %{"kind" => "project_roots", "subpath" => "readable"}
          :null -> %{"kind" => "project_roots", "subpath" => nil}
          :omitted -> %{"kind" => "project_roots"}
        end

      permissions = %{
        "fileSystem" => %{
          "entries" => [%{"path" => %{"type" => "special", "value" => value}, "access" => "read"}]
        }
      }

      reply_and_assert(ctx, pid, id, turn, approval, events, permissions, %{
        "read" => [readable(ctx)]
      })
    end
  end

  defp pending_read(ctx) do
    pending = {_pid, _id, _turn, approval, _events} = pending(ctx)

    assert approval.wire["params"]["permissions"] == %{
             "network" => nil,
             "fileSystem" => %{
               "read" => [readable(ctx)],
               "write" => nil,
               "entries" => [entry("read", readable(ctx))]
             }
           }

    pending
  end

  defp pending(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => ctx.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "permission_nested", "version" => "1"}, %{
               "experimentalApi" => true
             })

    roots =
      if ctx.special_subpath in [:null, :omitted],
        do: [readable(ctx)],
        else: [ctx.fixture.workspace]

    started =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "runtimeWorkspaceRoots" => roots,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "ephemeral" => false
      })

    assert started["runtimeWorkspaceRoots"] == roots
    id = started["thread"]["id"]

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned nested permission conversion only"}
      ])

    events = collect(pid, [], &Enum.any?(&1, fn e -> e.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/permissions/requestApproval"
    p = approval.wire["params"]
    assert p["threadId"] == id and p["turnId"] == turn
    assert p["itemId"] == "permission-variant-1" and p["environmentId"] == "local"
    assert p["reason"] == "Owned permission variant only" and p["cwd"] == ctx.fixture.workspace
    assert is_integer(p["startedAtMs"]) and p["startedAtMs"] > 0
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    {pid, id, turn, approval, events}
  end

  defp reply_and_assert(ctx, pid, id, turn, approval, events, permissions, file_system) do
    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{
                  "permissions" => permissions,
                  "scope" => "turn",
                  "strictAutoReview" => nil
                }}
             )

    events =
      collect(
        pid,
        events,
        &(notification(&1, "turn/completed", fn p -> p["turn"]["id"] == turn end) != nil)
      )

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert [%{"text" => "Owned permission variant finished."}] =
             Enum.filter(items, &(&1["type"] == "agentMessage"))

    refute Enum.any?(items, &(&1["type"] in ["commandExecution", "fileChange"]))
    assert Enum.count(events, &(&1.kind == :server_request)) == 1
    assert length(ModelFixture.requests(ctx.fixture)) == 2

    outputs =
      for request <- ModelFixture.requests(ctx.fixture),
          item <- request["input"],
          item["type"] == "function_call_output",
          item["call_id"] == "permission-variant-1",
          do: JSON.decode!(item["output"])

    assert Enum.uniq(outputs) == [
             %{
               "permissions" => %{"network" => nil, "file_system" => file_system},
               "scope" => "turn"
             }
           ]

    refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))

    refute Enum.any?(events, fn e ->
             e.wire["method"] in ["item/started", "item/completed"] and
               get_in(e.wire, ["params", "item", "type"]) in ["commandExecution", "fileChange"]
           end)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{}})

    refute File.exists?(Path.join(ctx.fixture.codex_home, "rules/default.rules"))
    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["readable", "writable"]
    assert File.ls!(readable(ctx)) == ["sentinel.txt"]
    assert File.read!(Path.join(readable(ctx), "sentinel.txt")) == @sentinel
    assert File.ls!(Path.join(ctx.fixture.workspace, "writable")) == ["secrets"]
    assert File.ls!(Path.join(ctx.fixture.workspace, "writable/secrets")) == []
  end

  defp readable(ctx), do: Path.join(ctx.fixture.workspace, "readable")

  defp entry(access, path),
    do: %{"path" => %{"type" => "path", "path" => path}, "access" => access}

  defp collect(pid, events, predicate),
    do: collect(pid, events, predicate, System.monotonic_time(:millisecond) + 20_000)

  defp collect(pid, events, predicate, deadline) do
    assert {:ok, new} = Session.drain(pid)
    events = events ++ new

    cond do
      predicate.(events) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native nested permission deadline")

      true ->
        receive do
        after
          5 -> collect(pid, events, predicate, deadline)
        end
    end
  end
end
