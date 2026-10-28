defmodule SamgitaCodexDriver.NativeOrdinaryCurrentTimeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.{Error, Schema}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_current_time_fixture.py", __DIR__)
  @script_sha "8c42ff9f3adeaf87b2c1469913714dca3492fe7e8681aece2d7ab490fb09d0d3"
  @reply %{"currentTimeAt" => 1_781_717_655}

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    def send(state, encoded) do
      with :ok <- append(state, :out, encoded), do: Stdio.send(state, encoded)
    end

    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &record(&1, &2, next)) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp record({:message, encoded}, :ok, state) do
      case append(state, :in, encoded) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end

    defp record(_, :ok, _state), do: {:cont, :ok}

    defp append(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if length(ledger.frames) < 128 and size <= 65_536 and ledger.bytes + size <= 2_097_152 do
          {:ok, %{frames: ledger.frames ++ [{direction, encoded}], bytes: ledger.bytes + size}}
        else
          {{:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    def close(state), do: Stdio.close(state)
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
    TurnFixture.configure_model(ctx, %{})
    Map.put(ctx, :capture, start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end}))
  end

  for experimental <- [false, true] do
    @experimental experimental
    test "native external clock consumes three correlated reads with experimental=#{experimental}",
         ctx do
      session = start(ctx, @experimental)
      pid = session.pid

      thread =
        call(pid, "thread/start", %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.fixture.workspace,
          "ephemeral" => true
        })["thread"]["id"]

      turn =
        call(pid, "turn/start", %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => "Read the ordinary external clock"}]
        })["turn"]["id"]

      # The stock first turn awaits initial environment date, reminder, then
      # rebuilt environment date. Each request is a new read, never a retry.
      {held, answers} =
        Enum.reduce(1..3, {[], []}, fn _, {events, answered} ->
          answer_clock(ctx, pid, thread, events, answered)
        end)

      finished = finish_clock(ctx, pid, held, turn)
      requests = Enum.map(answers, &elem(&1, 0))
      assert Enum.filter(finished, &(&1.kind == :server_request)) === requests
      assert_clock_exchanges(ctx, answers)
      assert_clock_consumed(ctx, thread, turn)
      assert completed?(finished, turn)

      assert [%{"text" => "Owned external time read"}] =
               for(
                 event <- finished,
                 event.wire["method"] == "item/completed",
                 event.wire["params"]["item"]["type"] == "agentMessage",
                 do: Map.take(event.wire["params"]["item"], ["text"])
               )

      # The provider effect is independently observed. No transport response ACK
      # or serverRequest/resolved notification is manufactured for this method.
      outcomes = Session.interaction_outcomes(pid)
      assert length(outcomes) === 3

      for {request, response} <- answers do
        assert %{status: :sent_unconfirmed, response_digest: digest} =
                 Enum.find(outcomes, &(&1.handle === request.handle))

        assert digest === hash(response)
      end

      [request | _] = requests
      before_late = Agent.get(ctx.capture, & &1)

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(pid, request.handle, {:ok, @reply})

      assert Agent.get(ctx.capture, & &1) === before_late

      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
               Session.status(pid)

      assert :ok = Session.close(pid)
      assert :atomics.get(session.connection.owner.completion, 1) == 1
      assert Port.info(session.connection.port) == nil
      refute File.exists?("/proc/#{session.native}")
      assert_clock_consumed(ctx, thread, turn)
      assert length(frames(ctx, &(&1["method"] == "currentTime/read"))) === 3
      assert File.ls!(ctx.fixture.workspace) === []
      assert :ok = ModelFixture.close(ctx.fixture)
      assert :atomics.get(ctx.fixture.transport.owner.completion, 1) == 1
      assert Port.info(ctx.fixture.port) == nil
    end
  end

  defp answer_clock(ctx, pid, thread, events, answered) do
    held =
      collect(
        pid,
        events,
        fn incoming ->
          Enum.count(incoming, &(&1.kind == :server_request)) > length(answered)
        end,
        deadline()
      )

    requests = Enum.filter(held, &(&1.kind == :server_request))
    assert length(requests) === length(answered) + 1
    request = List.last(requests)
    assert is_integer(request.handle.id) and request.handle.id >= 0
    refute Enum.any?(answered, fn {old, _} -> old.handle.id === request.handle.id end)

    assert request.wire === %{
             "id" => request.handle.id,
             "method" => "currentTime/read",
             "params" => %{"threadId" => thread}
           }

    assert [{:in, original, wire}] =
             frames(ctx, &(&1["method"] == "currentTime/read" and &1["id"] === request.handle.id))

    assert JSON.decode!(original) === request.wire and wire === request.wire
    assert :ok = Schema.validate(clock_schema(), wire, max_depth: 32)
    assert ModelFixture.requests(ctx.fixture) === []
    assert %{interactions: 1, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = Session.respond(pid, request.handle, {:ok, @reply})

    assert [{:out, response, response_wire}] =
             for(
               {:out, _, _} = frame <-
                 frames(ctx, &(Map.has_key?(&1, "result") and &1["id"] === request.handle.id)),
               do: frame
             )

    assert response_wire === %{"id" => request.handle.id, "result" => @reply}
    assert response === JSON.encode!(response_wire)
    {held, answered ++ [{request, response}]}
  end

  defp assert_clock_exchanges(ctx, answers) do
    actual =
      for {direction, _, wire} <- frames(ctx, fn _ -> true end),
          (direction === :in and wire["method"] === "currentTime/read") or
            (direction === :out and Map.has_key?(wire, "result")),
          do: {direction, wire}

    expected =
      Enum.flat_map(answers, fn {request, response} ->
        [{:in, request.wire}, {:out, JSON.decode!(response)}]
      end)

    assert actual === expected
  end

  defp assert_clock_consumed(ctx, thread, turn) do
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert request["model"] === "mock-model"

    assert request["client_metadata"]["x-codex-turn-metadata"]
           |> JSON.decode!()
           |> Map.take(~w(thread_id turn_id)) === %{"thread_id" => thread, "turn_id" => turn}

    reminders =
      for item <- request["input"],
          item["role"] == "developer",
          part <- item["content"] || [],
          part["type"] == "input_text",
          String.contains?(part["text"], "<current_time_reminder>"),
          do: part["text"]

    assert [reminder] = reminders
    assert reminder =~ "It is 2026-06-17 17:34:15 UTC."
    assert reminder =~ "</current_time_reminder>"
  end

  defp finish_clock(ctx, pid, events, turn) do
    collect(pid, events, &completed?(&1, turn), deadline())
  rescue
    failure in ExUnit.AssertionError ->
      stack = __STACKTRACE__

      try do
        evidence = %{
          "native" =>
            Enum.map(frames(ctx, fn _ -> true end), fn {direction, _, wire} ->
              %{"direction" => Atom.to_string(direction), "wire" => wire}
            end),
          "provider_requests" => ModelFixture.requests(ctx.fixture)
        }

        encoded = JSON.encode!(evidence)
        assert byte_size(encoded) <= 3_145_728
        IO.puts("V543_ORDINARY_CLOCK_FAILURE " <> encoded)
      after
        reraise failure, stack
      end
  end

  defp frames(ctx, predicate) do
    ctx.capture
    |> Agent.get(& &1.frames)
    |> Enum.map(fn {direction, bytes} -> {direction, bytes, JSON.decode!(bytes)} end)
    |> Enum.filter(fn {_, _, wire} -> predicate.(wire) end)
  end

  defp clock_schema do
    root =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/ServerRequest.json")
      |> File.read!()
      |> JSON.decode!()

    root["oneOf"] |> Enum.at(8) |> Map.put("definitions", root["definitions"])
  end

  defp completed?(events, turn) do
    Enum.any?(events, fn event ->
      event.wire["method"] == "turn/completed" and
        event.wire["params"]["turn"]["id"] == turn and
        event.wire["params"]["turn"]["status"] == "completed"
    end)
  end

  defp collect(pid, events, ready, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 128 and byte_size(:erlang.term_to_binary(events)) <= 2_097_152
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    refute Enum.any?(
             events,
             &(&1.wire["method"] == "error" or &1.kind == :unsupported_server_request)
           )

    if ready.(events) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "Native external-clock event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected external-clock event gap")
      after
        10 -> :ok
      end

      collect(pid, events, ready, until)
    end
  end

  defp start(ctx, experimental) do
    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
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
               %{"name" => "ordinary_external_clock", "version" => "0.1.0"},
               %{"experimentalApi" => experimental},
               timeout_ms: 5_000
             )

    # Diagnostics is experimental even though the native external-clock request
    # can be delivered on an ordinary connection. Resolve only this owned helper.
    assert {:os_pid, helper} = Port.info(connection.port, :os_pid)
    children = File.read!("/proc/#{helper}/task/#{helper}/children")
    assert byte_size(children) <= 128
    assert [native] = children |> String.split() |> Enum.map(&String.to_integer/1)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} =
             Session.request(pid, method, params, timeout_ms: 5_000)

    result
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
