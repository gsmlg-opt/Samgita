defmodule SamgitaCodexDriver.NativeMultiAgentModeValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed multi-agent no-op fixture instructions."
  @hint "Owned ignored legacy multi-agent hint."
  @answer "Deterministic local fixture answer"

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

      if wire["method"] in ["thread/start", "turn/start"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
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
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "auto"\n) <>
        "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "thread start ignores each published legacy mode and retains fixed native behavior", ctx do
    pid = start(ctx)

    threads =
      for {{label, extra}, index} <- Enum.with_index(cases(), 1) do
        before = ModelFixture.requests(ctx.fixture)
        result = request(ctx, pid, "thread/start", Map.merge(thread_params(ctx), extra))
        assert Map.fetch!(result, "multiAgentMode") == "explicitRequestOnly"
        assert ModelFixture.requests(ctx.fixture) == before
        thread = result["thread"]["id"]
        assert is_binary(thread)
        baseline = snapshot(ctx, pid, thread, "concise")
        marker = "owned-thread-legacy-mode-#{label}"
        turn = turn(ctx, pid, thread, marker, %{}, index)
        assert snapshot(ctx, pid, thread, "detailed") == baseline
        assert_history(pid, thread, [turn])
        thread
      end

    assert length(Enum.uniq(threads)) == 5
    assert length(Agent.get(ctx.capture, & &1)) == 10
    finish(ctx, pid, 5)
  end

  test "turn start ignores each published legacy mode without changing live settings or instructions",
       ctx do
    pid = start(ctx)
    result = request(ctx, pid, "thread/start", thread_params(ctx))
    assert Map.fetch!(result, "multiAgentMode") == "explicitRequestOnly"
    thread = result["thread"]["id"]

    turns =
      for {{label, extra}, index} <- Enum.with_index(cases(), 1) do
        baseline = snapshot(ctx, pid, thread, "concise")
        marker = "owned-turn-legacy-mode-#{label}"
        turn = turn(ctx, pid, thread, marker, extra, index)
        assert snapshot(ctx, pid, thread, "detailed") == baseline
        turn
      end

    assert length(Enum.uniq(turns)) == 5
    assert_history(pid, thread, turns)
    assert length(Agent.get(ctx.capture, & &1)) == 6
    finish(ctx, pid, 5)
  end

  # rust-v0.163.0 explicitly ignores these deprecated request fields. These
  # cases qualify their native no-op behavior, never active delegation. The
  # legacy deserializer-only "none" alias is not a published schema alternative.
  defp cases do
    [
      {"omitted", %{}},
      {"null", %{"multiAgentMode" => nil}},
      {"explicit", %{"multiAgentMode" => "explicitRequestOnly"}},
      {"proactive", %{"multiAgentMode" => "proactive"}},
      {"custom", %{"multiAgentMode" => %{"custom" => @hint}}}
    ]
  end

  defp thread_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "sandbox" => "danger-full-access",
      "approvalPolicy" => "never",
      "ephemeral" => false,
      "historyMode" => "legacy"
    }
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-legacy-mode-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp turn(ctx, pid, thread, marker, extra, count) do
    params =
      Map.merge(
        %{"threadId" => thread, "input" => [%{"type" => "text", "text" => marker}]},
        extra
      )

    turn = request(ctx, pid, "turn/start", params)["turn"]["id"]
    events = complete_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{"item" => %{"type" => "agentMessage", "text" => @answer}} =
             notification(events, "item/completed", fn params ->
               params["threadId"] == thread and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)

    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    request = List.last(requests)
    assert request["model"] == "mock-model"
    refute Map.has_key?(request, "instructions")

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
    refute JSON.encode!(request["input"]) =~ @hint
    turn
  end

  # Local functional collector deliberately avoids the retained completion
  # helper's separate approval assertion.
  defp complete_turn(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    found =
      notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if found do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} = found
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "native legacy-mode turn deadline"
      wait(pid, 20)
      complete_turn(pid, thread, turn, events, deadline)
    end
  end

  # A changed summary gives an independent applied public snapshot; it supplies
  # neither multiAgentMode nor turn input. An acknowledgement is insufficient.
  defp snapshot(ctx, pid, thread, summary) do
    before = ModelFixture.requests(ctx.fixture)

    assert call(pid, "thread/settings/update", %{"threadId" => thread, "summary" => summary}) ==
             %{}

    settings =
      snapshot_event(pid, thread, summary, [], System.monotonic_time(:millisecond) + 5000)

    assert ModelFixture.requests(ctx.fixture) == before
    assert Map.fetch!(settings, "multiAgentMode") == "explicitRequestOnly"
    Map.take(settings, ["model", "modelProvider", "effort", "personality", "multiAgentMode"])
  end

  defp snapshot_event(pid, thread, summary, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    found =
      notification(events, "thread/settings/updated", fn params ->
        params["threadId"] == thread and params["threadSettings"]["summary"] == summary
      end)

    if found do
      found["threadSettings"]
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "native legacy-mode snapshot deadline"

      wait(pid, 10)
      snapshot_event(pid, thread, summary, events, deadline)
    end
  end

  defp wait(pid, milliseconds) do
    assert Session.status(pid).phase == :ready

    receive do
      {:codex_driver, ^pid, :events_available} ->
        :ok

      {:codex_driver, ^pid, {:gap, _}} ->
        flunk("Unexpected event gap during legacy-mode scenario")
    after
      milliseconds -> :ok
    end
  end

  defp assert_history(pid, thread, turns) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert saved["id"] == thread
    assert Enum.map(saved["turns"], & &1["id"]) == turns
    assert Enum.all?(saved["turns"], &(&1["status"] == "completed"))
  end

  defp finish(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "owned_multi_agent_mode_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
