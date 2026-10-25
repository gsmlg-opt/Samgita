defmodule SamgitaCodexDriver.NativeThreadStartConfigValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed ordinary thread-start config fixture instructions."
  @answer "Deterministic local fixture answer"
  @markers ["Owned per-thread config low λ", "Owned root config high 🙂"]
  @captured_methods ["thread/start", "turn/start"]

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
      if length(Agent.get(state.capture, & &1)) < 5 and byte_size(encoded) <= 4096 do
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

    # Supported presets supply no default: actual root and request values must
    # account for the independent low/high outcomes.
    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Synthetic low metadata"},
        %{"effort" => "high", "description" => "Synthetic high metadata"}
      ],
      "supports_reasoning_summary_parameter" => true,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(model_reasoning_effort = "high"\nmodel_reasoning_summary = "concise"\n) <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      for path <- [config, Path.join(ctx.fixture.codex_home, "turn-models.json")], into: %{} do
        {path, snapshot(path)}
      end

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "per-thread effort overrides root config while null and omission retain it", ctx do
    assert File.ls!(ctx.fixture.workspace) == []
    pid = start(ctx)
    native = native_id(ctx, pid)

    base = %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "historyMode" => "legacy",
      "ephemeral" => false
    }

    start_params = [
      Map.put(base, "config", %{"model_reasoning_effort" => "low"}),
      Map.put(base, "config", nil),
      base
    ]

    # All three native threads exist before inference or settings changes.
    # Omit request cwd so the ordinary process-cwd config fallback is used.
    threads =
      for {params, effort} <- Enum.zip(start_params, ["low", "high", "high"]) do
        result = call(ctx, pid, "thread/start", params)
        assert Map.fetch!(result, "reasoningEffort") == effort
        thread = Map.fetch!(result, "thread") |> Map.fetch!("id")
        assert is_binary(thread) and byte_size(thread) > 0

        {started, _events} =
          await_notice(
            pid,
            "thread/started",
            &(&1["thread"]["id"] == thread),
            [],
            deadline(5_000)
          )

        assert Map.fetch!(started, "thread")["reasoningEffort"] == effort
        thread
      end

    assert length(Enum.uniq(threads)) == 3
    assert [low_thread, high_thread, empty_thread] = threads
    assert ModelFixture.requests(ctx.fixture) == []
    assert_empty(ctx, pid, empty_thread)

    # Concise -> auto is a real change. The native applied-settings notice
    # independently preserves each thread's effort; the update never sets it.
    for {thread, effort} <- Enum.zip([low_thread, high_thread], ["low", "high"]) do
      assert call(ctx, pid, "thread/settings/update", %{
               "threadId" => thread,
               "summary" => "auto"
             }) == %{}

      {notice, _events} =
        await_notice(
          pid,
          "thread/settings/updated",
          &(&1["threadId"] == thread and &1["threadSettings"]["summary"] == "auto"),
          [],
          deadline(5_000)
        )

      assert Map.fetch!(notice, "threadSettings")["effort"] == effort
      assert Map.fetch!(notice, "threadSettings")["summary"] == "auto"
      assert ModelFixture.requests(ctx.fixture) == []
    end

    rows =
      for {thread, marker} <- Enum.zip([low_thread, high_thread], @markers) do
        complete_turn(ctx, pid, thread, marker)
      end

    assert length(Enum.uniq(Enum.map(rows, & &1.id))) == 2
    assert [low_provider, high_provider] = ModelFixture.requests(ctx.fixture)

    for {provider, row, effort} <-
          Enum.zip([[low_provider, high_provider], rows, ["low", "high"]]) do
      assert_provider(provider, row, effort)
    end

    journal = snapshot(ctx.fixture.requests)

    for row <- rows, do: assert_history(ctx, pid, row)
    assert_empty(ctx, pid, empty_thread)
    assert snapshot(ctx.fixture.requests) === journal

    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 5
    assert length(Enum.uniq(Enum.map(frames, & &1.wire["id"]))) == 5

    expected =
      Enum.map(start_params, &{"thread/start", &1}) ++
        Enum.map(rows, fn row ->
          {"turn/start",
           %{"threadId" => row.thread, "input" => [%{"type" => "text", "text" => row.marker}]}}
        end)

    assert Enum.map(frames, &{&1.wire["method"], &1.wire["params"]}) === expected
    assert_retained(ctx, pid, journal)
    close(pid, native)
    assert snapshot(ctx.fixture.requests) === journal
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp complete_turn(ctx, pid, thread, marker) do
    turn =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0

    {completed, events} =
      await_notice(
        pid,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn),
        [],
        deadline(20_000)
      )

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             completed

    items =
      for event <- events,
          event.wire["method"] == "item/completed",
          params = event.wire["params"],
          params["threadId"] == thread and params["turnId"] == turn,
          do: params["item"]

    assert [user, assistant] = items
    assert_user(user, marker)
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
    assert is_binary(user["id"]) and is_binary(assistant["id"])
    refute user["id"] == assistant["id"]
    %{id: turn, thread: thread, marker: marker, user: user["id"], assistant: assistant["id"]}
  end

  defp assert_provider(provider, row, effort) do
    assert Map.fetch!(provider, "model") == "mock-model"
    assert Map.fetch!(provider, "reasoning") === %{"effort" => effort, "summary" => "auto"}
    thread = row.thread
    turn = row.id

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(provider["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(provider["input"])

    user_texts =
      for item <- provider["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == row.marker)) == 1

    for other <- @markers -- [row.marker] do
      refute Enum.any?(user_texts, &String.contains?(&1, other))
    end
  end

  defp assert_history(ctx, pid, row) do
    saved = read(ctx, pid, row.thread)
    assert Map.fetch!(saved, "id") == row.thread
    assert Map.fetch!(saved, "historyMode") == "legacy"
    assert [turn] = Map.fetch!(saved, "turns")
    assert Map.fetch!(turn, "id") == row.id
    assert Map.fetch!(turn, "status") == "completed"
    assert [user, assistant] = Map.fetch!(turn, "items")
    # Pinned legacy reconstruction allocates item-1/item-2 for these two
    # ordinary records; it does not preserve their streamed UUIDs.
    assert Map.fetch!(user, "id") == "item-1"
    assert Map.fetch!(assistant, "id") == "item-2"
    assert_user(user, row.marker)
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
  end

  defp assert_empty(ctx, pid, thread) do
    # A never-submitted legacy thread deliberately has no materialized rollout.
    # Check that real boundary, rather than treating a metadata stub as history.
    id = "owned-thread-config-empty-#{System.unique_integer([:positive, :monotonic])}"

    message =
      "thread #{thread} is not materialized yet; includeTurns is unavailable before first user message"

    assert {:error,
            %SamgitaProtocolCodex.Error{
              code: :upstream_error,
              wire: %{"id" => ^id, "error" => %{"code" => -32_600, "message" => ^message}}
            }} =
             Session.request_native(
               pid,
               %{
                 "id" => id,
                 "method" => "thread/read",
                 "params" => %{"threadId" => thread, "includeTurns" => true}
               },
               timeout_ms: 5_000
             )

    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})["thread"]

    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "legacy"
    # Metadata-only turns are a stub. Exact provider/captured-call assertions
    # separately require that no C turn or inference was ever submitted.
    assert Map.fetch!(saved, "turns") == []
  end

  defp assert_user(user, marker) do
    assert %{"type" => "userMessage", "content" => content} = user
    assert [%{"type" => "text", "text" => ^marker}] = content
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-thread-start-config-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    response = Session.request_native(pid, wire, timeout_ms: 5_000)

    case response do
      {:error, %SamgitaProtocolCodex.Error{wire: %{"error" => error}}} ->
        flunk("Native thread config #{method}: #{inspect(error)}")

      _ ->
        :ok
    end

    assert {:ok, %{"id" => ^id, "result" => result}} = response

    captured = Agent.get(ctx.capture, &Enum.drop(&1, before))

    if method in @captured_methods do
      assert [%{encoded: encoded, wire: recorded}] = captured
      assert recorded === wire
      assert JSON.decode!(encoded) === wire
    else
      assert captured == []
    end

    result
  end

  defp await_notice(pid, method, predicate, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native thread config event buffer exceeded its count bound"
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during thread config")
    after
      0 -> :ok
    end

    case notification(events, method, predicate) do
      nil ->
        assert System.monotonic_time(:millisecond) < until,
               "native thread config #{method} deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during thread config")
        after
          10 -> :ok
        end

        await_notice(pid, method, predicate, events, until)

      notice ->
        {notice, events}
    end
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp assert_retained(ctx, pid, journal) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert snapshot(ctx.fixture.requests) === journal
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
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
               %{"name" => "owned_thread_start_config_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
