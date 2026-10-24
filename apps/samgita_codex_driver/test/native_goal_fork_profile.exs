defmodule SamgitaCodexDriver.GoalForkRecordingUDS do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.UnixSocket

  @impl true
  def open(opts) do
    with {:ok, inner} <- UnixSocket.open(opts),
         do: {:ok, %{inner: inner, sent: Keyword.fetch!(opts, :sent_path)}}
  end

  @impl true
  def send(state, json) do
    File.write!(state.sent, json <> "\n", [:append])

    case UnixSocket.send(state.inner, json) do
      {:ok, inner} -> {:ok, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case UnixSocket.handle_info(message, state.inner) do
      :unknown -> :unknown
      {:ok, events, inner} -> {:ok, events, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def close(state), do: UnixSocket.close(state.inner)
  @impl true
  def metadata(state), do: UnixSocket.metadata(state.inner)
end

defmodule SamgitaCodexDriver.NativeGoalForkProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{GoalForkRecordingUDS, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_goal_fork_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @objective "Owned synthetic fork continuation; retain the objective until its token budget stops work."
  @source "synthetic:goal-fork:source"
  @explicit "synthetic:goal-fork:explicit"
  @answers [
    "Owned source fork baseline",
    "Owned explicit fork progress",
    "Owned fork budget stop"
  ]

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-gf-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{root: root, owner: owner, socket: Path.join(root, "native.sock")}
    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]
    assert File.read_link!("/proc/#{proof["native_pid"]}/ns/net") == proof["namespace"]

    assert [%{"request_auth" => "none", "request_budget" => 3, "source_provider_requests" => 0}] =
             Enum.map(journal(ctx, "goal_fork_provider_ready"), &Map.delete(&1, "event"))

    config = File.read!(Path.join(root, "codex/config.toml"))

    for setting <- [
          "goals = true",
          "max_goal_token_budget = 20",
          "requires_openai_auth = false",
          "supports_websockets = false",
          "request_max_retries = 0",
          "stream_max_retries = 0",
          "enable_request_compression = false",
          "shell_tool = false",
          "unified_exec = false",
          "shell_snapshot = false",
          "plugins = false",
          "apps = false",
          "hooks = false",
          "[analytics]\nenabled = false",
          "cli_auth_credentials_store = \"file\""
        ] do
      assert config =~ setting
    end

    refute config =~ "experimental_bearer_token"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    ctx
  end

  test "native deferred goal fork survives restart then explicit work admits one budgeted continuation",
       ctx do
    {pid, _sent} = connect(ctx, true)

    source =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(source)
    assert goal(pid, source) == nil
    assert_attempts(ctx, 0)
    source_turn = start_turn(pid, source, @source, "owned_fork_source")
    source_events = collect(pid, &(length(notices(&1, "turn/completed")) == 1))
    assert_lifecycle(source_events, source, [source_turn], [1])
    assert [source_history] = turns(pid, source)
    assert Enum.filter(source_history["items"], &(&1["type"] == "agentMessage")) == [assistant(1)]

    {cold, _sent} = restart(ctx, pid)
    assert loaded(cold) == []
    timing = %{wall: System.system_time(:second), mono: now()}
    # A real API mutation on the cold materialized source records user intent but
    # has no registered runtime to start. No database rows or protocol frames are seeded.
    initial =
      call(cold, "thread/goal/set", %{
        "threadId" => source,
        "objective" => @objective,
        "status" => "active",
        "tokenBudget" => 20,
        "origin" => "user"
      })["goal"]

    assert_goal(initial, source, "active", 0, initial["createdAt"], timing)
    assert initial["timeUsedSeconds"] == 0
    assert goal(cold, source) == initial and loaded(cold) == []
    quiet(ctx, cold, 1)

    # Capture only AFTER the authorized native user-intent append above.
    path =
      call(cold, "thread/read", %{"threadId" => source, "includeTurns" => false})["thread"][
        "path"
      ]

    assert String.starts_with?(path, ctx.root <> "/codex/")
    baseline = %{path: path, bytes: File.read!(path), history: turns(cold, source), goal: initial}
    assert Enum.map(baseline.history, & &1["id"]) == [source_turn]

    for negotiation <- [:absent, false] do
      {stable, sent} = connect(ctx, negotiation)

      for extra <- [%{}, %{"deferGoalContinuation" => false}] do
        params = Map.merge(%{"threadId" => source, "excludeTurns" => true}, extra)
        child = call(stable, "thread/fork", params)["thread"]
        assert_uuid(child["id"])
        assert child["id"] != source and child["forkedFromId"] == source
        assert child["path"] != path and child["turns"] == []
        assert goal(stable, child["id"]) == nil
        assert turns(stable, child["id"]) == baseline.history
        assert last_params(sent, "thread/fork") == params
      end

      params = %{"threadId" => source, "excludeTurns" => true, "deferGoalContinuation" => true}
      before = count(sent, "thread/fork")
      current = loaded(stable)

      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(stable, "thread/fork", params)

      assert count(sent, "thread/fork") == before

      assert wire_error(stable, params) == %{
               "code" => -32_600,
               "message" =>
                 "thread/fork.deferGoalContinuation requires experimentalApi capability"
             }

      null = %{params | "deferGoalContinuation" => nil}
      before = count(sent, "thread/fork")

      assert {:error, %Error{code: :schema_violation}} =
               Session.request(stable, "thread/fork", null)

      assert count(sent, "thread/fork") == before

      assert wire_error(stable, null) == %{
               "code" => -32_600,
               "message" => "Invalid request: invalid type: null, expected a boolean"
             }

      assert loaded(stable) == current
      assert_source(cold, source, baseline)
      quiet(ctx, stable, 1)
      assert :ok = Session.close(stable)
    end

    {enabled, sent} = connect(ctx, true)
    params = %{"threadId" => source, "excludeTurns" => true, "deferGoalContinuation" => true}
    before = loaded(enabled)

    assert wire_error(enabled, Map.put(params, "ephemeral", true)) == %{
             "code" => -32_600,
             "message" => "`deferGoalContinuation` cannot be combined with `ephemeral`"
           }

    assert loaded(enabled) == before
    assert_source(cold, source, baseline)
    quiet(ctx, enabled, 1)

    child = call(enabled, "thread/fork", params)["thread"]
    target = child["id"]
    assert_uuid(target)
    assert target != source and child["forkedFromId"] == source and child["path"] != path
    assert child["turns"] == [] and turns(enabled, target) == baseline.history
    inherited = Map.put(initial, "threadId", target)
    assert goal(enabled, target) == inherited
    assert last_params(sent, "thread/fork") == params
    assert_source(cold, source, baseline)
    quiet(ctx, enabled, 1)
    assert :ok = Session.close(cold)

    {resumed, _sent} = restart(ctx, enabled)
    assert loaded(resumed) == [] and goal(resumed, target) == inherited
    assert turns(resumed, target) == baseline.history and loaded(resumed) == []
    assert call(resumed, "thread/resume", %{"threadId" => target})["thread"]["id"] == target
    assert goal(resumed, target) == inherited
    assert_idle(resumed, target)
    quiet(ctx, resumed, 1)

    explicit_turn = start_turn(resumed, target, @explicit, "owned_fork_explicit")

    pending =
      collect(resumed, fn events ->
        length(notices(events, "turn/started")) == 2 and
          length(notices(events, "turn/completed")) == 1 and
          Enum.any?(
            notices(events, "thread/goal/updated"),
            &(&1["turnId"] == explicit_turn and &1["goal"]["tokensUsed"] == 9)
          ) and
          case json(ctx, "goal-http.json") do
            [_, _, %{"waitingForRelease" => true, "responded" => false}] -> true
            _ -> false
          end
      end)

    assert [explicit_notice, automatic_notice] = notices(pending, "turn/started")
    assert explicit_notice["turn"]["id"] == explicit_turn
    automatic_turn = automatic_notice["turn"]["id"]
    assert automatic_turn != explicit_turn
    active = goal(resumed, target)
    assert_goal(active, target, "active", 9, initial["createdAt"], timing)

    assert Enum.any?(
             notices(pending, "thread/goal/updated"),
             &(&1["threadId"] == target and &1["turnId"] == explicit_turn and
                 &1["goal"]["status"] == "active" and &1["goal"]["tokensUsed"] == 9)
           )

    assert_attempts(ctx, 3)
    control(ctx, "release_auto")

    execution =
      collect(
        resumed,
        fn events ->
          length(notices(events, "turn/completed")) == 2 and
            Enum.any?(
              notices(events, "thread/goal/updated"),
              &(&1["goal"]["status"] == "budgetLimited")
            )
        end,
        pending
      )

    assert_lifecycle(execution, target, [explicit_turn, automatic_turn], [2, 3])
    final = goal(resumed, target)
    assert_goal(final, target, "budgetLimited", 21, initial["createdAt"], timing)
    assert final["timeUsedSeconds"] >= active["timeUsedSeconds"]

    assert Enum.any?(
             notices(execution, "thread/goal/updated"),
             &(&1 == %{"threadId" => target, "turnId" => automatic_turn, "goal" => final})
           )

    target_history = turns(resumed, target)
    assert Enum.take(target_history, 1) == baseline.history
    assert Enum.map(target_history, & &1["id"]) == [source_turn, explicit_turn, automatic_turn]

    for {turn, index} <- Enum.zip(tl(target_history), [2, 3]) do
      assert turn["status"] == "completed" and turn["error"] == nil
      assert Enum.filter(turn["items"], &(&1["type"] == "agentMessage")) == [assistant(index)]
    end

    assert_provider(ctx, source, source_turn, target, explicit_turn, automatic_turn)
    assert_source(resumed, source, baseline)
    refute source in loaded(resumed)
    assert_idle(resumed, target)
    quiet(ctx, resumed, 3)

    # Cutoffs select historical turns, while goal inheritance copies the current
    # native snapshot. None of these stopped children may issue another request.
    prefix_source = %{
      path: child["path"],
      bytes: File.read!(child["path"]),
      history: target_history,
      goal: final
    }

    prefix_children =
      for {boundary, expected_history} <- [
            {%{"lastTurnId" => explicit_turn}, Enum.take(target_history, 2)},
            {%{"beforeTurnId" => explicit_turn}, Enum.take(target_history, 1)},
            {%{"beforeTurnId" => source_turn}, []}
          ] do
        params =
          Map.merge(
            %{"threadId" => target, "excludeTurns" => true, "deferGoalContinuation" => true},
            boundary
          )

        forked = call(resumed, "thread/fork", params)["thread"]
        id = forked["id"]
        assert_uuid(id)
        refute id in [source, target]
        assert forked["forkedFromId"] == target and forked["turns"] == []
        assert String.starts_with?(forked["path"], ctx.root <> "/codex/")
        refute forked["path"] in [baseline.path, prefix_source.path]
        expected_goal = Map.put(final, "threadId", id)
        assert goal(resumed, id) == expected_goal
        assert turns(resumed, id) == expected_history
        assert_goal_fork_source(resumed, target, prefix_source)
        assert_attempts(ctx, 3)
        %{id: id, path: forked["path"], goal: expected_goal, history: expected_history}
      end

    assert length(Enum.uniq_by(prefix_children, & &1.id)) == 3
    assert length(Enum.uniq_by(prefix_children, & &1.path)) == 3

    {last, _sent} = restart(ctx, resumed)
    assert loaded(last) == [] and goal(last, target) == final
    assert turns(last, target) == target_history and loaded(last) == []

    for prefix <- prefix_children do
      assert goal(last, prefix.id) == prefix.goal
      assert turns(last, prefix.id) == prefix.history

      stored =
        call(last, "thread/read", %{"threadId" => prefix.id, "includeTurns" => false})["thread"]

      assert stored["id"] == prefix.id and stored["path"] == prefix.path
      assert stored["forkedFromId"] == target
      assert loaded(last) == []
    end

    assert_goal_fork_source(last, target, prefix_source)
    assert_source(last, source, baseline)
    empty = List.last(prefix_children)
    assert empty.history == []

    restored =
      call(last, "thread/resume", %{"threadId" => empty.id, "excludeTurns" => true})["thread"]

    assert restored["id"] == empty.id and restored["turns"] == []
    assert goal(last, empty.id) == empty.goal and turns(last, empty.id) == []
    assert_idle(last, empty.id)
    assert loaded(last) == [empty.id]
    assert_goal_fork_source(last, target, prefix_source)
    assert_attempts(ctx, 3)

    assert call(last, "thread/resume", %{"threadId" => target})["thread"]["id"] == target
    assert goal(last, target) == final and turns(last, target) == target_history
    assert_source(last, source, baseline)
    assert_idle(last, target)
    quiet(ctx, last, 3)
    assert :ok = Session.close(last)
    control(ctx, "close")
    assert length(journal(ctx, "fixture_closed")) == 1
  end

  defp assert_source(pid, id, baseline) do
    assert goal(pid, id) == baseline.goal
    assert turns(pid, id) == baseline.history
    assert File.read!(baseline.path) == baseline.bytes
    refute id in loaded(pid)
  end

  defp assert_goal_fork_source(pid, id, snapshot) do
    assert goal(pid, id) == snapshot.goal
    assert turns(pid, id) == snapshot.history
    assert File.read!(snapshot.path) == snapshot.bytes
  end

  defp assert_goal(value, id, status, tokens, created, timing) do
    assert Enum.sort(Map.keys(value)) ==
             Enum.sort(
               ~w(threadId objective status tokenBudget tokensUsed timeUsedSeconds createdAt updatedAt)
             )

    assert value["threadId"] == id and value["objective"] == @objective

    assert value["status"] == status and value["tokenBudget"] == 20 and
             value["tokensUsed"] == tokens

    assert value["createdAt"] == created and created >= timing.wall
    for key <- ~w(createdAt updatedAt timeUsedSeconds), do: assert(is_integer(value[key]))
    assert value["updatedAt"] >= created and value["updatedAt"] <= System.system_time(:second)

    assert value["timeUsedSeconds"] >= 0 and
             value["timeUsedSeconds"] <= div(now() - timing.mono, 1000) + 1
  end

  defp assert_lifecycle(events, id, ids, indexes) do
    refute Enum.any?(events, &(&1.kind == :server_request or &1.wire["method"] == "error"))
    for turn <- ids, do: assert_uuid(turn)
    assert Enum.map(notices(events, "turn/started"), & &1["turn"]["id"]) == ids
    assert Enum.map(notices(events, "turn/completed"), & &1["turn"]["id"]) == ids

    for notice <- notices(events, "turn/started") ++ notices(events, "turn/completed"),
        do: assert(notice["threadId"] == id)

    for notice <- notices(events, "turn/completed"),
        do: assert(notice["turn"]["status"] == "completed" and notice["turn"]["error"] == nil)

    for {turn, index} <- Enum.zip(ids, indexes), method <- ["item/started", "item/completed"] do
      assert [notice] =
               Enum.filter(
                 notices(events, method),
                 &(&1["turnId"] == turn and &1["item"]["type"] == "agentMessage")
               )

      assert notice["threadId"] == id and notice["item"] == assistant(index)
    end
  end

  defp assert_provider(ctx, source, first, target, explicit_turn, automatic) do
    await(fn -> Enum.all?(json(ctx, "goal-http.json"), & &1["responded"]) end)
    requests = json(ctx, "requests.json")
    records = json(ctx, "goal-http.json")
    assert length(records) == 3 and length(requests) == 3

    for {record, index} <- Enum.with_index(records, 1) do
      raw = Base.decode64!(record["rawBodyBase64"])

      assert hash(raw) == record["rawBodySHA256"] and
               JSON.decode!(raw) == Enum.at(requests, index - 1)

      assert record["path"] == "/v1/responses" and record["requestAuth"] == "none" and
               record["responded"]

      assert record["metadata"]["thread_id"] == Enum.at([source, target, target], index - 1)

      assert record["metadata"]["turn_id"] ==
               Enum.at([first, explicit_turn, automatic], index - 1)

      assert record["metadata"]["turn_trigger"] ==
               Enum.at(["owned_fork_source", "owned_fork_explicit", "goal"], index - 1)

      response = Base.decode64!(record["rawResponseBase64"])
      assert hash(response) == record["rawResponseSHA256"]

      actual =
        for block <- String.split(response, "\n\n", trim: true) do
          assert ["event: " <> event, "data: " <> data] = String.split(block, "\n")
          {event, JSON.decode!(data)}
        end

      identity = "owned-goal-fork-response-#{index}"

      assert actual == [
               {"response.created",
                %{"type" => "response.created", "response" => %{"id" => identity}}},
               {"response.output_item.done",
                %{
                  "type" => "response.output_item.done",
                  "item" => %{
                    "type" => "message",
                    "role" => "assistant",
                    "id" => "owned-goal-fork-answer-#{index}",
                    "content" => [
                      %{"type" => "output_text", "text" => Enum.at(@answers, index - 1)}
                    ]
                  }
                }},
               {"response.completed",
                %{
                  "type" => "response.completed",
                  "response" => %{"id" => identity, "usage" => usage(index)}
                }}
             ]
    end

    assert List.last(records)["waitingForRelease"]
    assert 7 - 3 + 5 == 9 and 11 - 2 + 3 == 12 and 9 + 12 == 21
  end

  defp usage(index) do
    {incoming, cached, outgoing} = Enum.at([{0, 0, 0}, {7, 3, 5}, {11, 2, 3}], index - 1)

    %{
      "input_tokens" => incoming,
      "input_tokens_details" => %{"cached_tokens" => cached, "cache_write_tokens" => 0},
      "output_tokens" => outgoing,
      "output_tokens_details" => %{"reasoning_tokens" => 0},
      "total_tokens" => incoming + outgoing
    }
  end

  defp assistant(index),
    do: %{
      "type" => "agentMessage",
      "id" => "owned-goal-fork-answer-#{index}",
      "text" => Enum.at(@answers, index - 1),
      "delivery" => nil,
      "memoryCitation" => nil,
      "phase" => nil,
      "questions" => nil
    }

  defp quiet(ctx, pid, attempts) do
    control(ctx, "barrier")
    quiet_until(ctx, pid, attempts, now() + 1_000)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []

    assert json(ctx, "provider-errors.json") == [] and
             json(ctx, "rejected-realtime-posts.json") == []

    refute Enum.any?(
             json(ctx, "realtime-journal.json"),
             &(&1["event"] in ["handshake", "native_frame"])
           )

    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
  end

  defp quiet_until(ctx, pid, attempts, deadline) do
    assert {:ok, events} = Session.drain(pid)

    refute Enum.any?(
             events,
             &(&1.kind == :server_request or
                 &1.wire["method"] in ["error", "turn/started", "turn/completed"])
           )

    assert_attempts(ctx, attempts)

    if now() < deadline do
      receive do
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native fork observation gap")
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        20 -> :ok
      end

      quiet_until(ctx, pid, attempts, deadline)
    end
  end

  defp assert_attempts(ctx, expected) do
    assert json(ctx, "goal-attempts.json") == expected
    assert length(json(ctx, "requests.json")) == expected
    assert length(json(ctx, "goal-http.json")) == expected
    assert json(ctx, "provider-errors.json") == []
  end

  defp assert_idle(pid, id),
    do:
      await(fn ->
        call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]["status"] ==
          %{"type" => "idle"}
      end)

  defp goal(pid, id), do: call(pid, "thread/goal/get", %{"threadId" => id})["goal"]
  defp loaded(pid), do: call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort()

  defp turns(pid, id) do
    result =
      call(pid, "thread/turns/list", %{
        "threadId" => id,
        "limit" => 100,
        "sortDirection" => "asc",
        "itemsView" => "full"
      })

    assert result["nextCursor"] == nil
    result["data"]
  end

  defp start_turn(pid, id, text, trigger),
    do:
      call(pid, "turn/start", %{
        "threadId" => id,
        "input" => [%{"type" => "text", "text" => text}],
        "turnTrigger" => trigger
      })["turn"]["id"]

  defp wire_error(pid, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, "thread/fork", params, validation: :wire)

    error
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp connect(ctx, negotiation) do
    sent = Path.join(ctx.root, "sent-#{System.unique_integer([:positive])}.jsonl")
    File.write!(sent, "")

    {:ok, pid} =
      Session.start_link(
        transport: {GoalForkRecordingUDS, [socket_path: ctx.socket, sent_path: sent]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_goal_fork", "version" => "0.1.0"},
               capabilities
             )

    {pid, sent}
  end

  defp restart(ctx, pid) do
    instance = Session.status(pid).instance_id
    previous = json(ctx, "state.json")["native_pid"]
    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{previous}")
    control(ctx, "restart")
    refute File.exists?("/proc/#{previous}")
    refute json(ctx, "state.json")["native_pid"] == previous
    {cold, sent} = connect(ctx, true)
    refute Session.status(cold).instance_id == instance
    {cold, sent}
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: assert_process_reaped(pid)

      assert journal(ctx, "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned goal fork evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp control(ctx, op) do
    id = "owned-goal-fork-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.any?(journal(ctx, "control_done"), &(&1["id"] == id)) end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || now() + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert now() < deadline, "Owned native goal-fork event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native goal-fork event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || now() + 10_000

    if value = predicate.() do
      value
    else
      assert now() < deadline, "Owned native goal-fork fixture deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp assert_uuid(value),
    do:
      assert(
        is_binary(value) and
          Regex.match?(~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, value)
      )

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp journal(ctx, event),
    do: json(ctx, "bem-journal.json") |> Enum.filter(&(&1["event"] == event))

  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()

  defp sent(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp count(path, method), do: Enum.count(sent(path), &(&1["method"] == method))

  defp last_params(path, method),
    do:
      sent(path) |> Enum.filter(&(&1["method"] == method)) |> List.last() |> Map.fetch!("params")

  defp hash(value), do: Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
