defmodule SamgitaCodexDriver.NativeClientRequestCaptureTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @metadata %{"label" => "  λ owned capture  ", "empty" => ""}

  # Test-local synthetic request capture only. No generic transport, production
  # logging, persisted payload collection, reply synthesis or native-output edits.
  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error
    @methods ~w(thread/start thread/resume project/import project/read thread/readState/update)

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      opts = Keyword.delete(opts, :capture)
      with {:ok, state} <- Stdio.open(opts), do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in @methods and Map.has_key?(wire, "id") do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      entries = Agent.get(state.capture, & &1)

      if length(entries) < 64 and byte_size(encoded) <= 4096 do
        record_send(state, encoded, wire)
      else
        {:error, Error.new(:test_capture_overflow), state}
      end
    end

    defp record_send(state, encoded, wire) do
      with {:ok, next} <- Stdio.send(state, encoded) do
        Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
        {:ok, next}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

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

    config_bytes = File.read!(config)
    assert config_bytes =~ "approval_policy = \"on-request\""
    on_exit(fn -> assert File.read!(config) == config_bytes end)
    capture = start_supervised!({Agent, fn -> [] end})
    Map.put(ctx, :capture, capture)
  end

  test "captured thread/start params select policy and roots without inheriting the configured default",
       ctx do
    extra = Path.join(ctx.root, "owned-extra")
    File.mkdir!(extra)
    roots = [ctx.fixture.workspace, extra]
    pid = start(ctx)
    baseline = captured_call(ctx, pid, "thread/start", start_params(ctx))

    selected =
      captured_call(
        ctx,
        pid,
        "thread/start",
        Map.merge(start_params(ctx), %{
          "approvalPolicy" => "never",
          "runtimeWorkspaceRoots" => roots
        })
      )

    assert baseline["approvalPolicy"] == "on-request"
    assert selected["approvalPolicy"] == "never"
    refute baseline["thread"]["id"] == selected["thread"]["id"]
    assert selected["runtimeWorkspaceRoots"] == roots
    saved = durable(ctx, pid, selected["thread"]["id"], "Owned captured start")
    assert creation_meta(saved.path, saved.id)["runtime_workspace_roots"] == roots
    assert creation_meta(saved.path, saved.id)["cwd"] == ctx.fixture.workspace
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
  end

  test "captured thread/resume roots replace saved roots and survive a separate native process",
       ctx do
    original_extra = Path.join(ctx.root, "owned-original")
    replacement_extra = Path.join(ctx.root, "owned-replacement")
    File.mkdir!(original_extra)
    File.mkdir!(replacement_extra)
    original = [ctx.fixture.workspace, original_extra]
    expected = [ctx.fixture.workspace, replacement_extra]
    first = start(ctx)

    started =
      captured_call(
        ctx,
        first,
        "thread/start",
        Map.put(start_params(ctx), "runtimeWorkspaceRoots", original)
      )

    saved = durable(ctx, first, started["thread"]["id"], "Owned captured resume")
    assert creation_meta(saved.path, saved.id)["runtime_workspace_roots"] == original
    assert :ok = Session.close(first)

    cold = start(ctx)
    assert_unloaded(cold)

    resumed =
      captured_call(ctx, cold, "thread/resume", %{
        "threadId" => saved.id,
        "runtimeWorkspaceRoots" => expected,
        "permissions" => ":read-only",
        "excludeTurns" => true
      })

    assert resumed["thread"]["id"] == saved.id
    assert resumed["runtimeWorkspaceRoots"] == expected
    refute resumed["runtimeWorkspaceRoots"] == original
    assert resumed["sandbox"] == %{"type" => "readOnly", "networkAccess" => false}
    assert_history(cold, saved, nil)
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
    assert creation_meta(saved.path, saved.id)["runtime_workspace_roots"] == original
    assert latest_roots(saved.path, saved.id) == expected
    checkpoint = File.read!(saved.path)

    verify = start(ctx)
    assert_unloaded(verify)
    assert File.read!(saved.path) == checkpoint

    restored =
      captured_call(ctx, verify, "thread/resume", %{
        "threadId" => saved.id,
        "excludeTurns" => true
      })

    assert restored["runtimeWorkspaceRoots"] == expected
    refute restored["runtimeWorkspaceRoots"] == original
    assert_history(verify, saved, nil)
    assert_idle(ctx, verify)
    assert :ok = Session.close(verify)
  end

  test "captured project/import and project/read select durable metadata, membership and replay identity",
       ctx do
    pid = start(ctx)
    params_for_members = Map.put(start_params(ctx), "historyMode", "paginated")
    selected_id = captured_call(ctx, pid, "thread/start", params_for_members)["thread"]["id"]
    control_id = captured_call(ctx, pid, "thread/start", params_for_members)["thread"]["id"]
    selected = durable(ctx, pid, selected_id, "Owned selected import member")
    control = durable(ctx, pid, control_id, "Owned control import member")

    control_params = %{
      "name" => "Owned default capture",
      "roots" => [],
      "threads" => [control.id],
      "idempotencyKey" => "owned-captured-control"
    }

    control_project = captured_call(ctx, pid, "project/import", control_params)["project"]

    params = %{
      "name" => "Owned selected capture",
      "roots" => [%{"path" => ctx.fixture.workspace}],
      "metadata" => @metadata,
      "threads" => [selected.id],
      "idempotencyKey" => "owned-captured-selected"
    }

    project = captured_call(ctx, pid, "project/import", params)["project"]
    refute project["id"] == control_project["id"]
    assert project["name"] == params["name"]
    assert project["roots"] == params["roots"]
    assert project["metadata"] == @metadata
    assert control_project["metadata"] == %{}
    assert_history(pid, selected, project["id"])
    assert_history(pid, control, control_project["id"])
    assert File.read!(selected.path) == selected.bytes
    assert File.read!(control.path) == control.bytes

    replay =
      captured_call(ctx, pid, "project/import", %{
        params
        | "metadata" => %{"replayed" => "must not persist"},
          "threads" => [control.id]
      })["project"]

    assert replay["id"] == project["id"]
    assert replay["metadata"] == @metadata
    assert_projects(ctx, pid, project["id"], control_project["id"])
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert_unloaded(cold)
    assert_projects(ctx, cold, project["id"], control_project["id"])
    assert_history(cold, selected, project["id"])
    assert_history(cold, control, control_project["id"])
    assert File.read!(selected.path) == selected.bytes
    assert File.read!(control.path) == control.bytes
    assert_unloaded(cold)
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
  end

  test "captured read-state operation variants change persisted state and stale revisions cannot overwrite it",
       ctx do
    pid = start(ctx)
    id = captured_call(ctx, pid, "thread/start", start_params(ctx))["thread"]["id"]
    saved = durable(ctx, pid, id, "Owned captured read state")
    initial = read(pid, id)["readState"]
    assert initial["firstUnread"] == nil

    unread_params = %{
      "threadId" => id,
      "expectedRevision" => initial["revision"],
      "operation" => %{"type" => "unread"}
    }

    unread = captured_call(ctx, pid, "thread/readState/update", unread_params)["readState"]
    assert unread["firstUnread"] == %{"type" => "threadStart"}
    refute unread["revision"] == initial["revision"]
    assert read(pid, id)["readState"] == unread

    read_params = %{
      "threadId" => id,
      "expectedRevision" => unread["revision"],
      "operation" => %{"type" => "read"}
    }

    marked = captured_call(ctx, pid, "thread/readState/update", read_params)["readState"]
    assert marked["firstUnread"] == nil
    refute marked["revision"] in [initial["revision"], unread["revision"]]
    assert read(pid, id)["readState"] == marked
    assert File.read!(saved.path) == saved.bytes
    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)

    cold = start(ctx)
    assert_unloaded(cold)
    assert read(cold, id)["readState"] == marked
    assert_history(cold, saved, nil)
    before = capture_count(ctx)

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => request_id, "error" => error}}} =
             Session.request(cold, "thread/readState/update", unread_params)

    assert error == %{
             "code" => -32_600,
             "message" => "read state changed",
             "data" => %{"reason" => "readStateConflict", "readState" => marked}
           }

    assert_capture(ctx, before, request_id, "thread/readState/update", unread_params)
    assert read(cold, id)["readState"] == marked
    assert File.read!(saved.path) == saved.bytes
    assert_unloaded(cold)
    assert_idle(ctx, cold)
    assert :ok = Session.close(cold)
  end

  defp captured_call(ctx, pid, method, params) do
    before = capture_count(ctx)
    assert {:ok, %{"id" => id, "result" => result}} = Session.request(pid, method, params)
    assert_capture(ctx, before, id, method, params)
    result
  end

  defp assert_capture(ctx, before, id, method, params) do
    assert [entry] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    # Exact submitted wire, including absence of implicit parameters, and actual
    # upstream response correlation; no digest-only or canonical-sibling evidence.
    assert entry.wire == %{"id" => id, "method" => method, "params" => params}
    assert JSON.decode!(entry.encoded) == entry.wire
  end

  defp capture_count(ctx), do: Agent.get(ctx.capture, &length/1)

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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

    connection = :sys.get_state(pid).connection
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_request_capture", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp start_params(ctx),
    do: %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "sandbox" => "read-only",
      "ephemeral" => false,
      "historyMode" => "legacy"
    }

  defp durable(_ctx, pid, id, name) do
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    thread = read(pid, id)["thread"]
    assert thread["id"] == id
    assert thread["name"] == name
    assert thread["turns"] == []
    assert thread["projectId"] == nil
    path = Map.fetch!(thread, "path")
    bytes = File.read!(path)
    assert byte_size(bytes) > 0
    %{id: id, name: name, path: path, bytes: bytes}
  end

  defp read(pid, id), do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})

  defp assert_history(pid, saved, project_id) do
    thread = read(pid, saved.id)["thread"]
    assert thread["id"] == saved.id
    assert thread["name"] == saved.name
    assert thread["path"] == saved.path
    assert thread["turns"] == []
    assert thread["projectId"] == project_id
  end

  defp assert_projects(ctx, pid, selected, control) do
    selected_result =
      captured_call(ctx, pid, "project/read", %{"projectId" => selected})["project"]

    control_result = captured_call(ctx, pid, "project/read", %{"projectId" => control})["project"]
    assert selected_result["id"] == selected
    assert selected_result["metadata"] == @metadata
    assert control_result["id"] == control
    assert control_result["metadata"] == %{}
    refute selected_result["id"] == control_result["id"]
  end

  defp rows(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp creation_meta(path, id) do
    assert [meta] =
             for(
               row <- rows(path),
               row["type"] == "session_meta",
               row["payload"]["id"] == id,
               do: row["payload"]
             )

    meta
  end

  defp latest_roots(path, id) do
    snapshots =
      for row <- rows(path),
          row["type"] == "event_msg",
          row["payload"]["type"] == "thread_settings_applied",
          row["payload"]["thread_id"] == id,
          do: row["payload"]["thread_settings"]["runtime_workspace_roots"]

    assert snapshots != []
    List.last(snapshots)
  end

  defp assert_unloaded(pid),
    do: assert(call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ])
           )
  end
end
