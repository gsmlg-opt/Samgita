defmodule SamgitaCodexDriver.NativeToolInteractionsProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_tool_interactions_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @pixel "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC"
  @audio "data:audio/wav;base64,UklGRg=="

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ["python3", "unshare", "ip"],
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-tool-interactions-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp"], do: File.mkdir_p!(Path.join(root, dir))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", ctx.binary],
        cwd: ctx.workspace,
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

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        state = state(ctx)

        for os_pid <- [state["native_pid"], state["controller_pid"], state["namespace_owner_pid"]],
            do:
              await(
                fn -> not File.exists?("/proc/#{os_pid}") end,
                "owned fixture process reaping"
              )
      end
    end)

    await(fn -> File.exists?(Path.join(root, "state.json")) end, "isolated fixture startup")
    proof = state(ctx)
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    ctx
  end

  @tag :async_messages
  test "async questions retain populated, omitted and null options without waiting for a reply",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{}, "paginated")
    turn = start_turn(pid, thread, "async-questions", "default")
    events = finish(pid, turn)

    expected = %{
      "type" => "agentMessage",
      "id" => turn.call,
      "text" =>
        "Choose owned color λ\n- Green\n- Blue\n\nProvide owned detail\n\nExplicit null detail",
      "phase" => "final_answer",
      "memoryCitation" => nil,
      "delivery" => "async",
      "questions" => [
        %{"title" => "Choose owned color λ", "options" => ["Green", "Blue"]},
        %{"title" => "Provide owned detail", "options" => nil},
        %{"title" => "Explicit null detail", "options" => nil}
      ]
    }

    assert_async_success(ctx, pid, turn, events, expected, "request_user_input_async")
  end

  @tag :async_messages
  test "async notice trims whitespace and continues the same turn without a client interaction",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{}, "paginated")
    turn = start_turn(pid, thread, "async-notice", "default")
    events = finish(pid, turn)

    expected = %{
      "type" => "agentMessage",
      "id" => turn.call,
      "text" => "Owned async notice λ",
      "phase" => "final_answer",
      "memoryCitation" => nil,
      "delivery" => "async",
      "questions" => nil
    }

    assert_async_success(ctx, pid, turn, events, expected, "send_message_to_user_async")
  end

  @tag :async_messages
  test "invalid async questions and blank notices return native errors without async items",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{}, "paginated")

    for {scenario, tool, error} <- [
          {"async-empty-questions", "request_user_input_async", "questions must not be empty"},
          {"async-blank-title", "request_user_input_async", "question titles must not be empty"},
          {"async-empty-options", "request_user_input_async",
           "options must contain at least one non-empty answer"},
          {"async-blank-option", "request_user_input_async",
           "options must contain at least one non-empty answer"},
          {"async-blank-notice", "send_message_to_user_async", "message must not be empty"}
        ] do
      before = length(requests(ctx))
      turn = start_turn(pid, thread, scenario, "default")
      events = finish(pid, turn)
      assert_async_continuation(ctx, pid, turn, events, tool, error, before)
      refute item(events, "item/started", turn.call)
      refute item(events, "item/completed", turn.call)

      refute Enum.any?(events, fn event ->
               get_in(event.wire, ["params", "item", "delivery"]) == "async"
             end)

      history = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})

      assert [%{"id" => turn_id, "status" => "completed"}] =
               Enum.filter(history["thread"]["turns"], &(&1["id"] == turn.id))

      assert turn_id == turn.id

      assert call(pid, "thread/items/read", %{
               "threadId" => thread,
               "turnId" => turn.id,
               "itemIds" => [turn.call]
             }) === %{"data" => []}

      assert length(requests(ctx)) == before + 2
    end
  end

  test "Plan input preserves multiple options and Unicode Other answers with explicit resolution",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    {turn, event, events} = pending(pid, thread, "input-multi")
    assert event.wire["method"] == "item/tool/requestUserInput"
    # Pinned Codex allocates server request IDs from AtomicI64 initialized at zero.
    assert is_integer(event.wire["id"]) and event.wire["id"] >= 0
    params = event.wire["params"]
    assert params["isBlocking"]
    assert params["autoResolutionMs"] == nil
    assert params["itemId"] == turn.call
    assert [choice, detail] = params["questions"]
    assert choice["id"] == "choice" and detail["id"] == "detail"
    assert Enum.map([choice, detail], & &1["header"]) == ["Choice", "Detail"]
    assert Enum.map(choice["options"], & &1["label"]) == ["One", "Two"]
    assert Enum.map(choice["options"], & &1["description"]) == ["Synthetic one", "Synthetic two"]
    assert Enum.map(detail["options"], & &1["label"]) == ["Red", "Blue"]
    assert choice["isOther"] and detail["isOther"] and detail["isSecret"]
    refute choice["isSecret"]

    assert params === %{
             "threadId" => thread,
             "turnId" => turn.id,
             "itemId" => turn.call,
             "isBlocking" => true,
             "autoResolutionMs" => nil,
             "questions" => [
               %{
                 "id" => "choice",
                 "header" => "Choice",
                 "question" => "Choose synthetic input",
                 "isOther" => true,
                 "isSecret" => false,
                 "options" => [
                   %{"label" => "One", "description" => "Synthetic one"},
                   %{"label" => "Two", "description" => "Synthetic two"}
                 ]
               },
               %{
                 "id" => "detail",
                 "header" => "Detail",
                 "question" => "Choose a synthetic detail",
                 "isOther" => true,
                 "isSecret" => true,
                 "options" => [
                   %{"label" => "Red", "description" => "Synthetic red"},
                   %{"label" => "Blue", "description" => "Synthetic blue"}
                 ]
               }
             ]
           }

    answers = %{
      "choice" => %{"answers" => ["One", "Two"]},
      "detail" => %{"answers" => ["自定义 λ\nline two"]}
    }

    assert :ok = Session.respond(pid, event.handle, {:ok, %{"answers" => answers}})
    events = finish(pid, turn, events)
    assert JSON.decode!(model_output(ctx, turn.call)) == %{"answers" => answers}
    assert_resolved(events, thread, event.wire["id"], turn.id)
    assert [%{handle: handle, status: :resolution_observed}] = Session.interaction_outcomes(pid)
    assert handle == event.handle
    assert Session.status(pid).interactions == 0
    assert length(requests(ctx)) == 2
  end

  test "Default input feature is nonblocking and invalid options are rejected before server requests",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{"features.default_mode_request_user_input" => true})
    {turn, event, events} = pending(pid, thread, "input-default", "default")
    refute event.wire["params"]["isBlocking"]
    assert event.wire["params"]["autoResolutionMs"] == nil
    assert Session.status(pid).interactions == 1
    assert length(requests(ctx)) == 1
    assert :ok = Session.respond(pid, event.handle, {:ok, %{"answers" => %{}}})
    events = finish(pid, turn, events)
    assert_resolved(events, thread, event.wire["id"], turn.id)
    assert JSON.decode!(model_output(ctx, turn.call)) == %{"answers" => %{}}

    disabled = thread(pid, ctx, %{"features.default_mode_request_user_input" => false})
    turn = start_turn(pid, disabled, "input-disabled", "default")
    events = finish(pid, turn)
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert model_output(ctx, turn.call) =~ "request_user_input is unavailable in Default mode"

    turn = start_turn(pid, thread, "input-empty-options")
    events = finish(pid, turn)
    refute Enum.any?(events, &(&1.kind == :server_request))

    assert model_output(ctx, turn.call) =~
             "request_user_input requires non-empty options for every question"

    assert length(requests(ctx)) == 6
  end

  test "invalid input replies keep the handle and explicit client errors return an empty answer map",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    {turn, event, events} = pending(pid, thread, "input-error")

    assert {:error, %Error{uncertain: false}} =
             Session.respond(pid, event.handle, {:ok, %{"answers" => []}})

    assert Session.status(pid).interactions == 1
    assert Session.interaction_outcomes(pid) == []
    assert length(requests(ctx)) == 1

    assert :ok =
             Session.respond(
               pid,
               event.handle,
               {:error, %{"code" => -32_000, "message" => "Synthetic user declined input"}}
             )

    events = finish(pid, turn, events)
    assert_resolved(events, thread, event.wire["id"], turn.id)
    assert JSON.decode!(model_output(ctx, turn.call)) == %{"answers" => %{}}

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, event.handle, {:ok, %{"answers" => %{}}})

    assert length(requests(ctx)) == 2
  end

  test "namespaced dynamic tools preserve nested arguments and all three native content variants",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    {turn, event, events} = pending(pid, thread, "dynamic-media")
    assert event.wire["method"] == "item/tool/call"
    assert event.wire["params"]["namespace"] == "fixture"
    assert event.wire["params"]["tool"] == "lookup"

    assert event.wire["params"]["arguments"] == %{
             "key" => "synthetic",
             "nested" => %{"null" => nil, "list" => [1, "λ", false]}
           }

    started = item(events, "item/started", turn.call)
    assert started["status"] == "inProgress"
    assert started["contentItems"] == nil and started["success"] == nil

    content = [
      text(JSON.encode!(%{"structured" => [nil, 1, "λ"]})),
      %{"type" => "inputImage", "imageUrl" => @pixel},
      %{"type" => "inputAudio", "audioUrl" => @audio}
    ]

    assert :ok =
             Session.respond(
               pid,
               event.handle,
               {:ok, %{"contentItems" => content, "success" => true}}
             )

    events = finish(pid, turn, events)
    completed = item(events, "item/completed", turn.call)
    assert completed["status"] == "completed" and completed["success"]
    assert completed["contentItems"] == content and completed["error"] == nil
    assert is_integer(completed["durationMs"]) and completed["durationMs"] >= 0

    assert model_output(ctx, turn.call) == [
             %{"type" => "input_text", "text" => hd(content)["text"]},
             %{"type" => "input_image", "image_url" => @pixel, "detail" => "high"},
             %{"type" => "input_audio", "audio_url" => @audio}
           ]

    assert [%{status: :sent_unconfirmed}] = Session.interaction_outcomes(pid)
    refute resolved?(events, event.wire["id"])
    assert length(requests(ctx)) == 2
  end

  test "dynamic failure, empty success and client RPC error have distinct native results", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)

    variants = [
      {"dynamic-false",
       {:ok, %{"success" => false, "contentItems" => [text("Synthetic failure")]}}, false,
       [text("Synthetic failure")], "Synthetic failure"},
      {"dynamic-empty", {:ok, %{"success" => true, "contentItems" => []}}, true, [], []},
      {"dynamic-error", {:error, %{"code" => -32_000, "message" => "Synthetic denial"}}, false,
       [text("dynamic tool request failed")], "dynamic tool request failed"}
    ]

    for {scenario, response, success, content, model_content} <- variants do
      {turn, event, events} = pending(pid, thread, scenario)
      assert :ok = Session.respond(pid, event.handle, response)
      events = finish(pid, turn, events)
      completed = item(events, "item/completed", turn.call)
      assert completed["success"] == success and completed["contentItems"] == content
      assert completed["status"] == if(success, do: "completed", else: "failed")
      assert completed["error"] == nil

      assert model_output(ctx, turn.call) == model_content

      assert Enum.all?(Session.interaction_outcomes(pid), &(&1.status == :sent_unconfirmed))
    end

    assert length(requests(ctx)) == 6
  end

  test "native dynamic media validation rejects remote URLs without fetching them", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    url = state(ctx)["forbidden_url"]

    for {scenario, content, message} <- [
          {"dynamic-image", %{"type" => "inputImage", "imageUrl" => url},
           "remote image URLs are not supported; use an inline data URL instead"},
          {"dynamic-audio", %{"type" => "inputAudio", "audioUrl" => url},
           "audio URLs must use an inline data URL"}
        ] do
      {turn, event, events} = pending(pid, thread, scenario)

      assert :ok =
               Session.respond(
                 pid,
                 event.handle,
                 {:ok, %{"success" => true, "contentItems" => [content]}}
               )

      events = finish(pid, turn, events)
      completed = item(events, "item/completed", turn.call)
      assert completed["status"] == "failed" and completed["success"] == false
      assert completed["contentItems"] == [text(message)]
      assert model_output(ctx, turn.call) == message
      refute File.exists?(Path.join(ctx.root, "forbidden-fetch.json"))
    end

    assert length(requests(ctx)) == 4
  end

  @tag :retirement_regression
  test "interruption retires unanswered native dynamic and user input handles without a reply",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)

    for scenario <- ["dynamic-interrupt", "input-interrupt"] do
      before = length(requests(ctx))
      {turn, event, events} = pending(pid, thread, scenario)
      assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn.id}) == %{}
      events = finish(pid, turn, events, "interrupted")

      if scenario == "input-interrupt" do
        events = collect(pid, &resolved?(&1, event.wire["id"]), events)
        assert resolved?(events, event.wire["id"])
      else
        completed = item(events, "item/completed", turn.call)
        assert completed["status"] == "failed" and completed["success"] == false
        assert completed["contentItems"] == []
        refute Map.has_key?(completed, "error")
        refute resolved?(events, event.wire["id"])
      end

      assert Session.status(pid).interactions == 0

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(
                 pid,
                 event.handle,
                 {:error, %{"code" => -32_000, "message" => "Too late"}}
               )

      assert Session.interaction_outcomes(pid) == []
      assert length(requests(ctx)) == before + 1
    end
  end

  test "explicit borrowed reconnect and resume replay retained native requests with fresh handles",
       ctx do
    pid = client(ctx)
    native = state(ctx)["native_pid"]

    for scenario <- ["dynamic-reconnect", "input-reconnect"] do
      thread = thread(pid, ctx)
      before = length(requests(ctx))
      {turn, old, _events} = pending(pid, thread, scenario)
      generation = Session.status(pid).generation
      assert :ok = Session.reconnect(pid)
      initialize(pid)
      assert Session.status(pid).generation == generation + 1

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(
                 pid,
                 old.handle,
                 {:error, %{"code" => -32_000, "message" => "Old connection"}}
               )

      assert {:ok, before_resume} = Session.drain(pid)
      refute Enum.any?(before_resume, &(&1.kind == :server_request))
      resumed = call(pid, "thread/resume", %{"threadId" => thread})["thread"]
      assert resumed["id"] == thread
      events = collect(pid, &Enum.any?(&1, fn event -> event.kind == :server_request end))
      replay = Enum.find(events, &(&1.kind == :server_request))
      assert replay.wire == old.wire
      assert replay.handle.generation == generation + 1
      refute replay.handle.reference == old.handle.reference
      assert length(requests(ctx)) == before + 1

      response =
        if scenario == "dynamic-reconnect",
          do: %{"success" => true, "contentItems" => [text("Explicit reattached response")]},
          else: %{"answers" => %{"choice" => %{"answers" => ["One"]}}}

      assert :ok = Session.respond(pid, replay.handle, {:ok, response})
      finish(pid, turn, events)
      assert length(requests(ctx)) == before + 2
      assert Session.status(pid).interactions == 0
      assert File.exists?("/proc/#{native}") and File.exists?(ctx.socket)
    end

    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}") and File.exists?(ctx.socket)
    survivor = client(ctx)
    assert is_list(call(survivor, "thread/loaded/list", %{})["data"])
  end

  defp assert_async_success(ctx, pid, turn, events, expected, tool) do
    assert_async_continuation(ctx, pid, turn, events, tool, ~s({"accepted":true}), 0)

    started = notification(events, "item/started", &(&1["item"]["id"] == turn.call))
    completed = notification(events, "item/completed", &(&1["item"]["id"] == turn.call))
    started_at = Map.fetch!(started, "startedAtMs")
    completed_at = Map.fetch!(completed, "completedAtMs")
    assert is_integer(started_at) and started_at > 0
    assert is_integer(completed_at) and completed_at >= started_at

    assert started === %{
             "threadId" => turn.thread,
             "turnId" => turn.id,
             "item" => expected,
             "startedAtMs" => started_at
           }

    assert completed === %{
             "threadId" => turn.thread,
             "turnId" => turn.id,
             "item" => expected,
             "completedAtMs" => completed_at
           }

    started_index = item_index(events, "item/started", &(&1["id"] == turn.call))
    completed_index = item_index(events, "item/completed", &(&1["id"] == turn.call))

    answer_index =
      item_index(
        events,
        "item/completed",
        &(&1["type"] == "agentMessage" and &1["text"] == "Owned interaction finished")
      )

    assert is_integer(started_index) and is_integer(completed_index) and is_integer(answer_index)
    assert started_index < completed_index and completed_index < answer_index

    # Full history supplies only the producer/store barrier. The selective
    # expectation uses independent semantic literals, never the history payload.
    history = call(pid, "thread/read", %{"threadId" => turn.thread, "includeTurns" => true})

    assert [%{"id" => turn_id, "status" => "completed"}] =
             history["thread"]["turns"]

    assert turn_id == turn.id
    provider_requests = requests(ctx)

    assert call(pid, "thread/items/read", %{
             "threadId" => turn.thread,
             "turnId" => turn.id,
             "itemIds" => [turn.call]
           }) === %{
             "data" => [
               %{
                 "turnId" => turn.id,
                 "item" => expected,
                 "startedAtMs" => started_at,
                 "completedAtMs" => completed_at
               }
             ]
           }

    assert requests(ctx) === provider_requests
    assert Session.status(pid).interactions == 0
    assert Session.interaction_outcomes(pid) == []
  end

  defp item_index(events, method, predicate) do
    Enum.find_index(events, fn event ->
      event.wire["method"] == method and predicate.(event.wire["params"]["item"])
    end)
  end

  defp assert_async_continuation(ctx, pid, turn, events, tool, output, before) do
    refute Enum.any?(events, &(&1.kind == :server_request))
    assert Session.status(pid).interactions == 0
    assert Session.interaction_outcomes(pid) == []
    assert model_output(ctx, turn.call) === output
    assert length(requests(ctx)) == before + 2
    assert [first, continued] = Enum.drop(requests(ctx), before)
    assert tool in advertised_tools(first["tools"])

    assert [result] =
             Enum.filter(continued["input"], fn item ->
               item["type"] == "function_call_output" and item["call_id"] == turn.call
             end)

    assert result["output"] === output

    assert [answer] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               item = event.wire["params"]["item"],
               item["type"] == "agentMessage" and item["id"] != turn.call,
               do: item
             )

    assert answer["text"] == "Owned interaction finished"
    refute answer["delivery"] == "async"
  end

  defp advertised_tools(tools) do
    Enum.flat_map(tools, fn tool ->
      case tool["type"] do
        "function" -> [tool["name"]]
        "namespace" -> advertised_tools(tool["tools"])
        _ -> []
      end
    end)
  end

  defp client(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    initialize(pid)
    pid
  end

  defp initialize(pid),
    do:
      assert(
        {:ok, _} =
          Session.initialize(
            pid,
            %{"name" => "samgita_tool_interactions", "version" => "0.1.0"},
            %{"experimentalApi" => true}
          )
      )

  defp thread(pid, ctx, config \\ %{}, history_mode \\ "legacy") do
    call(pid, "thread/start", %{
      "cwd" => ctx.workspace,
      "historyMode" => history_mode,
      "config" => config,
      "dynamicTools" => [
        %{
          "type" => "namespace",
          "name" => "fixture",
          "description" => "Synthetic client tools",
          "tools" => [
            %{
              "type" => "function",
              "name" => "lookup",
              "description" => "Synthetic lookup",
              "inputSchema" => %{
                "type" => "object",
                "properties" => %{
                  "key" => %{"type" => "string"},
                  "nested" => %{"type" => "object"}
                },
                "required" => ["key", "nested"],
                "additionalProperties" => false
              }
            }
          ]
        }
      ]
    })["thread"]["id"]
  end

  defp start_turn(pid, thread, scenario, mode \\ "plan") do
    marker = "synthetic:#{scenario}:#{System.unique_integer([:positive])}"

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}],
        "collaborationMode" => %{
          "mode" => mode,
          "settings" => %{
            "model" => "mock-model",
            "reasoning_effort" => "medium",
            "developer_instructions" => nil
          }
        }
      })["turn"]["id"]

    %{id: turn, call: marker, thread: thread}
  end

  defp pending(pid, thread, scenario, mode \\ "plan") do
    turn = start_turn(pid, thread, scenario, mode)
    events = collect(pid, &Enum.any?(&1, fn event -> event.kind == :server_request end))
    event = Enum.find(events, &(&1.kind == :server_request))
    assert event.wire["params"]["threadId"] == thread
    assert event.wire["params"]["turnId"] == turn.id
    {turn, event, events}
  end

  defp finish(pid, turn, events \\ [], status \\ "completed") do
    events =
      collect(
        pid,
        &notification(&1, "turn/completed", fn params -> params["turn"]["id"] == turn.id end),
        events
      )

    completed = notification(events, "turn/completed", &(&1["turn"]["id"] == turn.id))
    assert completed["threadId"] == turn.thread and completed["turn"]["status"] == status
    events
  end

  defp assert_resolved(events, thread, request_id, turn) do
    resolved =
      Enum.find_index(
        events,
        &(&1.wire["method"] == "serverRequest/resolved" and
            &1.wire["params"]["requestId"] == request_id and
            &1.wire["params"]["threadId"] == thread)
      )

    completed =
      Enum.find_index(
        events,
        &(&1.wire["method"] == "turn/completed" and &1.wire["params"]["turn"]["id"] == turn)
      )

    assert is_integer(resolved) and is_integer(completed) and resolved < completed
  end

  defp resolved?(events, request_id),
    do: notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

  defp text(value), do: %{"type" => "inputText", "text" => value}
  defp requests(ctx), do: ctx.root |> Path.join("requests.json") |> File.read!() |> JSON.decode!()
  defp state(ctx), do: ctx.root |> Path.join("state.json") |> File.read!() |> JSON.decode!()

  defp model_output(ctx, call_id) do
    requests(ctx)
    |> Enum.flat_map(& &1["input"])
    |> Enum.find_value(fn
      %{"type" => "function_call_output", "call_id" => ^call_id, "output" => output} -> output
      _ -> nil
    end)
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp item(events, method, id) do
    case notification(events, method, &(&1["item"]["id"] == id)) do
      nil -> nil
      params -> params["item"]
    end
  end

  defp notification(events, method, predicate),
    do:
      Enum.find_value(events, fn event ->
        if event.wire["method"] == method and predicate.(event.wire["params"]),
          do: event.wire["params"]
      end)

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || now() + 5_000
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    if predicate.(acc) do
      acc
    else
      assert Session.status(pid).phase == :ready, "native Session disconnected"

      assert now() < deadline,
             "native interaction observable barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, message, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, message

      receive do
      after
        10 -> :ok
      end

      await(predicate, message, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
