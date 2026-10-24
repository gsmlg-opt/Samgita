defmodule SamgitaCodexDriver.NativeImagegenSuccessProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_imagegen_success_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned explicit image success turn λ"
  @prompt "Owned synthetic image success whale"
  @answer "Owned image success acknowledged"
  @call "owned-image-success-call"
  @message "owned-image-success-message"
  @access "owned-synthetic-image-access"
  @result "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="
  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
         6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192,
         240, 31, 0, 5, 0, 1, 255, 137, 153, 61, 29, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96,
         130>>
  @png_sha "4ff6ab670a58c14270e034e2090d9a432caa263a14e0a25785386b0c12f880b5"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-img-ok-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
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

      if :atomics.get(complete, 1) == 1,
        do: File.rm_rf!(root),
        else: IO.puts("Owned imagegen success evidence retained: #{root}")
    end)

    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert [provider] = events(ctx, "bem-journal.json", "image_success_provider_ready")
    assert provider["source_provider_requests"] == 0 and provider["scenario"] == tags.scenario
    assert provider["request_auth"] == "explicit_synthetic_provider_bearer"
    assert provider["local_account"] == "synthetic_chatgpt_only"
    config = File.read!(Path.join(root, "codex/config.toml"))
    lines = String.split(config, "\n")

    for line <- [
          "cli_auth_credentials_store = \"file\"",
          "experimental_bearer_token = \"#{@access}\"",
          "requires_openai_auth = true",
          "base_url = \"#{provider["api_base"]}\"",
          "openai_base_url = \"#{provider["api_base"]}\"",
          "supports_websockets = false",
          "enable_request_compression = false"
        ],
        do: assert(Enum.count(lines, &(&1 == line)) == 1)

    assert config =~ "[analytics]\nenabled = false\n"
    refute "requires_openai_auth = false" in lines
    assert Bitwise.band(File.stat!(Path.join(root, "codex/auth.json")).mode, 0o777) == 0o600
    ctx
  end

  for scenario <- ~w(opaque transparent), mode <- ~w(legacy paginated) do
    @scenario scenario
    @mode mode
    @tag scenario: scenario
    test "#{mode} requested transparent image keeps #{@scenario} result, bytes and cold history",
         ctx do
      pid = connect(ctx)

      thread =
        call(pid, "thread/start", %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => Path.join(ctx.root, "workspace"),
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "historyMode" => @mode,
          "ephemeral" => false,
          "serviceName" => "chatgpt_cca"
        })["thread"]["id"]

      assert_uuid(thread)
      saved = Path.join([ctx.root, "codex", "generated_images", thread, @call <> ".png"])
      before_turn = System.system_time(:second)

      turn =
        call(pid, "turn/start", %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => @input}]
        })["turn"]["id"]

      assert_uuid(turn)

      pending =
        collect(pid, fn batch ->
          Enum.any?(
            batch,
            &(get_in(&1.wire, ["params", "item", "type"]) == "imageGeneration" and
                &1.wire["method"] == "item/started")
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
      refute File.exists?(saved)
      control(ctx, "release200")
      execution = collect(pid, &notice(&1, "turn/completed"), pending)
      completion = notice(execution, "turn/completed")
      assert completion["threadId"] == thread
      assert completion["turn"]["id"] == turn and completion["turn"]["status"] == "completed"
      assert Map.fetch!(completion["turn"], "error") == nil
      sources = assert_sources(execution, thread, turn, @scenario == "transparent", saved)
      assert_artifact(ctx, thread, saved)

      expected_history =
        if @mode == "legacy" do
          # The pinned legacy reducer allocates IDs for UserMessage/AgentMessage
          # events; ImageGenerationEnd retains its call ID and complete payload.
          [user, image, assistant] = sources
          [%{user | "id" => "item-1"}, image, %{assistant | "id" => "item-2"}]
        else
          sources
        end

      # The barrier checks prescribed contents before snapshotting dynamic turn timestamps.
      warm_thread =
        call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

      assert [hydrated] = warm_thread["turns"]
      assert hydrated["id"] == turn and hydrated["status"] == "completed"
      assert hydrated["items"] == expected_history
      assert Map.fetch!(hydrated, "error") == nil
      assert is_integer(hydrated["startedAt"]) and hydrated["startedAt"] >= before_turn

      assert is_integer(hydrated["completedAt"]) and
               hydrated["completedAt"] >= hydrated["startedAt"]

      assert hydrated["completedAt"] <= System.system_time(:second)
      assert is_integer(hydrated["durationMs"]) and hydrated["durationMs"] >= 0
      history_path = Map.fetch!(warm_thread, "path")
      history_bytes = File.read!(history_path)
      query = %{"threadId" => thread, "limit" => 100}

      backing_query = %{
        "threadId" => thread,
        "turnId" => turn,
        "itemIds" => Enum.map(sources, & &1["id"])
      }

      paginated =
        if @mode == "paginated" do
          page = call(pid, "thread/timeline/list", query)
          assert_timeline(page, sources, hydrated)
          backing = call(pid, "thread/items/read", backing_query)
          assert Enum.map(backing["data"], & &1["item"]) == sources
          assert Enum.all?(backing["data"], &(&1["turnId"] == turn))
          {page, backing}
        end

      assert_safe(ctx, pid, turn, saved)
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

      assert [cold_turn] =
               call(cold, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
                 "thread"
               ]["turns"]

      assert cold_turn == hydrated

      if @mode == "paginated" do
        {page, backing} = paginated
        assert call(cold, "thread/timeline/list", query) == page
        assert call(cold, "thread/items/read", backing_query) == backing
      end

      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert File.read!(history_path) == history_bytes
      assert_artifact(ctx, thread, saved)
      assert_safe(ctx, cold, turn, saved)
      assert :ok = Session.close(cold)
      control(ctx, "close")
      assert length(events(ctx, "bem-journal.json", "fixture_closed")) == 1
      for native <- state(ctx)["native_pids"], do: refute(File.exists?("/proc/#{native}"))
      :atomics.put(ctx.complete, 1, 1)
    end
  end

  defp assert_sources(execution, thread, turn, transparent, saved) do
    refute Enum.any?(execution, &(&1.kind == :server_request))
    refute Enum.any?(execution, &(&1.wire["method"] in ["error", "thread/realtime/error"]))

    started =
      for event <- execution, event.wire["method"] == "item/started", do: event.wire["params"]

    completed =
      for event <- execution, event.wire["method"] == "item/completed", do: event.wire["params"]

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
             "status" => "completed",
             "revisedPrompt" => @prompt,
             "result" => @result,
             "transparentBackground" => transparent,
             "failure" => nil,
             "savedPath" => saved
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

    image_position =
      Enum.find_index(
        execution,
        &(&1.wire["method"] == "item/completed" and
            get_in(&1.wire, ["params", "item", "id"]) == @call)
      )

    turn_position = Enum.find_index(execution, &(&1.wire["method"] == "turn/completed"))

    assert is_integer(image_position) and is_integer(turn_position) and
             image_position < turn_position

    sources
  end

  defp assert_artifact(ctx, thread, saved) do
    assert File.lstat!(Path.join(ctx.root, "codex/generated_images")).type == :directory
    assert File.lstat!(Path.join(ctx.root, "codex/generated_images/#{thread}")).type == :directory
    assert File.lstat!(saved).type == :regular
    assert File.read!(saved) == @png
    assert Base.encode16(:crypto.hash(:sha256, File.read!(saved)), case: :lower) == @png_sha

    files =
      Path.wildcard(Path.join(ctx.root, "codex/generated_images/**/*"))
      |> Enum.filter(&File.regular?/1)

    assert files == [saved]
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
  end

  defp assert_timeline(page, sources, turn) do
    assert Enum.sort(Map.keys(page)) == ["activeRealtimeSessionAtPageStart", "data", "nextCursor"]

    assert Map.fetch!(page, "activeRealtimeSessionAtPageStart") == nil and
             Map.fetch!(page, "nextCursor") == nil

    expected =
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
    positions = Enum.map(page["data"], & &1["position"])

    assert Enum.all?(positions, &(is_integer(&1) and &1 >= 0)) and
             positions == Enum.sort(positions)

    start_position = Enum.find(page["data"], &(&1["type"] == "turnStarted"))["position"]
    end_position = Enum.find(page["data"], &(&1["type"] == "turnCompleted"))["position"]

    for entry <- page["data"],
        entry["type"] == "item",
        do: assert(start_position < entry["position"] and entry["position"] < end_position)
  end

  defp assert_safe(ctx, pid, turn, saved) do
    control(ctx, "barrier")

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))

    refute Enum.any?(
             remaining,
             &(&1.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed",
                 "error"
               ])
           )

    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert events(ctx, "realtime-journal.json", "handshake") == []
    assert [first, second] = json(ctx, "requests.json")
    assert first["model"] == "mock-model" and second["model"] == "mock-model"
    assert Enum.filter(first["input"], &(&1["type"] == "function_call_output")) == []
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == @call

    hint =
      "Generated images are saved to #{Path.dirname(saved)} as #{saved} by default.\nIf you need to use a generated image at another path, copy it and leave the original in place unless the user explicitly asks you to delete it.\nThe generated image is already displayed to the user. There is no need to render it in the final response as a Markdown image or file link."

    assert byte_size(hint) <= 1024

    assert output["output"] == [
             %{
               "type" => "input_image",
               "image_url" => "data:image/png;base64," <> @result,
               "detail" => "high"
             },
             %{"type" => "input_text", "text" => hint}
           ]

    developer = Enum.filter(second["input"], &(&1["role"] == "developer")) |> JSON.encode!()
    refute developer =~ "Generated images are saved to"

    assert Enum.map(events(ctx, "imagegen-http.json", "http_request"), & &1["path"]) ==
             ["/api/codex/responses", "/api/codex/images/generations", "/api/codex/responses"]

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "http_request"),
             &(&1["method"] == "POST" and &1["authorization"] == "Bearer " <> @access and
                 &1["content_encoding"] in [nil, "identity"])
           )

    allowed = [
      "/api/codex/accounts/check",
      "/api/codex/settings/user",
      "/api/codex/config/bundle"
    ]

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "startup_metadata"),
             &(&1["path"] in allowed)
           )

    assert Enum.all?(
             events(ctx, "imagegen-http.json", "success_startup_auth"),
             &(&1["path"] in allowed and &1["account"] == "owned-synthetic-image-account")
           )

    assert [request] = events(ctx, "imagegen-http.json", "image_request")

    assert request["body"] == %{
             "prompt" => @prompt,
             "background" => "transparent",
             "model" => "gpt-image-2",
             "quality" => "auto",
             "size" => "auto"
           }

    assert request["turn_id"] == turn and request["originator"] == "chatgpt_cca"
    assert [response] = events(ctx, "imagegen-http.json", "image_response")

    assert response == %{
             "event" => "image_response",
             "status" => 200,
             "headers" => %{"x-codex-imagegen-request-id" => "owned-image-success-request"},
             "body" => %{
               "created" => 1,
               "background" => ctx.scenario,
               "data" => [
                 %{"b64_json" => @result, "generation_id" => "owned-image-success-generation"},
                 %{"b64_json" => "ignored", "generation_id" => "owned-image-unused-generation"}
               ]
             }
           }

    assert Enum.map(
             events(ctx, "imagegen-http.json", "responses_response"),
             &{&1["index"], &1["status"]}
           ) == [{1, 200}, {2, 200}]
  end

  defp connect(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_imagegen_success", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp control(ctx, op) do
    id = "owned-image-success-#{System.unique_integer([:positive])}"
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
             "Owned image success native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected image success event gap")
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
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned image success fixture deadline"

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
