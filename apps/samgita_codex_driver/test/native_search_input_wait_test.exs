defmodule SamgitaCodexDriver.NativeSearchInputWaitTest do
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
  @script Path.expand("../../../scripts/codex/search_user_input_fixture.py", __DIR__)
  @script_sha "0b044293018473a5fcd345eb85d96be4eed081de19460b640579a94ee809f6cb"
  @warmup "OWNED_SEARCH_INPUT_WAIT λ"
  @question "OWNED_SEARCH_INPUT_QUESTION"
  @call "owned-search-input-choice"
  @warm_done "Owned searchable warmup done"
  @choice_done "Owned ordinary choice One complete"
  @answers %{"answers" => %{"fixture" => %{"answers" => ["One"]}}}

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      incoming = Keyword.fetch!(opts, :incoming_capture)
      transport_opts = Keyword.drop(opts, [:capture, :incoming_capture])

      with {:ok, state} <- Stdio.open(transport_opts),
           do: {:ok, Map.merge(state, %{capture: capture, incoming_capture: incoming})}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)
      if captured?(wire), do: capture(state, encoded, wire), else: Stdio.send(state, encoded)
    end

    defp captured?(%{"method" => "thread/search"}), do: true
    defp captured?(%{"result" => %{"answers" => _}}), do: true
    defp captured?(_wire), do: false

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 8 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [{encoded, wire}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case capture_incoming(next, events) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp capture_incoming(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case capture_incoming_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp capture_incoming_event(state, {:message, encoded}) do
      case JSON.decode(encoded) do
        {:ok, %{"method" => "item/tool/requestUserInput"} = wire} ->
          Agent.get_and_update(state.incoming_capture, &append_incoming(&1, encoded, wire))

        _ ->
          :ok
      end
    end

    defp capture_incoming_event(_state, _event), do: :ok

    defp append_incoming(ledger, encoded, wire) do
      size = byte_size(encoded)

      if length(ledger.frames) < 32 and size <= 65_536 and
           ledger.bytes + size <= 1_048_576 do
        {:ok, %{frames: ledger.frames ++ [{encoded, wire}], bytes: ledger.bytes + size}}
      else
        {{:error, SamgitaProtocolCodex.Error.new(:test_incoming_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@script)) == @script_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

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
      "default_reasoning_level" => "medium",
      "supported_reasoning_levels" => [
        %{"effort" => "medium", "description" => "Owned medium effort"}
      ]
    })

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))
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
          @script,
          Path.expand("../../../scripts/codex/model_fixture.py", __DIR__),
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    Map.merge(ctx, %{
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end}),
      incoming_capture:
        start_supervised!(%{
          id: :incoming_capture,
          start: {Agent, :start_link, [fn -> %{frames: [], bytes: 0} end]}
        })
    })
  end

  test "native search exposes a held ordinary input request then clears it and stays unloaded after restart",
       ctx do
    warm = start(ctx)

    thread =
      call(warm.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and thread != ""
    first = turn(warm.pid, thread, @warmup, %{})
    first_events = collect(warm.pid, [], &finished?(&1, thread, first), deadline(20_000))
    assert_answer(first_events, thread, first, @warm_done)
    initial = read(warm.pid, thread)
    assert_history(initial, [{first, @warmup, @warm_done}])
    path = Map.fetch!(initial, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    initial_file = snapshot(path)
    search(ctx, warm.pid, initial, %{"type" => "idle"})
    assert length(ModelFixture.requests(ctx.fixture)) == 1

    second =
      turn(warm.pid, thread, @question, %{
        "collaborationMode" => %{
          "mode" => "plan",
          "settings" => %{
            "model" => "mock-model",
            "reasoning_effort" => "medium",
            "developer_instructions" => nil
          }
        }
      })

    held =
      collect(
        warm.pid,
        [],
        &Enum.any?(&1, fn event -> event.wire["method"] == "item/tool/requestUserInput" end),
        deadline(20_000)
      )

    [request] = Enum.filter(held, &(&1.wire["method"] == "item/tool/requestUserInput"))
    assert request.kind == :server_request
    incoming = Agent.get(ctx.incoming_capture, & &1)
    assert %{frames: [{original, wire}], bytes: size} = incoming
    assert size == byte_size(original)
    assert wire === request.wire
    assert Map.fetch!(wire, "id") === Map.fetch!(request.wire, "id")
    assert JSON.decode!(original) === request.wire
    params = Map.fetch!(request.wire, "params")

    assert Map.take(params, ~w(threadId turnId itemId isBlocking autoResolutionMs)) == %{
             "threadId" => thread,
             "turnId" => second,
             "itemId" => @call,
             "isBlocking" => true,
             "autoResolutionMs" => nil
           }

    assert [question] = Map.fetch!(params, "questions")

    assert Map.take(question, ~w(id header question options)) == %{
             "id" => "fixture",
             "header" => "Fixture",
             "question" => "Choose fixture input",
             "options" => [
               %{"label" => "One", "description" => "Fixture one"},
               %{"label" => "Two", "description" => "Fixture two"}
             ]
           }

    assert %{interactions: 1, pending: 0, phase: :ready, gap: nil} = Session.status(warm.pid)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    search(ctx, warm.pid, initial, %{"type" => "active", "activeFlags" => ["waitingOnUserInput"]})
    assert %{interactions: 1} = Session.status(warm.pid)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    before = length(Agent.get(ctx.capture, & &1))
    assert :ok = Session.respond(warm.pid, request.handle, {:ok, @answers})
    reply = %{"id" => Map.fetch!(request.wire, "id"), "result" => @answers}
    assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert actual === reply and JSON.decode!(bytes) === reply and bytes === JSON.encode!(reply)

    complete =
      collect(
        warm.pid,
        held,
        &(finished?(&1, thread, second) and resolved?(&1, thread, reply["id"])),
        deadline(20_000)
      )

    assert_answer(complete, thread, second, @choice_done)

    assert [
             %{
               handle: handle,
               status: :resolution_observed,
               thread_id: ^thread,
               response_digest: digest
             }
           ] = Session.interaction_outcomes(warm.pid)

    assert handle === request.handle and digest == hash(bytes)
    assert %{interactions: 0} = Session.status(warm.pid)
    assert_provider(ctx, thread, [first, second])
    search(ctx, warm.pid, initial, %{"type" => "idle"})
    final = read(warm.pid, thread)
    assert_history(final, [{first, @warmup, @warm_done}, {second, @question, @choice_done}])
    assert hd(Map.fetch!(final, "turns")) === hd(Map.fetch!(initial, "turns"))
    final_file = snapshot(path)
    assert String.starts_with?(final_file, initial_file)

    retained =
      Map.merge(ctx.inputs, %{
        path => final_file,
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    assert_retained(ctx, warm.pid, retained)
    close(warm)

    cold = start(ctx)
    refute cold.native == warm.native
    assert_unloaded(cold.pid)
    search(ctx, cold.pid, initial, %{"type" => "notLoaded"})
    assert_unloaded(cold.pid)
    restored = read(cold.pid, thread)
    assert Map.fetch!(restored, "turns") === Map.fetch!(final, "turns")
    assert Map.fetch!(restored, "path") == path
    assert_unloaded(cold.pid)
    assert Session.interaction_outcomes(cold.pid) == []
    assert_retained(ctx, cold.pid, retained)
    close(cold)
    for {file, original} <- retained, do: assert(snapshot(file) === original)
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 5
    queries = for {_bytes, %{"method" => "thread/search"} = wire} <- frames, do: wire
    assert length(Enum.uniq_by(queries, & &1["id"])) == 4
    assert Enum.map(queries, & &1["params"]) == List.duplicate(search_params(), 4)
    assert Agent.get(ctx.incoming_capture, & &1) === incoming
  end

  defp assert_provider(ctx, thread, [first, second]) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 3

    assert Enum.map(requests, fn row ->
             assert Map.fetch!(row, "model") == "mock-model"

             row["client_metadata"]["x-codex-turn-metadata"]
             |> JSON.decode!()
             |> Map.take(~w(thread_id turn_id))
           end) == [
             %{"thread_id" => thread, "turn_id" => first},
             %{"thread_id" => thread, "turn_id" => second},
             %{"thread_id" => thread, "turn_id" => second}
           ]

    last = List.last(requests)
    assert [output] = Enum.filter(last["input"], &(&1["type"] == "function_call_output"))
    assert Map.fetch!(output, "call_id") == @call
    assert JSON.decode!(Map.fetch!(output, "output")) === @answers
  end

  defp search(ctx, pid, saved, status) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-input-search-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => "thread/search", "params" => search_params()}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert byte_size(JSON.encode!(response)) <= 65_536
    assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert actual === wire and JSON.decode!(bytes) === wire and bytes === JSON.encode!(wire)
    assert %{"data" => [row], "nextCursor" => nil, "backwardsCursor" => backwards} = result

    expected_cursor =
      (Map.fetch!(saved, "createdAt") * 1000 - 1)
      |> DateTime.from_unix!(:millisecond)
      |> DateTime.to_iso8601()

    assert backwards == expected_cursor
    thread = Map.fetch!(row, "thread")
    assert Map.fetch!(thread, "id") == saved["id"]
    assert Map.fetch!(thread, "path") == saved["path"]
    assert Map.fetch!(row, "snippet") == @warmup
    assert Map.fetch!(thread, "status") === status
    assert Map.fetch!(thread, "turns") == []
  end

  defp search_params, do: %{"searchTerm" => @warmup, "limit" => 100}

  defp turn(pid, thread, text, extra) do
    id =
      call(
        pid,
        "turn/start",
        Map.merge(
          %{"threadId" => thread, "input" => [%{"type" => "text", "text" => text}]},
          extra
        )
      )["turn"]["id"]

    assert is_binary(id) and id != ""
    id
  end

  defp finished?(events, thread, turn),
    do:
      Enum.any?(events, fn event ->
        event.wire["method"] == "turn/completed" and event.wire["params"]["threadId"] == thread and
          event.wire["params"]["turn"]["id"] == turn and
          event.wire["params"]["turn"]["status"] == "completed"
      end)

  defp resolved?(events, thread, request),
    do:
      Enum.any?(events, fn event ->
        event.wire["method"] == "serverRequest/resolved" and
          event.wire["params"] === %{"threadId" => thread, "requestId" => request}
      end)

  defp assert_answer(events, thread, turn, text) do
    answers =
      for event <- events,
          event.wire["method"] == "item/completed",
          params = event.wire["params"],
          params["threadId"] == thread and params["turnId"] == turn,
          params["item"]["type"] == "agentMessage",
          do: params["item"]["text"]

    assert answers == [text]
  end

  defp collect(pid, events, ready, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(:erlang.term_to_binary(events)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    refute Enum.any?(
             events,
             &(&1.wire["method"] == "error" or &1.kind == :unsupported_server_request)
           )

    if ready.(events) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native input-wait event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected input-wait gap")
      after
        10 -> :ok
      end

      collect(pid, events, ready, until)
    end
  end

  defp assert_history(thread, expected) do
    turns = Map.fetch!(thread, "turns")
    assert Enum.map(turns, & &1["id"]) == Enum.map(expected, &elem(&1, 0))

    for {turn, {id, input, answer}} <- Enum.zip(turns, expected) do
      assert Map.take(turn, ~w(id status error)) == %{
               "id" => id,
               "status" => "completed",
               "error" => nil
             }

      assert [%{"content" => [%{"type" => "text", "text" => ^input, "text_elements" => []}]}] =
               Enum.filter(turn["items"], &(&1["type"] == "userMessage"))

      assert [%{"text" => ^answer}] = Enum.filter(turn["items"], &(&1["type"] == "agentMessage"))
    end
  end

  defp assert_retained(ctx, pid, retained) do
    for {file, original} <- retained, do: assert(snapshot(file) === original)
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 128
    assert byte_size(:erlang.term_to_binary(events)) <= 1_048_576

    refute Enum.any?(
             events,
             &(&1.kind in [:server_request, :unsupported_server_request] or
                 &1.wire["method"] == "error")
           )
  end

  defp assert_unloaded(pid),
    do: assert(call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil})

  defp read(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp call(pid, method, params) do
    id = "owned-input-wait-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

    assert byte_size(JSON.encode!(response)) <= 65_536
    result
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    incoming_capture: ctx.incoming_capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
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
               %{"name" => "owned_search_input_wait", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, native: native, connection: connection}
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    bytes
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
