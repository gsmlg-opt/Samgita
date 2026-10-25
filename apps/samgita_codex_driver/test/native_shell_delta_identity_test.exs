defmodule SamgitaCodexDriver.NativeShellDeltaIdentityTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @effects "owned-shell-effects.log"

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

      if wire["method"] == "thread/shellCommand" do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
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

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    capture = start_supervised!({Agent, fn -> [] end})
    Map.put(ctx, :capture, capture)
  end

  test "native shell deltas bind distinct turns and cold history never repeats effects", ctx do
    pid = start(ctx)

    thread =
      TurnFixture.thread(ctx, pid, %{
        "historyMode" => "paginated",
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    config = Path.join(ctx.fixture.codex_home, "config.toml")
    config_bytes = File.read!(config)
    effects = Path.join(ctx.fixture.workspace, @effects)
    refute File.exists?(effects)

    records =
      for {label, index} <- Enum.with_index(["alpha", "beta"], 1) do
        output = "owned-shell-output-#{label}\n"
        effect = "owned-shell-effect-#{label}"

        command =
          "printf '%s\\n' 'owned-shell-output-#{label}'; " <>
            "printf '%s\\n' '#{effect}' >> #{@effects}"

        params = %{"threadId" => thread, "command" => command, "timeoutMs" => 5_000}
        before = length(Agent.get(ctx.capture, & &1))
        assert call(pid, "thread/shellCommand", params) === %{}
        captured = Agent.get(ctx.capture, & &1)
        assert length(captured) == before + 1
        assert %{"method" => "thread/shellCommand", "params" => ^params} = List.last(captured)
        events = collect(pid, [], deadline(20_000))
        record = assert_shell(events, thread, output)

        expected_effects =
          ["alpha", "beta"]
          |> Enum.take(index)
          |> Enum.map_join("", &"owned-shell-effect-#{&1}\n")

        assert File.read!(effects) === expected_effects
        assert ModelFixture.requests(ctx.fixture) == []
        record
      end

    assert length(Enum.uniq(Enum.map(records, & &1.turn))) == 2
    assert length(Enum.uniq(Enum.map(records, & &1.item["id"]))) == 2
    saved = history(pid, thread)
    assert_history(saved, records)
    expected_effects = "owned-shell-effect-alpha\nowned-shell-effect-beta\n"
    assert_owned_state(ctx, pid, effects, expected_effects, config, config_bytes)

    original = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(original)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{original}")
    cold = start(ctx)
    replacement = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(replacement) and replacement != original
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert history(cold, thread) === saved
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert length(Agent.get(ctx.capture, & &1)) == 2
    assert_owned_state(ctx, cold, effects, expected_effects, config, config_bytes)
    assert :ok = Session.close(cold)
    refute File.exists?("/proc/#{replacement}")
  end

  defp assert_shell(events, thread, output) do
    assert [%{"threadId" => ^thread, "turn" => %{"id" => turn}}] =
             params(events, "turn/started")

    assert is_binary(turn) and turn != ""

    assert [%{"threadId" => ^thread, "turnId" => ^turn, "item" => started}] =
             params(events, "item/started")

    assert %{"id" => item, "type" => "commandExecution", "source" => "userShell"} = started
    assert is_binary(item) and item != ""
    assert started["status"] == "inProgress"
    deltas = params(events, "item/commandExecution/outputDelta")
    assert deltas != []

    for delta <- deltas do
      assert Map.fetch!(delta, "threadId") === thread
      assert Map.fetch!(delta, "turnId") === turn
      assert Map.fetch!(delta, "itemId") === item
      assert is_binary(Map.fetch!(delta, "delta")) and delta["delta"] != ""
    end

    assert Enum.map_join(deltas, "", &Map.fetch!(&1, "delta")) === output

    assert [%{"threadId" => ^thread, "turnId" => ^turn, "item" => completed}] =
             params(events, "item/completed")

    assert completed["id"] === item
    assert completed["type"] == "commandExecution"
    assert completed["source"] == "userShell"
    assert completed["status"] == "completed"
    assert completed["exitCode"] === 0
    assert completed["aggregatedOutput"] === output

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    methods = Enum.map(events, & &1.wire["method"])
    started_index = Enum.find_index(methods, &(&1 == "item/started"))
    completed_index = Enum.find_index(methods, &(&1 == "item/completed"))
    assert Enum.find_index(methods, &(&1 == "turn/started")) < started_index
    assert completed_index < Enum.find_index(methods, &(&1 == "turn/completed"))

    for {method, index} <- Enum.with_index(methods),
        method == "item/commandExecution/outputDelta" do
      assert started_index < index and index < completed_index
    end

    %{turn: turn, item: completed}
  end

  defp assert_history(turns, records) do
    assert Enum.map(turns, & &1["id"]) === Enum.map(records, & &1.turn)

    for {turn, record} <- Enum.zip(turns, records) do
      assert turn["status"] == "completed"
      assert turn["items"] === [record.item]
    end
  end

  defp history(pid, thread),
    do:
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]["turns"]

  defp assert_owned_state(ctx, pid, effects, expected, config, config_bytes) do
    assert File.read!(effects) === expected
    assert File.ls!(ctx.fixture.workspace) == [@effects]
    assert File.read!(config) === config_bytes
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.read!(ctx.fixture.requests) == "[]"
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp collect(pid, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "shell event count exceeded its bound"

    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576,
           "shell event bytes exceeded their bound"

    if params(events, "turn/completed") != [] do
      events
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native shell completion deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during native shell")
      after
        10 -> :ok
      end

      collect(pid, events, until)
    end
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
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_shell_delta_identity", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true
               }
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
end
