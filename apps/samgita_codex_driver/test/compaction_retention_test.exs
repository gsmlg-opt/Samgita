defmodule SamgitaCodexDriver.CompactionRetentionTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @checkpoint "SYNTHETIC_COMPACTION_CHECKPOINT"
  @namespace "synthetic_retention_budget"

  setup {TurnFixture, :setup}

  test "shared budget keeps the newest output whole and does not backfill older outputs",
       context do
    context = remote_fixture(context, "compaction")
    pid = start(context)
    thread = thread(context, pid)

    # Pinned compact_remote_v2.rs uses 64,000 estimated tokens, newest first.
    # The newest fits; the middle exceeds the remaining budget; the oldest
    # would fit that remainder but must not backfill across the middle output.
    submitted = [
      output("oldest_fit", 8_000),
      output("middle_blocker", 180_000),
      output("newest_kept", 120_000)
    ]

    seed_outputs(pid, thread, submitted)
    compact = compact_successfully(pid, thread, context.fixture, length(submitted))
    assert_outputs(compact, submitted)

    after_resume = cold_resume_request(context, pid, thread)
    assert_checkpoint(after_resume)
    assert_outputs(after_resume, [List.last(submitted)])
  end

  test "an oversized newest retained output drops whole without backfilling an older output",
       context do
    context = remote_fixture(context, "compaction")
    pid = start(context)
    thread = thread(context, pid)
    submitted = [output("older_would_fit", 8_000), output("newest_oversized", 300_000)]

    seed_outputs(pid, thread, submitted)
    compact = compact_successfully(pid, thread, context.fixture, length(submitted))
    assert_outputs(compact, submitted)

    after_resume = cold_resume_request(context, pid, thread)
    assert_checkpoint(after_resume)
    assert_outputs(after_resume, [])
  end

  test "a genuine remote compaction failure preserves history for ordinary and cold-resumed turns",
       context do
    # This fixture returns an ordinary assistant item even for a real compaction
    # request. Pinned Codex must reject its missing checkpoint asynchronously.
    context = remote_fixture(context, "assistant")
    pid = start(context)
    thread = thread(context, pid)
    submitted = [output("survives_failed_compaction", 8_000)]
    seed_outputs(pid, thread, submitted)

    assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
    events = compaction_finished(pid, thread)
    assert [_, compact] = ModelFixture.requests(context.fixture)
    assert_trigger(compact)
    assert_outputs(compact, submitted)

    assert %{"threadId" => ^thread, "turnId" => turn, "item" => %{"type" => "contextCompaction"}} =
             notification(events, "item/started", &(&1["item"]["type"] == "contextCompaction"))

    message =
      "remote compaction v2 expected exactly one compaction output item, got 0 from 1 output items"

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "willRetry" => false,
             "error" => %{"message" => error}
           } = notification(events, "error")

    assert error =~ message

    assert %{
             "threadId" => ^thread,
             "turn" => %{"id" => ^turn, "status" => "failed", "error" => %{"message" => error}}
           } =
             notification(events, "turn/completed")

    assert error =~ message
    refute notification(events, "item/completed", &(&1["item"]["type"] == "contextCompaction"))
    refute Enum.any?(events, &(&1.kind == :server_request))

    followup = normal_request(context.fixture, pid, thread, "Continue after failed compaction")
    assert_outputs(followup, submitted)
    refute Enum.any?(followup["input"], &(&1["type"] in ["compaction", "compaction_trigger"]))

    after_resume = cold_resume_request(context, pid, thread)
    assert_outputs(after_resume, submitted)
    refute Enum.any?(after_resume["input"], &(&1["type"] in ["compaction", "compaction_trigger"]))
  end

  defp remote_fixture(context, scenario) do
    fixture = ModelFixture.start(Path.join(context.root, "retention"), scenario)
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    context = %{context | fixture: fixture}

    configure_model(context, %{
      "context_window" => 8_000_000,
      "truncation_policy" => %{"mode" => "bytes", "limit" => 1_000_000}
    })

    File.write!(
      Path.join(fixture.codex_home, "config.toml"),
      """

      [model_providers.fixture.capabilities]
      remote_compaction = "v2"
      [features]
      retain_client_tool_outputs = true
      """,
      [:append]
    )

    context
  end

  defp output(name, bytes) do
    %{
      "name" => name,
      "namespace" => @namespace,
      "output" => name <> ":" <> String.duplicate("x", bytes) <> ":END:" <> name
    }
  end

  defp seed_outputs(pid, thread, submitted) do
    for output <- submitted do
      turn = start_turn(pid, thread, [], %{"toolOutput" => Map.put(output, "retain", true)})
      finish_turn(pid, thread, turn)
    end
  end

  defp compact_successfully(pid, thread, fixture, seed_count) do
    assert length(ModelFixture.requests(fixture)) == seed_count
    assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
    events = compaction_finished(pid, thread)

    assert %{
             "threadId" => ^thread,
             "turnId" => turn,
             "item" => %{"type" => "contextCompaction", "id" => item}
           } =
             notification(events, "item/started", &(&1["item"]["type"] == "contextCompaction"))

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"type" => "contextCompaction", "id" => ^item}
           } =
             notification(events, "item/completed", &(&1["item"]["type"] == "contextCompaction"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed")

    refute notification(events, "error")
    refute Enum.any?(events, &(&1.kind == :server_request))
    requests = ModelFixture.requests(fixture)
    assert length(requests) == seed_count + 1
    compact = List.last(requests)
    assert_trigger(compact)
    compact
  end

  defp cold_resume_request(context, pid, thread) do
    request_count = length(ModelFixture.requests(context.fixture))
    assert :ok = Session.close(pid)
    resumed = start(context)
    assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert length(ModelFixture.requests(context.fixture)) == request_count
    request = normal_request(context.fixture, resumed, thread, "Continue after cold resume")
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
    request
  end

  defp normal_request(fixture, pid, thread, text) do
    request_count = length(ModelFixture.requests(fixture))
    turn = start_turn(pid, thread, [%{"type" => "text", "text" => text}])
    finish_turn(pid, thread, turn)
    requests = ModelFixture.requests(fixture)
    assert length(requests) == request_count + 1
    List.last(requests)
  end

  defp assert_outputs(request, expected) do
    outputs = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))
    assert Enum.map(outputs, &Map.take(&1, ["name", "namespace", "output"])) == expected

    for output <- outputs, field <- ["call_id", "retain", "client_authored"] do
      refute Map.has_key?(output, field)
    end
  end

  defp assert_trigger(request) do
    assert [_] = Enum.filter(request["input"], &(&1["type"] == "compaction_trigger"))
  end

  defp assert_checkpoint(request) do
    assert [%{"encrypted_content" => @checkpoint}] =
             Enum.filter(request["input"], &(&1["type"] == "compaction"))

    refute Enum.any?(request["input"], &(&1["type"] == "compaction_trigger"))
  end

  defp compaction_finished(pid, thread) do
    collect_compaction(pid, thread, [], System.monotonic_time(:millisecond) + 20_000)
  end

  defp collect_compaction(pid, thread, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if notification(events, "turn/completed", &(&1["threadId"] == thread)) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect_compaction(pid, thread, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected gap during real compaction")
      after
        remaining -> flunk("Real compaction did not finish before its deadline")
      end
    end
  end
end
