defmodule SamgitaCodexDriver.CompactionControlTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/compaction_control_fixture.py", __DIR__)
  @late "SYNTHETIC_CANCELLED_COMPACTION_CHECKPOINT"
  @failed "SYNTHETIC_FAILED_COMPACTION_CHECKPOINT"
  @final "SYNTHETIC_RETRIED_COMPACTION_CHECKPOINT"

  setup tags do
    binary = System.fetch_env!("CODEX_BINARY")

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-compact-control-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags.scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  @tag scenario: "hold"
  test "interruption fences held compaction output and cold resume preserves usable history",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    seed = start_turn(pid, thread, [%{"type" => "text", "text" => "Before held compaction"}])
    finish_turn(pid, thread, seed)

    # This empty RPC result acknowledges submission, not successful compaction.
    assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
    assert %{"event" => "compaction_held", "index" => 2, "attempt" => 1} = next_notice(ctx)

    started = collect_until(pid, &compaction_started?(&1, thread))
    {turn, item} = compaction_identity(started, thread)
    refute terminal(started, turn)
    assert [_, request] = ModelFixture.requests(ctx.fixture)
    assert compaction_request?(request)

    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}
    interrupted = collect_until(pid, &terminal(&1, turn), started)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "interrupted"}} =
             terminal(interrupted, turn)

    # Release only after the real server has reported interruption. The provider
    # records whether late output was written or the cancelled peer had closed.
    assert Port.command(ctx.fixture.port, JSON.encode!(%{"release" => true}) <> "\n")

    assert %{"event" => "late_output_released", "index" => 2, "outcome" => outcome} =
             next_notice(ctx)

    assert outcome in ["written", "peer_closed"]
    followup = start_turn(pid, thread, [%{"type" => "text", "text" => "After interruption"}])
    later = finish_turn(pid, thread, followup)
    assert [_, _, ordinary] = ModelFixture.requests(ctx.fixture)
    assert checkpoints(ordinary) == []
    assert request_text?(ordinary, "Before held compaction")
    assert request_text?(ordinary, "After interruption")
    assert_one_terminal(interrupted ++ later, turn, "interrupted")

    assert notification(interrupted, "item/started", &(&1["item"]["id"] == item))
    assert :ok = Session.close(pid)
    resumed = start(ctx)
    assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    cold = start_turn(resumed, thread, [%{"type" => "text", "text" => "After cold resume"}])
    finish_turn(resumed, thread, cold)
    assert [_, _, _, after_resume] = ModelFixture.requests(ctx.fixture)
    assert checkpoints(after_resume) == []
    assert request_text?(after_resume, "Before held compaction")
    assert request_text?(after_resume, "After interruption")
    refute JSON.encode!(after_resume) =~ @late
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
  end

  @tag scenario: "retry"
  test "remote v2 retries open and incomplete stream failures without persisting provisional output",
       ctx do
    pid = start(ctx)
    thread = thread(ctx, pid)
    seed = start_turn(pid, thread, [%{"type" => "text", "text" => "Original retry history"}])
    finish_turn(pid, thread, seed)

    assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
    events = collect_until(pid, &compaction_completed?(&1, thread))
    {turn, item} = compaction_identity(events, thread)
    assert_one_terminal(events, turn, "completed")

    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"id" => ^item}} =
             notification(events, "item/completed", &(&1["item"]["id"] == item))

    assert Enum.map(1..3, fn _ -> next_notice(ctx) end) == [
             %{"event" => "compaction_attempt", "index" => 2, "attempt" => 1},
             %{"event" => "compaction_attempt", "index" => 3, "attempt" => 2},
             %{"event" => "compaction_attempt", "index" => 4, "attempt" => 3}
           ]

    assert [_, first, second, third] = ModelFixture.requests(ctx.fixture)
    assert Enum.all?([first, second, third], &compaction_request?/1)
    assert first["input"] == second["input"]
    assert second["input"] == third["input"]
    assert request_text?(first, "Original retry history")
    assert Enum.all?([first, second, third], &(checkpoints(&1) == []))

    followup = start_turn(pid, thread, [%{"type" => "text", "text" => "After successful retry"}])
    later = finish_turn(pid, thread, followup)
    assert [_, _, _, _, ordinary] = ModelFixture.requests(ctx.fixture)
    assert checkpoints(ordinary) == [@final]
    refute JSON.encode!(ordinary) =~ @failed
    refute compaction_request?(ordinary)
    assert_one_terminal(events ++ later, turn, "completed")

    assert :ok = Session.close(pid)
    resumed = start(ctx)
    assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    cold = start_turn(resumed, thread, [%{"type" => "text", "text" => "Retry cold resume"}])
    finish_turn(resumed, thread, cold)
    assert [_, _, _, _, _, after_resume] = ModelFixture.requests(ctx.fixture)
    assert checkpoints(after_resume) == [@final]
    refute JSON.encode!(after_resume) =~ @failed
    refute compaction_request?(after_resume)
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
  end

  defp next_notice(ctx), do: next_notice(ctx.fixture.port, now() + 20_000)

  defp next_notice(port, deadline) do
    key = {__MODULE__, port}
    buffer = Process.get(key, "")

    case String.split(buffer, "\n", parts: 2) do
      [line, rest] ->
        Process.put(key, rest)
        JSON.decode!(line)

      _ ->
        receive do
          {^port, {:data, bytes}} ->
            Process.put(key, buffer <> bytes)
            next_notice(port, deadline)

          {^port, {:exit_status, status}} ->
            flunk("Owned compaction fixture exited: #{status}")
        after
          max(deadline - now(), 0) -> flunk("Compaction fixture barrier deadline")
        end
    end
  end

  defp collect_until(pid, predicate, events \\ []),
    do: collect_until(pid, predicate, events, now() + 20_000)

  defp collect_until(pid, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if predicate.(events) do
      events
    else
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect_until(pid, predicate, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected gap during controlled compaction")
      after
        max(deadline - now(), 0) -> flunk("Controlled compaction event deadline")
      end
    end
  end

  defp compaction_started?(events, thread),
    do:
      notification(
        events,
        "item/started",
        &(&1["threadId"] == thread && &1["item"]["type"] == "contextCompaction")
      )

  defp compaction_completed?(events, thread) do
    if started = compaction_started?(events, thread), do: terminal(events, started["turnId"])
  end

  defp compaction_identity(events, thread) do
    assert %{"threadId" => ^thread, "turnId" => turn, "item" => %{"id" => item}} =
             compaction_started?(events, thread)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             notification(events, "turn/started", &(&1["turn"]["id"] == turn))

    {turn, item}
  end

  defp terminal(events, turn),
    do: notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp assert_one_terminal(events, turn, status) do
    terminals =
      Enum.filter(events, fn event ->
        event.wire["method"] == "turn/completed" &&
          get_in(event.wire, ["params", "turn", "id"]) == turn
      end)

    assert [event] = terminals
    assert get_in(event.wire, ["params", "turn", "status"]) == status
  end

  defp checkpoints(request),
    do:
      request["input"]
      |> Enum.filter(&(&1["type"] == "compaction"))
      |> Enum.map(& &1["encrypted_content"])

  defp compaction_request?(request),
    do: Enum.any?(request["input"], &(&1["type"] == "compaction_trigger"))

  defp request_text?(request, text),
    do:
      Enum.any?(request["input"], fn item ->
        Enum.any?(Map.get(item, "content", []), &(&1["text"] == text))
      end)

  defp now, do: System.monotonic_time(:millisecond)
end
