defmodule StandaloneCodex.Workflows do
  @moduledoc "Ordinary native workflows with a deterministic local model provider."

  alias SamgitaCodexDriver.Session
  alias StandaloneCodex.ProviderFixture

  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @answer "Deterministic local fixture answer"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Pure lookup in an explicitly supplied synthetic table",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }
  @capabilities %{"experimentalApi" => true}
  @event_limit 256
  @byte_limit 1_048_576

  def run(binary, root, provider_script, on_event \\ fn _ -> :ok end) do
    prerequisite!(binary, "CODEX_BINARY")
    prerequisite!(provider_script, "CODEX_MODEL_FIXTURE_SCRIPT")

    ensure!(
      Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha,
      "Selected executable differs from the immutable Codex pin"
    )

    completed =
      ProviderFixture.with(Path.join(root, "completed"), provider_script, fn fixture ->
        with_session(binary, fixture, fn pid -> completed(pid, fixture, on_event) end)
      end)

    interrupted =
      ProviderFixture.with(Path.join(root, "interrupted"), provider_script, fn fixture ->
        with_session(binary, fixture, fn pid -> interrupted(pid, fixture, on_event) end)
      end)

    report = %{completed: completed, interrupted: interrupted}
    ensure!(cleaned_up?(report), "Owned resources remain; retain the disposable directory")
    report
  end

  @doc "The selected Linux profile confirms closed Sessions, fixture Ports and native PIDs."
  def cleaned_up?(report) do
    Enum.all?([report.completed, report.interrupted], fn workflow ->
      not Process.alive?(workflow.session) and Port.info(workflow.fixture_port) == nil and
        Enum.all?(workflow.native_pids, &(not File.exists?("/proc/#{&1}")))
    end)
  end

  @doc "An explicit pure result for the one declared tool and its exact argument shape."
  def lookup(%{"tool" => "fixture_lookup", "arguments" => %{"key" => "synthetic"}}) do
    %{
      "success" => true,
      "contentItems" => [%{"type" => "inputText", "text" => "Synthetic lookup completed"}]
    }
  end

  def lookup(_), do: raise(ArgumentError, "Unexpected synthetic lookup request")

  defp with_session(binary, fixture, function) do
    {:ok, pid} =
      StandaloneCodex.start(
        binary,
        fixture.home,
        fixture.codex_home,
        fixture.workspace,
        @capabilities
      )

    try do
      function.(pid)
    after
      close_owned(pid)
    end
  end

  defp completed(pid, fixture, on_event) do
    native = native_pid(pid)
    {thread, turn, operations} = start_turn(pid, fixture, "Standalone pure lookup")
    events = collect(pid, [], &tool_request?(&1, thread, turn), on_event)
    tool = Enum.find(events, &matching_tool?(&1, thread, turn))
    tool_result = lookup(tool.wire["params"])
    :ok = StandaloneCodex.respond(pid, tool.handle, {:ok, tool_result})
    events = collect(pid, events, &terminal?(&1, thread, turn, "completed"), on_event)
    history = request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    provider_before = ProviderFixture.requests(fixture)
    ensure!(length(provider_before) == 2, "Expected tool call and one model continuation")
    before = Session.status(pid)

    :ok = Session.reconnect(pid)
    {:ok, initialize} = StandaloneCodex.initialize(pid, @capabilities)
    replacement = native_pid(pid)
    cold_read = request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    resume = request(pid, "thread/resume", %{"threadId" => thread})
    recovered = request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    after_recovery = Session.status(pid)
    recovery_events = drain(pid, on_event)
    verify_completed!(events, history, thread, turn)

    for restored <- [cold_read, recovered] do
      ensure!(
        restored.response["result"]["thread"]["turns"] ==
          history.response["result"]["thread"]["turns"],
        "Recovered history differs from the original turn"
      )
    end

    ensure!(
      ProviderFixture.requests(fixture) == provider_before,
      "Recovery unexpectedly requested another model response"
    )

    ensure!(
      after_recovery.generation == before.generation + 1 and
        after_recovery.gap.reason == :explicit_reconnect,
      "Recovery did not retain its connection gap"
    )

    %{
      session: pid,
      fixture_port: fixture.port,
      native_pids: [native, replacement],
      thread: thread,
      turn: turn,
      tool: tool,
      tool_result: tool_result,
      events: events,
      expected_answer: @answer,
      history: history,
      provider_before_recovery: provider_before,
      provider_after_recovery: ProviderFixture.requests(fixture),
      operations: operations,
      recovery: %{
        initialize: initialize,
        before: before,
        after: after_recovery,
        cold_read: cold_read,
        resume: resume,
        history: recovered,
        events: recovery_events
      }
    }
  end

  defp interrupted(pid, fixture, on_event) do
    native = native_pid(pid)
    {thread, turn, operations} = start_turn(pid, fixture, "Standalone interrupted lookup")
    events = collect(pid, [], &tool_request?(&1, thread, turn), on_event)
    tool = Enum.find(events, &matching_tool?(&1, thread, turn))
    ensure!(not terminal?(events, thread, turn, "completed"), "Turn already completed")
    interrupt = request(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn})
    ensure!(interrupt.response["result"] == %{}, "Expected an interruption acknowledgement")
    events = collect(pid, events, &terminal?(&1, thread, turn, "interrupted"), on_event)
    history = request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})

    %{
      session: pid,
      fixture_port: fixture.port,
      native_pids: [native],
      thread: thread,
      turn: turn,
      tool: tool,
      events: events,
      interrupt: interrupt,
      history: history,
      operations: operations,
      provider_requests: ProviderFixture.requests(fixture),
      status: Session.status(pid),
      interaction_outcomes: Session.interaction_outcomes(pid)
    }
  end

  defp start_turn(pid, fixture, text) do
    creation =
      request(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated",
        "dynamicTools" => [@lookup]
      })

    thread = creation.response["result"]["thread"]["id"]

    submission =
      request(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })

    turn = submission.response["result"]["turn"]["id"]
    {thread, turn, %{create: creation, submit: submission}}
  end

  defp verify_completed!(events, history, thread, turn) do
    deltas =
      for event <- events,
          event.wire["method"] == "item/agentMessage/delta",
          do: event.wire["params"]

    ensure!(Enum.map_join(deltas, & &1["delta"]) == @answer, "Incomplete incremental text")

    ensure!(
      Enum.all?(deltas, &(&1["threadId"] == thread and &1["turnId"] == turn)),
      "Incremental text belongs to another operation"
    )

    [message_id] = deltas |> Enum.map(& &1["itemId"]) |> Enum.uniq()
    [history_turn] = history.response["result"]["thread"]["turns"]

    ensure!(
      history_turn["id"] == turn and history_turn["status"] == "completed",
      "Incomplete history"
    )

    ensure!(
      Enum.any?(history_turn["items"], fn item ->
        item["type"] == "agentMessage" and item["id"] == message_id and item["text"] == @answer
      end),
      "History lost the streamed message identity"
    )
  end

  defp native_pid(pid) do
    request(pid, "server/diagnostics", %{}).response["result"]["process"]["id"]
  end

  defp request(pid, method, params) do
    id = "standalone-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}
    {:ok, %{"id" => ^id} = response} = Session.request_native(pid, wire, timeout_ms: 5000)
    %{request: wire, response: response}
  end

  defp collect(pid, events, predicate, on_event) do
    collect(pid, events, predicate, on_event, System.monotonic_time(:millisecond) + 5000)
  end

  defp collect(pid, events, predicate, on_event, deadline) do
    events = events ++ drain(pid, on_event)
    bounded!(events)

    if predicate.(events) do
      events
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, on_event, deadline)

        {:codex_driver, ^pid, {:gap, _gap}} ->
          raise "Unexpected connection gap during an ordinary turn"
      after
        remaining -> raise "Native event deadline exceeded"
      end
    end
  end

  defp drain(pid, on_event) do
    {:ok, incoming} = Session.drain(pid, @event_limit)
    bounded!(incoming)
    Enum.each(incoming, on_event)
    incoming
  end

  defp bounded!(events) do
    ensure!(length(events) <= @event_limit, "Consumer event count exceeded")

    ensure!(
      Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= @byte_limit,
      "Consumer event bytes exceeded"
    )
  end

  defp tool_request?(events, thread, turn),
    do: Enum.any?(events, &matching_tool?(&1, thread, turn))

  defp matching_tool?(event, thread, turn) do
    event.kind == :server_request and event.wire["method"] == "item/tool/call" and
      event.wire["params"]["threadId"] == thread and event.wire["params"]["turnId"] == turn
  end

  defp terminal?(events, thread, turn, status) do
    Enum.any?(events, fn event ->
      event.wire["method"] == "turn/completed" and
        event.wire["params"]["threadId"] == thread and
        event.wire["params"]["turn"]["id"] == turn and
        event.wire["params"]["turn"]["status"] == status
    end)
  end

  defp close_owned(pid) do
    monitor = Process.monitor(pid)
    if Process.alive?(pid), do: :ok = StandaloneCodex.close(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
    after
      5000 -> raise "Owned Session cleanup did not finish"
    end
  end

  defp prerequisite!(path, name) do
    ensure!(is_binary(path) and File.regular?(path), "BLOCKED_ENV: #{name} required")
  end

  defp ensure!(true, _message), do: :ok
  defp ensure!(false, message), do: raise(ArgumentError, message)
end
