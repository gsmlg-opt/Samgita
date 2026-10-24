defmodule SamgitaCodexDriver.NativeRealtimeBemProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_realtime_bem_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned explicit BEM turn λ"
  @output "Owned fixed tool output λ"
  @answer "Owned synthetic dynamic result acknowledged"
  @markdown "::codex-realtime-inline{}\nOwned markdown λ"
  @visualization "```\n::codex-inline-vis{file=hidden}\n```\n~~~\nvisualize{file=also-hidden}\n~~~\n::codex-inline-vis{file=first}\nvisualize{file=second}"
  @tool %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Owned fixed synthetic lookup",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-realtime-bem-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [
          @script,
          "--root",
          root,
          "--codex",
          Path.expand(binary),
          "--scenario",
          tags.scenario
        ],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{
      root: root,
      owner: owner,
      socket: Path.join(root, "native.sock"),
      scenario: tags.scenario
    }

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do: await(fn -> not File.exists?("/proc/#{os_pid}") end)

        assert events(ctx, "bem-journal.json", "fixture_closed") != []
      end

      File.rm_rf!(root)
    end)

    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    ctx
  end

  for scenario <- ~w(dynamic markdown visualization) do
    @scenario scenario
    @tag scenario: scenario
    test "native #{@scenario} BEM promotion retains full backing history and cold identity",
         ctx do
      pid = connect(ctx)

      thread =
        call(pid, "thread/start", %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => Path.join(ctx.root, "workspace"),
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "historyMode" => "paginated",
          "ephemeral" => false,
          "dynamicTools" => if(@scenario == "dynamic", do: [@tool], else: [])
        })["thread"]["id"]

      session_id = "owned-bem-#{@scenario}"

      assert call(pid, "thread/realtime/start", %{
               "threadId" => thread,
               "realtimeSessionId" => session_id,
               "outputModality" => "text",
               "flushTranscriptTailOnSessionEnd" => false
             }) == %{}

      started = collect(pid, &notice(&1, "thread/realtime/started"))
      assert notice(started, "thread/realtime/started")["realtimeSessionId"] == session_id
      before_turn = System.system_time(:second)

      turn =
        call(pid, "turn/start", %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => @input}]
        })["turn"]["id"]

      assert_uuid(turn)

      execution =
        if @scenario == "dynamic" do
          pending = collect(pid, &Enum.any?(&1, fn event -> event.kind == :server_request end))
          assert [tool] = Enum.filter(pending, &(&1.kind == :server_request))
          assert tool.wire["method"] == "item/tool/call"

          assert tool.wire["params"] == %{
                   "threadId" => thread,
                   "turnId" => turn,
                   "callId" => "owned-bem-tool-call",
                   "namespace" => nil,
                   "tool" => "fixture_lookup",
                   "arguments" => %{"key" => "synthetic"}
                 }

          assert tool.handle.generation == Session.status(pid).generation

          assert :ok =
                   Session.respond(
                     pid,
                     tool.handle,
                     {:ok,
                      %{
                        "success" => true,
                        "contentItems" => [%{"type" => "inputText", "text" => @output}]
                      }}
                   )

          collect(pid, &notice(&1, "turn/completed"), pending)
        else
          collect(pid, &notice(&1, "turn/completed"))
        end

      completion = notice(execution, "turn/completed")
      assert completion["threadId"] == thread
      assert completion["turn"]["id"] == turn and completion["turn"]["status"] == "completed"
      assert completion["turn"]["error"] == nil
      assert call(pid, "thread/realtime/stop", %{"threadId" => thread}) == %{}
      closing = collect(pid, &notice(&1, "thread/realtime/closed"))

      assert notice(closing, "thread/realtime/closed") == %{
               "threadId" => thread,
               "reason" => "requested"
             }

      all = started ++ execution ++ closing
      sources = assert_sources(execution, @scenario, thread, turn)
      facts = assert_promotions(all, @scenario, thread, turn, session_id)

      # This native read is the producer/store flush barrier, never a polling baseline.
      assert [hydrated] =
               call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"][
                 "turns"
               ]

      assert hydrated["id"] == turn and hydrated["status"] == "completed" and
               hydrated["items"] == sources

      assert hydrated["error"] == nil
      assert is_integer(hydrated["startedAt"]) and hydrated["startedAt"] >= before_turn

      assert is_integer(hydrated["completedAt"]) and
               hydrated["completedAt"] >= hydrated["startedAt"]

      assert hydrated["completedAt"] <= System.system_time(:second)
      assert is_integer(hydrated["durationMs"]) and hydrated["durationMs"] >= 0
      timeline_query = %{"threadId" => thread, "limit" => 100}
      warm = call(pid, "thread/timeline/list", timeline_query)
      assert_history(warm, sources, facts, hydrated)

      backing_query = %{
        "threadId" => thread,
        "turnId" => turn,
        "itemIds" => Enum.map(sources, & &1["id"])
      }

      backing = call(pid, "thread/items/read", backing_query)
      assert Enum.map(backing["data"], & &1["item"]) == sources
      assert Enum.all?(backing["data"], &(&1["turnId"] == turn))
      assert_safe(ctx, pid, @scenario)
      await(fn -> events(ctx, "realtime-journal.json", "peer_closed") != [] end)

      instance = Session.status(pid).instance_id
      old_native = state(ctx)["native_pid"]
      assert :ok = Session.close(pid)
      assert File.exists?("/proc/#{old_native}")
      control(ctx, "restart")
      refute File.exists?("/proc/#{old_native}")
      assert state(ctx)["native_pid"] != old_native
      cold = connect(ctx)
      assert Session.status(cold).instance_id != instance
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert call(cold, "thread/timeline/list", timeline_query) == warm
      assert call(cold, "thread/items/read", backing_query) == backing
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_safe(ctx, cold, @scenario)
      assert :ok = Session.close(cold)
      control(ctx, "close")
      assert length(events(ctx, "bem-journal.json", "fixture_closed")) == 1
      for native <- state(ctx)["native_pids"], do: refute(File.exists?("/proc/#{native}"))
    end
  end

  defp assert_sources(events, scenario, thread, turn) do
    completed =
      for event <- events, event.wire["method"] == "item/completed", do: event.wire["params"]

    assert Enum.all?(completed, &(&1["threadId"] == thread and &1["turnId"] == turn))
    sources = Enum.map(completed, & &1["item"])

    assert Enum.map(sources, & &1["type"]) ==
             if(scenario == "dynamic",
               do: ["userMessage", "dynamicToolCall", "agentMessage"],
               else: ["userMessage", "agentMessage"]
             )

    user = hd(sources)
    assert_uuid(user["id"])

    assert user == %{
             "type" => "userMessage",
             "id" => user["id"],
             "clientId" => nil,
             "content" => [%{"type" => "text", "text" => @input, "text_elements" => []}]
           }

    assistant = List.last(sources)

    text =
      %{"dynamic" => @answer, "markdown" => @markdown, "visualization" => @visualization}[
        scenario
      ]

    assert assistant == %{
             "type" => "agentMessage",
             "id" => "owned-bem-message",
             "text" => text,
             "phase" => nil,
             "memoryCitation" => nil,
             "delivery" => nil,
             "questions" => nil
           }

    if scenario == "dynamic" do
      dynamic = Enum.at(sources, 1)
      assert is_integer(dynamic["durationMs"]) and dynamic["durationMs"] >= 0

      assert dynamic == %{
               "type" => "dynamicToolCall",
               "id" => "owned-bem-tool-call",
               "namespace" => nil,
               "tool" => "fixture_lookup",
               "arguments" => %{"key" => "synthetic"},
               "status" => "completed",
               "contentItems" => [%{"type" => "inputText", "text" => @output}],
               "success" => true,
               "durationMs" => dynamic["durationMs"]
             }

      assert length(Enum.filter(events, &(&1.kind == :server_request))) == 1
    else
      refute Enum.any?(events, &(&1.kind == :server_request))
    end

    sources
  end

  defp assert_promotions(events, scenario, thread, turn, session_id) do
    params =
      for event <- events,
          event.wire["method"] == "thread/realtime/item/completed",
          do: event.wire["params"]

    facts = Enum.map(params, & &1["item"])

    presentations =
      case scenario do
        "dynamic" ->
          [%{"type" => "wholeItem"}]

        "markdown" ->
          [%{"type" => "inlineMarkdown"}]

        "visualization" ->
          [
            %{"type" => "inlineVisualization", "index" => 0},
            %{"type" => "inlineVisualization", "index" => 1}
          ]
      end

    assert length(facts) == length(presentations) + 2
    assert length(Enum.uniq_by(facts, & &1["id"])) == length(facts)
    backing = if scenario == "dynamic", do: "owned-bem-tool-call", else: "owned-bem-message"

    contents =
      [%{"type" => "realtimeSessionStarted"}] ++
        Enum.map(
          presentations,
          &%{
            "type" => "bemItemPromoted",
            "turnId" => turn,
            "itemId" => backing,
            "presentation" => &1
          }
        ) ++
        [%{"type" => "realtimeSessionClosed", "outcome" => "ended"}]

    for {fact, content} <- Enum.zip(facts, contents) do
      assert_uuid(fact["id"])
      assert fact == Map.merge(content, %{"id" => fact["id"], "realtimeSessionId" => session_id})
    end

    assert params == Enum.map(facts, &%{"threadId" => thread, "item" => &1})
    facts
  end

  defp assert_history(page, sources, facts, turn) do
    assert Map.keys(page) |> Enum.sort() == [
             "activeRealtimeSessionAtPageStart",
             "data",
             "nextCursor"
           ]

    assert page["activeRealtimeSessionAtPageStart"] == nil and page["nextCursor"] == nil

    expected =
      Enum.map(facts, &%{"type" => "realtime", "item" => &1}) ++
        Enum.map(sources, &%{"type" => "item", "turnId" => turn["id"], "item" => &1}) ++
        [
          %{"type" => "turnStarted", "turnId" => turn["id"], "startedAt" => turn["startedAt"]},
          %{
            "type" => "turnCompleted",
            "turnId" => turn["id"],
            "status" => "completed",
            "error" => nil,
            "startedAt" => turn["startedAt"],
            "completedAt" => turn["completedAt"],
            "durationMs" => turn["durationMs"]
          }
        ]

    # Check every payload, including all ordinary records, without presuming
    # that streamed promotion and backing-item materialization share an ordinal.
    assert Enum.sort(Enum.map(page["data"], &Map.delete(&1, "position"))) == Enum.sort(expected)
    assert for(entry <- page["data"], entry["type"] == "item", do: entry["item"]) == sources
    assert for(entry <- page["data"], entry["type"] == "realtime", do: entry["item"]) == facts
    assert hd(page["data"])["item"] == hd(facts)
    assert List.last(page["data"])["item"] == List.last(facts)
    start_position = Enum.find(page["data"], &(&1["type"] == "turnStarted"))["position"]
    end_position = Enum.find(page["data"], &(&1["type"] == "turnCompleted"))["position"]

    for entry <- page["data"],
        entry["type"] == "item" or get_in(entry, ["item", "type"]) == "bemItemPromoted" do
      assert start_position < entry["position"] and entry["position"] < end_position
    end

    positions = Enum.map(page["data"], & &1["position"])
    assert Enum.all?(positions, &(is_integer(&1) and &1 >= 0))
    assert positions == Enum.sort(positions)
  end

  defp assert_safe(ctx, pid, scenario) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    requests = json(ctx, "requests.json")
    assert length(requests) == if(scenario == "dynamic", do: 2, else: 1)
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))

    if scenario == "dynamic" do
      assert [output] =
               Enum.filter(List.last(requests)["input"], &(&1["type"] == "function_call_output"))

      assert output["call_id"] == "owned-bem-tool-call" and output["output"] == @output
    end

    assert length(events(ctx, "realtime-journal.json", "handshake")) == 1
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
  end

  defp connect(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(pid, %{"name" => "samgita_realtime_bem", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    pid
  end

  defp control(ctx, op) do
    id = "owned-bem-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.find(events(ctx, "bem-journal.json", "control_done"), &(&1["id"] == id)) end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline, "Owned BEM native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected BEM event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline, "Owned BEM fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp notice(events, method),
    do: Enum.find_value(events, &if(&1.wire["method"] == method, do: &1.wire["params"]))

  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp state(ctx), do: json(ctx, "state.json")
  defp events(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
