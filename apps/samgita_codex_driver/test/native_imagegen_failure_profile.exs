defmodule SamgitaCodexDriver.NativeImagegenFailureProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_imagegen_failure_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned explicit image quota turn λ"
  @prompt "Owned synthetic blue whale"
  @answer "Owned image quota result acknowledged"
  @call "owned-image-limit-call"
  @message "owned-image-limit-message"
  @access "owned-synthetic-image-access"
  @reset 1_786_150_800

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-imagegen-failure-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))
    complete = :atomics.new(1, [])

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
      scenario: tags.scenario,
      complete: complete
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

      if :atomics.get(complete, 1) == 1 do
        File.rm_rf!(root)
      else
        IO.puts("Owned imagegen failure evidence retained: #{root}")
      end
    end)

    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert [provider] = events(ctx, "bem-journal.json", "image_provider_ready")
    assert provider["source_provider_requests"] == 0 and provider["scenario"] == tags.scenario
    assert provider["request_auth"] == "explicit_synthetic_provider_bearer"
    assert provider["local_account"] == "synthetic_chatgpt_only"
    config = File.read!(Path.join(root, "codex/config.toml")) |> String.split("\n")
    assert Enum.count(config, &(&1 == "cli_auth_credentials_store = \"file\"")) == 1
    assert Enum.count(config, &(&1 == "experimental_bearer_token = \"#{@access}\"")) == 1
    assert Enum.count(config, &(&1 == "requires_openai_auth = true")) == 1
    assert Enum.count(config, &(&1 == "base_url = \"#{provider["api_base"]}\"")) == 1
    assert Enum.count(config, &(&1 == "openai_base_url = \"#{provider["api_base"]}\"")) == 1
    assert Enum.count(config, &(&1 == "supports_websockets = false")) == 1
    assert Enum.count(config, &(&1 == "enable_request_compression = false")) == 1
    assert File.read!(Path.join(root, "codex/config.toml")) =~ "[analytics]\nenabled = false\n"
    refute Enum.any?(config, &(&1 == "requires_openai_auth = false"))
    assert Bitwise.band(File.stat!(Path.join(root, "codex/auth.json")).mode, 0o777) == 0o600
    ctx
  end

  for scenario <- ~w(reset no_reset) do
    @scenario scenario
    @tag scenario: scenario
    test "native image quota #{@scenario} keeps complete failure and one image promotion after restart",
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
          "ephemeral" => false
        })["thread"]["id"]

      session_id = "owned-image-quota-#{@scenario}"

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

      pending =
        collect(pid, fn events ->
          Enum.any?(
            events,
            &(get_in(&1.wire, ["params", "item", "type"]) == "imageGeneration" and
                &1.wire["method"] == "item/started")
          ) and
            Enum.any?(
              events,
              &(get_in(&1.wire, ["params", "item", "type"]) == "bemItemPromoted" and
                  &1.wire["method"] == "thread/realtime/item/completed")
            )
        end)

      refute notice(pending, "turn/completed")

      refute Enum.any?(
               pending,
               &(get_in(&1.wire, ["params", "item", "type"]) == "imageGeneration" and
                   &1.wire["method"] == "item/completed")
             )

      await(fn -> length(events(ctx, "imagegen-http.json", "image_request")) == 1 end)
      assert events(ctx, "imagegen-http.json", "image_response") == []
      control(ctx, "release429")
      execution = collect(pid, &notice(&1, "turn/completed"), pending)
      assert notice(execution, "turn/completed")["threadId"] == thread
      completion = notice(execution, "turn/completed")["turn"]
      assert completion["id"] == turn and completion["status"] == "completed"
      assert completion["error"] == nil

      assert call(pid, "thread/realtime/stop", %{"threadId" => thread}) == %{}
      closing = collect(pid, &notice(&1, "thread/realtime/closed"))

      assert notice(closing, "thread/realtime/closed") == %{
               "threadId" => thread,
               "reason" => "requested"
             }

      all = started ++ execution ++ closing
      refute Enum.any?(all, &(&1.kind == :server_request))
      refute Enum.any?(all, &(&1.wire["method"] in ["error", "thread/realtime/error"]))
      sources = assert_sources(execution, thread, turn, @scenario)
      facts = assert_facts(all, thread, turn, session_id)

      # Native producer/store flush barrier; expected item payloads are prescribed
      # above, never learned from a polling baseline.
      assert [hydrated] =
               call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"][
                 "turns"
               ]

      assert hydrated["id"] == turn and hydrated["status"] == "completed"
      assert hydrated["items"] == sources and hydrated["error"] == nil
      assert is_integer(hydrated["startedAt"]) and hydrated["startedAt"] >= before_turn

      assert is_integer(hydrated["completedAt"]) and
               hydrated["completedAt"] >= hydrated["startedAt"]

      assert hydrated["completedAt"] <= System.system_time(:second)
      assert is_integer(hydrated["durationMs"]) and hydrated["durationMs"] >= 0

      query = %{"threadId" => thread, "limit" => 100}
      warm = call(pid, "thread/timeline/list", query)
      assert_history(warm, sources, facts, hydrated)

      backing_query = %{
        "threadId" => thread,
        "turnId" => turn,
        "itemIds" => Enum.map(sources, & &1["id"])
      }

      backing = call(pid, "thread/items/read", backing_query)
      assert Enum.map(backing["data"], & &1["item"]) == sources
      assert Enum.all?(backing["data"], &(&1["turnId"] == turn))
      assert_safe(ctx, pid)
      await(fn -> events(ctx, "realtime-journal.json", "peer_closed") != [] end)

      old_instance = Session.status(pid).instance_id
      old_native = state(ctx)["native_pid"]
      assert :ok = Session.close(pid)
      assert File.exists?("/proc/#{old_native}")
      control(ctx, "restart")
      refute File.exists?("/proc/#{old_native}")
      assert state(ctx)["native_pid"] != old_native
      cold = connect(ctx)
      assert Session.status(cold).instance_id != old_instance
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert call(cold, "thread/timeline/list", query) == warm
      assert call(cold, "thread/items/read", backing_query) == backing
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_safe(ctx, cold)
      assert :ok = Session.close(cold)
      control(ctx, "close")
      assert length(events(ctx, "bem-journal.json", "fixture_closed")) == 1
      for native <- state(ctx)["native_pids"], do: refute(File.exists?("/proc/#{native}"))
      :atomics.put(ctx.complete, 1, 1)
    end
  end

  defp assert_sources(events, thread, turn, scenario) do
    started =
      for event <- events, event.wire["method"] == "item/started", do: event.wire["params"]

    completed =
      for event <- events, event.wire["method"] == "item/completed", do: event.wire["params"]

    assert Enum.all?(started ++ completed, &(&1["threadId"] == thread and &1["turnId"] == turn))
    assert [image_start] = Enum.filter(started, &(&1["item"]["type"] == "imageGeneration"))

    assert image_start["item"] == %{
             "type" => "imageGeneration",
             "id" => @call,
             "status" => "in_progress",
             "revisedPrompt" => nil,
             "result" => "",
             "transparentBackground" => nil,
             "failure" => nil
           }

    sources = Enum.map(completed, & &1["item"])
    assert Enum.map(sources, & &1["type"]) == ["userMessage", "imageGeneration", "agentMessage"]
    [user, image, assistant] = sources
    assert_uuid(user["id"])

    assert user == %{
             "type" => "userMessage",
             "id" => user["id"],
             "clientId" => nil,
             "content" => [%{"type" => "text", "text" => @input, "text_elements" => []}]
           }

    assert image == %{
             "type" => "imageGeneration",
             "id" => @call,
             "status" => "failed",
             "revisedPrompt" => @prompt,
             "result" => "",
             "transparentBackground" => nil,
             "failure" => %{
               "type" => "usageLimitExceeded",
               "limitId" => "image_gen",
               "resetsAt" => if(scenario == "reset", do: @reset, else: nil)
             }
           }

    assert assistant == %{
             "type" => "agentMessage",
             "id" => @message,
             "text" => @answer,
             "phase" => nil,
             "memoryCitation" => nil,
             "delivery" => nil,
             "questions" => nil
           }

    sources
  end

  defp assert_facts(events, thread, turn, session_id) do
    params =
      for event <- events,
          event.wire["method"] == "thread/realtime/item/completed",
          do: event.wire["params"]

    facts = Enum.map(params, & &1["item"])
    assert length(facts) == 3
    assert length(Enum.uniq_by(facts, & &1["id"])) == 3

    expected = [
      %{"type" => "realtimeSessionStarted"},
      %{
        "type" => "bemItemPromoted",
        "turnId" => turn,
        "itemId" => @call,
        "presentation" => %{"type" => "wholeItem"}
      },
      %{"type" => "realtimeSessionClosed", "outcome" => "ended"}
    ]

    for {fact, content} <- Enum.zip(facts, expected) do
      assert_uuid(fact["id"])
      assert fact == Map.merge(content, %{"id" => fact["id"], "realtimeSessionId" => session_id})
    end

    assert params == Enum.map(facts, &%{"threadId" => thread, "item" => &1})
    facts
  end

  defp assert_history(page, sources, facts, turn) do
    assert Enum.sort(Map.keys(page)) == ["activeRealtimeSessionAtPageStart", "data", "nextCursor"]
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

  defp assert_safe(ctx, pid) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert [first, second] = json(ctx, "requests.json")
    assert first["model"] == "mock-model" and second["model"] == "mock-model"
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == @call
    assert JSON.encode!(output["output"]) =~ "image generation failed:"

    assert Enum.map(events(ctx, "imagegen-http.json", "http_request"), & &1["path"]) ==
             ["/api/codex/responses", "/api/codex/images/generations", "/api/codex/responses"]

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "http_request"),
             &(&1["method"] == "POST" and &1["authorization"] == "Bearer " <> @access)
           )

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "http_request"),
             &(&1["content_encoding"] in [nil, "identity"])
           )

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "startup_metadata"),
             &(&1["path"] in [
                 "/api/codex/accounts/check",
                 "/api/codex/settings/user",
                 "/api/codex/config/bundle"
               ])
           )

    assert [request] = events(ctx, "imagegen-http.json", "image_request")

    assert request["body"] == %{
             "prompt" => @prompt,
             "background" => "opaque",
             "model" => "gpt-image-2",
             "quality" => "auto",
             "size" => "auto"
           }

    assert [response] = events(ctx, "imagegen-http.json", "image_response")
    assert response["status"] == 429

    expected_headers = %{
      "x-codex-active-limit" => "image_gen",
      "x-image-gen-primary-used-percent" => "100",
      "x-image-gen-primary-window-minutes" => "1440"
    }

    expected_error = %{
      "type" => "usage_limit_reached",
      "message" => "Owned synthetic image limit reached",
      "plan_type" => "plus"
    }

    {headers, error} =
      if ctx.scenario == "reset",
        do:
          {Map.put(expected_headers, "x-image-gen-primary-reset-at", Integer.to_string(@reset)),
           Map.put(expected_error, "resets_at", @reset)},
        else: {expected_headers, expected_error}

    assert response["headers"] == headers and response["body"] == %{"error" => error}

    assert Enum.map(
             events(ctx, "imagegen-http.json", "responses_response"),
             &{&1["index"], &1["status"]}
           ) == [{1, 200}, {2, 200}]

    assert [handshake] = events(ctx, "realtime-journal.json", "handshake")
    assert handshake["authorization"] == "Bearer " <> @access
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
  end

  defp connect(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_imagegen_failure", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp control(ctx, op) do
    id = "owned-imagegen-#{System.unique_integer([:positive])}"
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
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned imagegen native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected imagegen event gap")
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
        assert System.monotonic_time(:millisecond) < deadline, "Owned imagegen fixture deadline"

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
