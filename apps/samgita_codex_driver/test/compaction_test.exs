defmodule SamgitaCodexDriver.CompactionTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @checkpoint "SYNTHETIC_COMPACTION_CHECKPOINT"

  setup {TurnFixture, :setup}

  for retained <- [false, true] do
    @tag retained: retained
    test "remote compaction and cold resume honor tool-output retention=#{retained}", context do
      fixture = ModelFixture.start(Path.join(context.root, "compact"), "compaction")
      on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
      context = %{context | fixture: fixture}

      File.write!(
        Path.join(fixture.codex_home, "config.toml"),
        """

        [model_providers.fixture.capabilities]
        remote_compaction = "v2"
        [features]
        retain_client_tool_outputs = #{context.retained}
        """,
        [:append]
      )

      pid = start(context)
      thread = thread(context, pid)

      for {name, retained} <- [{"retained_instruction", true}, {"transient_progress", false}] do
        turn =
          start_turn(pid, thread, [], %{
            "toolOutput" => %{
              "name" => name,
              "namespace" => "synthetic_compaction",
              "output" => "#{name}: é🙂",
              "retain" => retained
            }
          })

        finish_turn(pid, thread, turn)
      end

      assert length(ModelFixture.requests(fixture)) == 2
      assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
      events = compacted(pid, thread)
      assert_compaction_lifecycle(events, thread)
      assert [_, _, compact] = ModelFixture.requests(fixture)
      assert [_trigger] = Enum.filter(compact["input"], &(&1["type"] == "compaction_trigger"))

      assert Enum.map(outputs(compact), & &1["name"]) == [
               "retained_instruction",
               "transient_progress"
             ]

      assert :ok = Session.close(pid)
      resumed = start(context)
      assert call(resumed, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
      assert length(ModelFixture.requests(fixture)) == 3

      turn = start_turn(resumed, thread, [%{"type" => "text", "text" => "After cold resume"}])
      finish_turn(resumed, thread, turn)
      assert [_, _, _, after_resume] = ModelFixture.requests(fixture)

      assert [%{"encrypted_content" => @checkpoint}] =
               Enum.filter(after_resume["input"], &(&1["type"] == "compaction"))

      if context.retained do
        assert [kept] = outputs(after_resume)
        assert kept["name"] == "retained_instruction"
        assert kept["namespace"] == "synthetic_compaction"
        assert kept["output"] == "retained_instruction: é🙂"
        refute Map.has_key?(kept, "call_id")
        refute Map.has_key?(kept, "retain")
        refute Map.has_key?(kept, "client_authored")
      else
        assert outputs(after_resume) == []
      end

      refute Enum.any?(after_resume["input"], &(&1["type"] == "compaction_trigger"))
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
    end
  end

  test "local compaction emits a correlated item and carries its summary into the next request",
       context do
    config = Path.join(context.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "compact_prompt = \"Synthetic explicit compaction prompt\"\n" <> File.read!(config)
    )

    pid = start(context)
    thread = thread(context, pid)
    turn = start_turn(pid, thread, [%{"type" => "text", "text" => "Seed local history"}])
    finish_turn(pid, thread, turn)

    assert call(pid, "thread/compact/start", %{"threadId" => thread}) == %{}
    events = compacted(pid, thread)
    assert_compaction_lifecycle(events, thread)
    assert [_, compact] = ModelFixture.requests(context.fixture)
    refute Enum.any?(compact["input"], &(&1["type"] == "compaction_trigger"))
    assert request_text?(compact, "Synthetic explicit compaction prompt")

    turn = start_turn(pid, thread, [%{"type" => "text", "text" => "Continue local history"}])
    finish_turn(pid, thread, turn)
    assert [_, _, followup] = ModelFixture.requests(context.fixture)
    refute request_text?(followup, "Synthetic explicit compaction prompt")

    assert Enum.any?(followup["input"], fn item ->
             Enum.any?(Map.get(item, "content", []), fn content ->
               is_binary(content["text"]) and
                 String.contains?(content["text"], "Deterministic local fixture answer") and
                 String.contains?(content["text"], "summary")
             end)
           end)
  end

  test "invalid and missing compact targets fail without a turn or provider request", context do
    pid = start(context)

    for {thread, message} <- [
          {"not-a-thread-id", "invalid thread id"},
          {"67e55044-10b1-426f-9247-bb680e5fe0c8", "thread not found"}
        ] do
      error = upstream_error(pid, "thread/compact/start", %{"threadId" => thread})
      assert error["code"] == -32_600
      assert error["message"] =~ message
    end

    assert [] = ModelFixture.requests(context.fixture)
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
    refute notification(events, "item/started")
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp outputs(request),
    do: Enum.filter(request["input"], &(&1["type"] == "function_call_output"))

  defp request_text?(request, text) do
    Enum.any?(request["input"], fn item ->
      Enum.any?(Map.get(item, "content", []), &(&1["text"] == text))
    end)
  end

  defp compacted(pid, thread) do
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
        remaining -> flunk("Real compaction did not complete before its deadline")
      end
    end
  end

  defp assert_compaction_lifecycle(events, thread) do
    assert %{"turnId" => turn, "item" => %{"type" => "contextCompaction", "id" => item}} =
             notification(events, "item/started", &(&1["item"]["type"] == "contextCompaction"))

    assert %{
             "threadId" => ^thread,
             "turnId" => ^turn,
             "item" => %{"type" => "contextCompaction", "id" => ^item}
           } =
             notification(events, "item/completed", &(&1["item"]["type"] == "contextCompaction"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed")

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn}} =
             notification(events, "turn/started")

    refute Enum.any?(events, &(&1.kind == :server_request))
  end
end
