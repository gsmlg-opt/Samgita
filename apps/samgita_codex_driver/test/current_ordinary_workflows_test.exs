defmodule SamgitaCodexDriver.CurrentOrdinaryWorkflowsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @provider Path.expand("../../../scripts/codex/ordinary_consumer_provider.py", __DIR__)
  @answer "Deterministic local fixture answer"

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    context =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    TurnFixture.configure_model(context, %{})
    Map.put(context, :pid, TurnFixture.start(context))
  end

  test "the selected client creates and lists a persistent Project with its root", ctx do
    project = create_project(ctx)
    result = request(ctx.pid, "project/list", %{})
    assert Enum.any?(result["data"], &(&1["id"] == project["id"]))
    assert project["name"] == "Current ordinary Project"
    assert project["roots"] == [%{"path" => ctx.fixture.workspace}]
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.status(ctx.pid).phase == :ready
  end

  test "Project chat streams text and restores the same completed turn after reconnect", ctx do
    project = create_project(ctx)

    result =
      request(ctx.pid, "thread/start", %{
        "cwd" => ctx.fixture.workspace,
        "projectId" => project["id"],
        "ephemeral" => false
      })

    thread = result["thread"]["id"]
    assert is_binary(thread)
    assert result["thread"]["projectId"] == project["id"]

    result =
      request(ctx.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "Owned current ordinary chat"}]
      })

    turn = result["turn"]["id"]
    assert is_binary(turn)
    events = completed_events(ctx.pid, turn, [], System.monotonic_time(:millisecond) + 10_000)

    deltas =
      for %{kind: :notification, wire: %{"method" => "item/agentMessage/delta"} = wire} <- events,
          do: wire["params"]["delta"]

    assert deltas != []
    assert Enum.join(deltas) == @answer

    assert Enum.any?(events, fn event ->
             get_in(event, [:wire, "method"]) == "turn/completed" &&
               get_in(event, [:wire, "params", "turn", "id"]) == turn &&
               get_in(event, [:wire, "params", "turn", "status"]) == "completed"
           end)

    original = request(ctx.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert_history(original, thread, turn)
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    generation = Session.status(ctx.pid).generation
    assert :ok = Session.reconnect(ctx.pid)

    assert {:ok, _} =
             Session.initialize(
               ctx.pid,
               %{"name" => "samgita_current_ordinary", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    resumed = request(ctx.pid, "thread/resume", %{"threadId" => thread})
    assert_history(resumed, thread, turn)
    restored = request(ctx.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert restored["thread"]["turns"] == original["thread"]["turns"]
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert Session.status(ctx.pid).generation == generation + 1
    assert Session.status(ctx.pid).gap.reason == :explicit_reconnect
    assert Session.status(ctx.pid).uncertain == 0
  end

  defp create_project(ctx) do
    request(ctx.pid, "project/create", %{
      "idempotencyKey" => "owned-current-ordinary-project",
      "name" => "Current ordinary Project",
      "roots" => [%{"path" => ctx.fixture.workspace}]
    })["project"]
  end

  defp request(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params, timeout_ms: 5_000)
    result
  end

  defp completed_events(pid, turn, accumulated, deadline) do
    assert {:ok, events} = Session.drain(pid)
    accumulated = accumulated ++ events
    assert length(accumulated) <= 256
    assert byte_size(JSON.encode!(Enum.map(accumulated, & &1.wire))) <= 1_048_576
    assert Enum.all?(accumulated, &(&1.kind == :notification))

    if Enum.any?(accumulated, fn event ->
         event.wire["method"] == "turn/completed" && event.wire["params"]["turn"]["id"] == turn
       end) do
      accumulated
    else
      remaining = deadline - System.monotonic_time(:millisecond)
      assert remaining > 0, "Current ordinary turn completion deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          completed_events(pid, turn, accumulated, deadline)
      after
        remaining -> flunk("Current ordinary turn completion deadline")
      end
    end
  end

  defp assert_history(result, thread, turn) do
    assert result["thread"]["id"] == thread
    assert [completed] = Enum.filter(result["thread"]["turns"], &(&1["id"] == turn))
    assert completed["status"] == "completed"
    messages = Enum.filter(completed["items"], &(&1["type"] == "agentMessage"))
    assert [%{"text" => @answer}] = messages
  end
end
