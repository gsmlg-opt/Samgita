defmodule SamgitaCodexDriver.NativeProjectImportMetadataTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @metadata %{
    "color" => "blue",
    "label" => "  λ owned import metadata  ",
    "empty" => ""
  }

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    bytes = File.read!(config)
    on_exit(fn -> assert File.read!(config) == bytes end)
    ctx
  end

  test "nonempty import metadata differs from defaults and survives cold reads without changing history",
       ctx do
    pid = start(ctx)
    selected = durable_thread(ctx, pid, "Owned import metadata member")
    control = durable_thread(ctx, pid, "Owned default metadata member")

    defaults =
      for {suffix, metadata_fields} <- [
            {"omitted", %{}},
            {"null", %{"metadata" => nil}},
            {"empty", %{"metadata" => %{}}}
          ] do
        params =
          Map.merge(
            %{
              "name" => "Owned default #{suffix}",
              "roots" => [],
              "threads" => if(suffix == "omitted", do: [control.id], else: []),
              "idempotencyKey" => "owned-import-default-#{suffix}"
            },
            metadata_fields
          )

        project = call(pid, "project/import", params)["project"]
        assert Map.fetch!(project, "metadata") == %{}
        assert Map.fetch!(project, "name") == "Owned default #{suffix}"
        project
      end

    control_project = hd(defaults)

    params = %{
      "name" => "Owned nonempty import",
      "roots" => [%{"path" => ctx.fixture.workspace}],
      "metadata" => @metadata,
      "threads" => [selected.id],
      "idempotencyKey" => "owned-import-nonempty-metadata"
    }

    imported = call(pid, "project/import", params)["project"]
    assert Map.fetch!(imported, "metadata") == @metadata
    assert Map.fetch!(imported, "name") == "Owned nonempty import"
    assert Map.fetch!(imported, "roots") == [%{"path" => ctx.fixture.workspace}]
    refute imported["id"] in Enum.map(defaults, & &1["id"])

    expected =
      Map.new(defaults, &{Map.fetch!(&1, "id"), %{}}) |> Map.put(imported["id"], @metadata)

    assert_metadata(pid, expected)
    assert_history(pid, selected, imported["id"])
    assert_history(pid, control, control_project["id"])

    # Same-key replay must preserve the original known map and association,
    # even when the new request supplies different nonempty metadata and member.
    replacement = %{"color" => "red", "replayed" => "must not persist"}

    replay =
      call(pid, "project/import", %{
        params
        | "metadata" => replacement,
          "threads" => [control.id]
      })["project"]

    assert Map.fetch!(replay, "id") == imported["id"]
    assert Map.fetch!(replay, "metadata") == @metadata
    assert_metadata(pid, expected)
    assert_history(pid, selected, imported["id"])
    assert_history(pid, control, control_project["id"])
    assert_idle(ctx, pid)

    instance = Session.status(pid).instance_id
    connection = :sys.get_state(pid).connection
    assert :ok = Session.close(pid)
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1

    cold = start(ctx)
    refute Session.status(cold).instance_id == instance
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_metadata(cold, expected)
    assert_history(cold, selected, imported["id"])
    assert_history(cold, control, control_project["id"])
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
  end

  defp durable_thread(ctx, pid, name) do
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => "paginated"})
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    # In the pinned native implementation, includeTurns materializes paginated
    # metadata in the local store. No turn, message or model request is needed.
    native = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert Map.fetch!(native, "id") == id
    assert Map.fetch!(native, "name") == name
    assert Map.fetch!(native, "projectId") == nil
    assert Map.fetch!(native, "turns") == []
    path = Map.fetch!(native, "path")
    bytes = File.read!(path)
    assert byte_size(bytes) > 0
    %{id: id, name: name, path: path, bytes: bytes}
  end

  defp assert_metadata(pid, expected) do
    for {id, metadata} <- expected do
      project = call(pid, "project/read", %{"projectId" => id})["project"]
      assert Map.fetch!(project, "id") == id
      assert Map.fetch!(project, "metadata") == metadata
    end

    listed = call(pid, "project/list", %{"limit" => 100})

    assert Map.new(listed["data"], &{Map.fetch!(&1, "id"), Map.fetch!(&1, "metadata")}) ==
             expected
  end

  defp assert_history(pid, saved, project_id) do
    thread =
      call(pid, "thread/read", %{"threadId" => saved.id, "includeTurns" => true})["thread"]

    assert Map.fetch!(thread, "id") == saved.id
    assert Map.fetch!(thread, "name") == saved.name
    assert Map.fetch!(thread, "historyMode") == "paginated"
    assert Map.fetch!(thread, "projectId") == project_id
    assert Map.fetch!(thread, "turns") == []
    assert Map.fetch!(thread, "path") == saved.path
    assert File.read!(saved.path) == saved.bytes
  end

  defp start(ctx) do
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
               "TMPDIR" => ctx.root,
               "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_project_import_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/started",
               "item/completed"
             ]
           end)
  end
end
