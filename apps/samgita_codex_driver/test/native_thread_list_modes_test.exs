defmodule SamgitaCodexDriver.NativeThreadListModesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @observer Path.expand("../../../scripts/codex/thread_list_io_fixture.py", __DIR__)
  @marker "Owned list mode input λ🙂"
  @name "Owned literal list mode title λ🙂"
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary list mode fixture instructions."

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] == "thread/list" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
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
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nmemories = false\n" <>
        "background_paginated_rollout_migration = false\nlocal_thread_store_compression = false\n"
    )

    inputs =
      Map.new([config, Path.join(ctx.fixture.codex_home, "turn-models.json")], fn path ->
        {path, snapshot(path)}
      end)

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "ordinary native list modes preserve results while only default modes read the rollout",
       ctx do
    warm = start(ctx)
    warm_native = native_id(warm)

    thread =
      call(warm, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0

    turn =
      call(warm, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    events = collect(warm, thread, turn, [], deadline(20_000))

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    assert call(warm, "thread/name/set", %{"threadId" => thread, "name" => @name}) == %{}
    history = call(warm, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert_history(history, thread, turn)
    path = Map.fetch!(history, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    assert [provider] = ModelFixture.requests(ctx.fixture)
    assert Map.fetch!(provider, "model") == "mock-model"

    texts = for item <- provider["input"], part <- Map.get(item, "content", []), do: part["text"]
    assert Enum.count(texts, &(&1 == @marker)) == 1
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    query = %{
      "cwd" => ctx.fixture.workspace,
      "modelProviders" => ["fixture"],
      "sortKey" => "created_at",
      "sortDirection" => "asc",
      "limit" => 100
    }

    # Successful DB-only listing requires the initialized native state handle.
    # Pinned state_db initialization awaits its backfill-complete gate; startup
    # migration/compression readers are explicitly disabled before either start.
    ready = list(ctx, cold, Map.put(query, "useStateDbOnly", true))
    expected = assert_list(ready, thread, ctx.fixture.workspace)

    retained =
      Map.merge(ctx.inputs, %{
        path => snapshot(path),
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    observer = start_observer(ctx, path)

    for {extra, reads?} <- [
          {%{"useStateDbOnly" => true}, false},
          {%{"useStateDbOnly" => false}, true},
          {%{}, true},
          {%{"useStateDbOnly" => true, "originators" => nil}, false},
          {%{"useStateDbOnly" => true, "originators" => []}, false},
          {%{"useStateDbOnly" => true}, false}
        ] do
      observe(observer, reads?, fn ->
        result = list(ctx, cold, Map.merge(query, extra))
        assert assert_list(result, thread, ctx.fixture.workspace) === expected
      end)
    end

    for originators <- [["owned-local-originator"], ["owned-first", "owned-second"]] do
      observe(observer, false, fn ->
        error =
          list_error(
            ctx,
            cold,
            Map.merge(query, %{"useStateDbOnly" => true, "originators" => originators})
          )

        assert error === %{
                 "code" => -32_602,
                 "message" => "originator filtering is not supported by the local app-server"
               }
      end)
    end

    observe(observer, false, fn ->
      assert assert_list(
               list(ctx, cold, Map.put(query, "useStateDbOnly", true)),
               thread,
               ctx.fixture.workspace
             ) === expected
    end)

    stop_observer(observer)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
    assert ModelFixture.requests(ctx.fixture) == [provider]
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert length(Agent.get(ctx.capture, & &1)) == 10
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(cold) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(cold)

    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp assert_history(history, thread, turn) do
    assert history["id"] == thread and history["name"] == @name
    assert history["historyMode"] == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "items" => [user, assistant]}] =
             history["turns"]

    assert user["type"] == "userMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) == [
             %{"type" => "text", "text" => @marker}
           ]

    assert assistant["type"] == "agentMessage" and assistant["text"] == @answer
  end

  defp assert_list(result, thread, cwd) do
    assert [row] = Map.fetch!(result, "data")

    expected = %{
      "id" => thread,
      "name" => @name,
      "cwd" => cwd,
      "modelProvider" => "fixture",
      "source" => "vscode",
      "preview" => @marker
    }

    assert Map.take(row, Map.keys(expected)) === expected
    assert Map.fetch!(result, "nextCursor") === nil
    expected
  end

  defp list(ctx, pid, query) do
    assert {:ok, %{"result" => result}} = list_request(ctx, pid, query)
    result
  end

  defp list_error(ctx, pid, query) do
    assert {:error, %SamgitaProtocolCodex.Error{code: :upstream_error, wire: %{"error" => error}}} =
             list_request(ctx, pid, query)

    error
  end

  defp list_request(ctx, pid, query) do
    id = "owned-list-mode-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => "thread/list", "params" => query}
    before = length(Agent.get(ctx.capture, & &1))
    response = Session.request_native(pid, wire, timeout_ms: 5_000)

    case response do
      {:ok, returned} -> assert returned["id"] === id
      {:error, %SamgitaProtocolCodex.Error{wire: returned}} -> assert returned["id"] === id
    end

    assert [%{wire: recorded, encoded: encoded}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert recorded === wire and JSON.decode!(encoded) === wire
    response
  end

  defp start_observer(ctx, path) do
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python required")

    assert {:ok, connection} =
             Stdio.open(
               executable: python,
               args: ["-B", "-u", @observer, "--path", path],
               inherit_env: [],
               env: %{"CODEX_HOME" => ctx.fixture.codex_home},
               max_message_bytes: 8192
             )

    on_exit(fn -> assert :ok = Stdio.close(connection) end)

    assert %{"status" => "ready", "pid" => native, "path" => ^path} =
             observer_reply(connection.port)

    assert is_integer(native)
    %{port: connection.port, native: native, connection: connection}
  end

  defp observe(observer, reads?, operation) do
    send_observer(observer.port, "arm")
    assert %{"status" => "armed", "sequence" => sequence} = observer_reply(observer.port)
    operation.()
    send_observer(observer.port, "drain")

    assert %{"status" => "drained", "sequence" => ^sequence, "events" => events} =
             observer_reply(observer.port)

    if reads? do
      assert 32 in events and 1 in events and 16 in events
    else
      assert events === []
    end
  end

  defp stop_observer(observer) do
    send_observer(observer.port, "stop")
    assert %{"status" => "stopped", "sequence" => 9} = observer_reply(observer.port)
    port = observer.port
    assert_receive {^port, {:exit_status, 0}}, 5_000
    assert :ok = Stdio.close(observer.connection)
    refute File.exists?("/proc/#{observer.native}")
  end

  defp send_observer(port, command),
    do: assert(Port.command(port, JSON.encode!(%{"command" => command}) <> "\n"))

  defp observer_reply(port, buffer \\ <<>>) do
    receive do
      {^port, {:data, bytes}} ->
        buffer = buffer <> bytes
        assert byte_size(buffer) <= 8192

        case String.split(buffer, "\n", parts: 2) do
          [line, ""] -> JSON.decode!(line)
          [_partial] -> observer_reply(port, buffer)
          _ -> flunk("Unexpected extra observer barrier output")
        end

      {^port, {:exit_status, status}} ->
        flunk("Observer exited before barrier: #{status}")
    after
      5_000 -> flunk("Observer barrier deadline")
    end
  end

  defp collect(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         params(events, "turn/completed"),
         &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "Native list seed turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected list seed gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp call(pid, method, params) do
    id = "owned-list-setup-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

    result
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp native_id(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "RUST_LOG" => "off",
               "NO_COLOR" => "1"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_thread_list_modes", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
