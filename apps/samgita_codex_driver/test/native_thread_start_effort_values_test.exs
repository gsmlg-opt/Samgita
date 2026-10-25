defmodule SamgitaCodexDriver.NativeThreadStartEffortValuesTest do
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
  @instructions "Owned fixed thread-start effort fixture instructions."
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
      if length(Agent.get(state.capture, & &1)) < 8 and byte_size(encoded) <= 4096 do
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

    # The synthetic catalog deliberately supplies no model reasoning default.
    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Synthetic low metadata"},
        %{"effort" => "high", "description" => "Synthetic high metadata"}
      ],
      "supports_reasoning_summary_parameter" => true,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    effort =
      case tags[:configured_effort] do
        nil -> ""
        "low" -> ~s(model_reasoning_effort = "low"\n)
      end

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      effort <>
        ~s(model_reasoning_summary = "auto"\ncli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "unset effort is explicit null in independent native start frames and absent at inference",
       ctx do
    scenario(ctx, nil, "owned-thread-start-effort-unset")
  end

  @tag configured_effort: "low"
  test "configured low survives independent native start frames and reaches inference", ctx do
    scenario(ctx, "low", "owned-thread-start-effort-low")
  end

  defp scenario(ctx, expected_effort, marker) do
    assert File.ls!(ctx.fixture.workspace) == []
    pid = start(ctx)

    result =
      request(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false
      })

    assert Map.fetch!(result, "reasoningEffort") === expected_effort
    thread = Map.fetch!(result, "thread") |> Map.fetch!("id")
    assert is_binary(thread)

    # This is a separately received native notification, never reconstructed
    # from the response's thread object or inferred from source equality.
    started = await_started(pid, thread, [], deadline(5000))
    assert Map.fetch!(started, "reasoningEffort") === expected_effort
    assert ModelFixture.requests(ctx.fixture) == []

    # A changed summary supplies an applied settings barrier. The ACK alone
    # does not show that the future turn has captured the new settings.
    assert call(pid, "thread/settings/update", %{
             "threadId" => thread,
             "summary" => "concise"
           }) == %{}

    settings = await_settings(pid, thread, [], deadline(5000))
    assert Map.fetch!(settings, "effort") === expected_effort
    assert Map.fetch!(settings, "summary") == "concise"
    assert ModelFixture.requests(ctx.fixture) == []

    turn =
      request(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn)
    events = complete_turn(pid, thread, turn, [], deadline(20_000))

    assert %{"item" => %{"type" => "agentMessage", "text" => @answer}} =
             notification(events, "item/completed", fn params ->
               params["threadId"] == thread and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)

    assert [provider] = ModelFixture.requests(ctx.fixture)
    assert Map.fetch!(provider, "model") == "mock-model"
    reasoning = Map.fetch!(provider, "reasoning")
    assert Map.fetch!(reasoning, "summary") == "concise"

    case expected_effort do
      nil -> refute Map.has_key?(reasoning, "effort")
      "low" -> assert Map.fetch!(reasoning, "effort") == "low"
    end

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(provider["input"])

    user_texts =
      for item <- provider["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
    assert length(Agent.get(ctx.capture, & &1)) == 2
    finish(ctx, pid)
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-start-effort-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp await_started(pid, thread, events, until) do
    events = drain(pid, events)

    case notification(events, "thread/started", &(&1["thread"]["id"] == thread)) do
      nil ->
        wait(pid, until, "native thread-start notification deadline")
        await_started(pid, thread, events, until)

      params ->
        Map.fetch!(params, "thread")
    end
  end

  defp await_settings(pid, thread, events, until) do
    events = drain(pid, events)

    found =
      notification(events, "thread/settings/updated", fn params ->
        params["threadId"] == thread and params["threadSettings"]["summary"] == "concise"
      end)

    if found do
      Map.fetch!(found, "threadSettings")
    else
      wait(pid, until, "native thread-start applied settings deadline")
      await_settings(pid, thread, events, until)
    end
  end

  defp complete_turn(pid, thread, turn, events, until) do
    events = drain(pid, events)

    found =
      notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if found do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} = found
      events
    else
      wait(pid, until, "native thread-start effort turn deadline")
      complete_turn(pid, thread, turn, events, until)
    end
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native effort scenario event buffer exceeded its bound"
    events
  end

  defp wait(pid, until, message) do
    assert Session.status(pid).phase == :ready
    assert System.monotonic_time(:millisecond) < until, message

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during effort scenario")
    after
      10 -> :ok
    end
  end

  defp finish(ctx, pid) do
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
               %{"name" => "owned_thread_start_effort_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
