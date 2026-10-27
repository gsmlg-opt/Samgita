defmodule SamgitaCodexDriver.NativeTurnCollaborationNullTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @plan "OWNED_PLAN_NULL_KEEP λ"
  @default "OWNED_DEFAULT_NULL_CONTROL λ"
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary collaboration null base instructions."

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      with {:ok, next} <- Stdio.send(state, encoded) do
        case record(next, :out, encoded) do
          :ok -> {:ok, next}
          {:error, error} -> {:error, error, next}
        end
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)

      if selected?(direction, wire) do
        Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
      else
        :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 32 and size <= limit and ledger.bytes + size <= 1_048_576 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger
          |> Map.put(direction, entries ++ [entry])
          |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "default_reasoning_level" => "low",
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Owned low effort"},
        %{"effort" => "medium", "description" => "Owned medium effort"}
      ],
      "supports_reasoning_summary_parameter" => true,
      "default_reasoning_summary" => "auto",
      "use_responses_lite" => false,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "outer null retains Plan and instructions while independent effort changes", ctx do
    session = start(ctx)
    pid = session.pid

    thread_params = %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "ephemeral" => false,
      "historyMode" => "legacy"
    }

    initial = call(ctx, pid, "thread/start", thread_params)["thread"]
    thread = initial["id"]
    assert is_binary(thread) and thread != ""
    assert ModelFixture.requests(ctx.fixture) == []

    rows = [
      {%{"collaborationMode" => mode("plan", "medium", @plan)}, "plan", "medium", @plan},
      {%{"collaborationMode" => nil, "effort" => "low"}, "plan", "low", @plan},
      {%{}, "plan", "low", @plan},
      {%{"collaborationMode" => mode("default", "medium", @default)}, "default", "medium",
       @default}
    ]

    turns =
      for {{extra, expected_mode, effort, instructions}, index} <- Enum.with_index(rows, 1) do
        marker = "owned-collaboration-null-turn-#{index} λ"

        params =
          Map.merge(
            %{"threadId" => thread, "input" => [%{"type" => "text", "text" => marker}]},
            extra
          )

        result = call(ctx, pid, "turn/start", params)
        turn = result["turn"]["id"]
        assert is_binary(turn) and turn != ""

        sent = captured(ctx, "turn/start")
        assert length(sent) == index
        assert List.last(sent).wire["params"] === params

        assert Map.has_key?(List.last(sent).wire["params"], "collaborationMode") ==
                 Map.has_key?(extra, "collaborationMode")

        events =
          collect(
            pid,
            fn events ->
              TurnFixture.notification(events, "turn/completed", fn item ->
                item["threadId"] == thread and item["turn"]["id"] == turn
              end)
            end,
            deadline(20_000)
          )

        identity = assert_turn(events, thread, turn, marker)
        assert_provider(ctx, index, thread, turn, marker, effort, instructions)
        settings_snapshot(ctx, pid, thread, expected_mode, effort, instructions, index)
        Map.merge(identity, %{id: turn, marker: marker})
      end

    assert length(Enum.uniq_by(turns, & &1.id)) == 4
    assert length(Enum.uniq(Enum.flat_map(turns, &[&1.user["id"], &1.assistant["id"]]))) == 8
    journal = snapshot(ctx.fixture.requests)
    assert length(ModelFixture.requests(ctx.fixture)) == 4

    first =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert_history(first, thread, turns)
    rollout = snapshot(first["path"])

    second =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert second === first
    assert_history(second, thread, turns)
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] == [thread]

    assert {:ok, remaining} = Session.drain(pid, 256)
    assert_bounded(remaining)
    assert {:ok, []} = Session.drain(pid, 256)

    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil, buffered_events: 0} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert_inventory(ctx)
    assert_unchanged(ctx, journal, first["path"], rollout)

    assert :ok = Session.close(pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
    assert_unchanged(ctx, journal, first["path"], rollout)
  end

  defp mode(name, effort, instructions) do
    %{
      "mode" => name,
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => effort,
        "developer_instructions" => instructions
      }
    }
  end

  defp assert_turn(events, thread, turn, marker) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             TurnFixture.notification(events, "turn/started", &(&1["turn"]["id"] == turn))

    completed = items(events, "item/completed", thread, turn)
    assert [user, assistant] = completed
    assert user["type"] == "userMessage"
    assert user["content"] == [%{"type" => "text", "text" => marker, "text_elements" => []}]
    assert assistant["type"] == "agentMessage"
    assert assistant["text"] === @answer

    started = items(events, "item/started", thread, turn)

    assert Enum.map(started, &Map.take(&1, ["id", "type"])) ==
             Enum.map(completed, &Map.take(&1, ["id", "type"]))

    assert Enum.all?(completed, &(is_binary(&1["id"]) and &1["id"] != ""))
    %{user: user, assistant: assistant}
  end

  defp items(events, method, thread, turn) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["threadId"] == thread,
        event.wire["params"]["turnId"] == turn,
        do: event.wire["params"]["item"]
  end

  defp assert_provider(ctx, index, thread, turn, marker, effort, instructions) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == index
    request = List.last(requests)
    assert request["model"] == "mock-model"
    assert request["reasoning"]["effort"] == effort
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    assert metadata["thread_id"] == thread and metadata["turn_id"] == turn

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1

    fragments =
      for item <- request["input"],
          item["role"] == "developer",
          content <- item["content"],
          content["type"] == "input_text",
          String.contains?(content["text"], [@plan, @default]),
          do: content["text"]

    assert fragments != []
    assert List.last(fragments) =~ instructions

    if index < 4 do
      assert Enum.all?(fragments, &(not String.contains?(&1, @default)))
    end
  end

  # Changing only summary forces a real applied-settings event even when the
  # preceding turn omitted the target fields. The RPC ACK is not the oracle.
  defp settings_snapshot(ctx, pid, thread, expected_mode, effort, instructions, index) do
    journal = snapshot(ctx.fixture.requests)
    summary = if rem(index, 2) == 1, do: "concise", else: "detailed"
    params = %{"threadId" => thread, "summary" => summary}
    assert call(ctx, pid, "thread/settings/update", params) == %{}

    events =
      collect(
        pid,
        fn events ->
          TurnFixture.notification(events, "thread/settings/updated", fn item ->
            item["threadId"] == thread and item["threadSettings"]["summary"] == summary
          end)
        end,
        deadline(5_000)
      )

    applied =
      TurnFixture.notification(events, "thread/settings/updated", fn item ->
        item["threadId"] == thread and item["threadSettings"]["summary"] == summary
      end)["threadSettings"]

    assert applied["model"] == "mock-model"
    assert applied["modelProvider"] == "fixture"
    assert applied["effort"] == effort
    assert applied["collaborationMode"] === mode(expected_mode, effort, instructions)
    assert snapshot(ctx.fixture.requests) == journal
  end

  defp collect(pid, predicate, deadline, events \\ []) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert_bounded(events)

    if predicate.(events) do
      events
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, predicate, deadline, events)
      after
        remaining -> flunk("native event deadline")
      end
    end
  end

  defp assert_bounded(events) do
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
  end

  defp assert_history(saved, thread, turns) do
    assert saved["id"] == thread
    assert saved["historyMode"] == "legacy"
    assert Enum.map(saved["turns"], & &1["id"]) == Enum.map(turns, & &1.id)

    # Legacy thread/read reconstructs User/AgentMessage IDs with a single
    # monotonic item-N counter. Live start/completed IDs remain independently
    # correlated above; they are not this history representation's identity.
    for {{stored, original}, index} <- Enum.with_index(Enum.zip(saved["turns"], turns), 1) do
      assert stored["status"] == "completed"

      expected = [
        Map.put(original.user, "id", "item-#{index * 2 - 1}"),
        Map.put(original.assistant, "id", "item-#{index * 2}")
      ]

      assert stored["items"] === expected

      assert Enum.map(stored["items"], & &1["id"]) !=
               [original.user["id"], original.assistant["id"]]
    end
  end

  defp call(ctx, pid, method, params) do
    id = "owned-collaboration-null-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] == wire["id"]))
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
  end

  defp captured(ctx, method),
    do:
      Agent.get(ctx.capture, &Enum.filter(&1.out, fn entry -> entry.wire["method"] == method end))

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
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

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    info = %{"name" => "owned_collaboration_null", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, timeout_ms: 5_000)

    assert [sent] = captured(ctx, "initialize")
    assert sent.wire["params"] === %{"clientInfo" => info, "capabilities" => capabilities}
    assert_exchange(ctx, sent.wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, native: native, connection: connection}
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    expected =
      ["initialize", "server/diagnostics", "thread/start"] ++
        List.flatten(List.duplicate(["turn/start", "thread/settings/update"], 4)) ++
        ["thread/read", "thread/read", "thread/loaded/list"]

    assert Enum.map(ledger.out, & &1.wire["method"]) === expected
    assert length(ledger.in) == length(expected)
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == length(ids)
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_unchanged(ctx, journal, path, rollout) do
    for {input, original} <- ctx.inputs, do: assert(snapshot(input) == original)
    assert snapshot(ctx.fixture.requests) == journal
    assert snapshot(path) == rollout
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp snapshot(path) do
    assert is_binary(path)
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
