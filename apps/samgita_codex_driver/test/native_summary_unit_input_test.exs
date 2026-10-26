defmodule SamgitaCodexDriver.NativeSummaryUnitInputTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @assistant Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @active Path.expand("../../../scripts/codex/active_turn_settings_fixture.py", __DIR__)
  @assistant_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @active_sha "e21d528a4cd4862e1df6c9c17c00c464b27a39e9257e2e74cda3034781a48819"
  @answer "Deterministic local fixture answer"
  @instructions "Owned fixed summary unit input fixture instructions."
  @active_instructions "Synthetic local settings fixture instructions."
  @tool %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Owned synthetic summary update barrier",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in [
           "thread/start",
           "thread/settings/update",
           "turn/start",
           "turn/settings/update"
         ] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(binary) == @binary_sha
    assert hash(@assistant) == @assistant_sha
    assert hash(@active) == @active_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-summary-unit-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    active? = tags.method == "turn/settings/update"
    script = if active?, do: @active, else: @assistant
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", script)

    fixture =
      try do
        ModelFixture.start(root, if(active?, do: "active", else: "assistant"))
      after
        restore_script(previous)
      end

    on_exit(fn -> close_provider(fixture) end)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, fixture: fixture, root: root, baseline: baseline(tags.summary)}
    catalog = configure(ctx, active?)
    config = Path.join(fixture.codex_home, "config.toml")
    originals = Enum.map([@assistant, @active, config, catalog], &{&1, File.read!(&1)})

    Map.merge(ctx, %{
      capture: start_supervised!({Agent, fn -> [] end}),
      originals: originals,
      model: if(active?, do: "step-settings-a", else: "mock-model"),
      instructions: if(active?, do: @active_instructions, else: @instructions)
    })
  end

  for method <- ["turn/start", "thread/settings/update", "turn/settings/update"],
      summary <- ~w(auto concise detailed none),
      payload <- [nil, %{}] do
    @tag method: method, summary: summary, payload: payload
    test "native #{method} summary #{summary} with #{inspect(payload)} retains its real scope",
         ctx do
      pid = start(ctx)
      native = native_process(pid)

      params = %{
        "model" => ctx.model,
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "legacy",
        "ephemeral" => false
      }

      params =
        if ctx.method == "turn/settings/update",
          do: Map.put(params, "dynamicTools", [@tool]),
          else: params

      started = request(ctx, pid, "thread/start", params)
      thread = Map.fetch!(Map.fetch!(started, "thread"), "id")
      assert is_binary(thread) and thread != ""
      assert requests(ctx) === []
      assert_idle(pid)

      rows =
        if ctx.method == "turn/settings/update",
          do: active_journey(ctx, pid, thread),
          else: thread_journey(ctx, pid, thread)

      saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
      assert saved["id"] == thread
      assert Enum.map(saved["turns"], & &1["id"]) === rows
      assert Enum.all?(saved["turns"], &(&1["status"] == "completed"))
      providers = requests(ctx)
      assert length(providers) == if(ctx.method == "turn/start", do: 4, else: 3)
      assert_retained(ctx)
      assert_idle(pid)
      assert :ok = Session.close(pid)
      assert_gone(native)
      assert_applied_history(ctx, saved["path"])
      assert requests(ctx) === providers
      assert_retained(ctx)
    end
  end

  defp configure(ctx, active?) do
    unless active? do
      TurnFixture.configure_model(ctx, %{
        "supported_reasoning_levels" => [%{"effort" => "low", "description" => "Owned low"}],
        "default_reasoning_level" => "low",
        "supports_reasoning_summary_parameter" => true,
        "default_reasoning_summary" => "auto",
        "use_responses_lite" => false,
        "model_messages" => %{"instructions_template" => @instructions}
      })
    end

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    body =
      config
      |> File.read!()
      |> String.replace(~s(approval_policy = "on-request"), ~s(approval_policy = "never"))
      |> String.replace(~s(sandbox_mode = "read-only"), ~s(sandbox_mode = "danger-full-access"))

    body =
      if active? do
        String.replace(
          body,
          ~s(model_reasoning_summary = "concise"),
          ~s(model_reasoning_summary = "#{ctx.baseline}")
        )
      else
        ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "#{ctx.baseline}"\n) <>
          body <> "\n[features]\nstep_model_switching = true\nreasoning_effort_override = false\n"
      end

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        body <>
        "\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n" <>
        "browser_use = false\ncomputer_use = false\n"
    )

    Path.join(
      ctx.fixture.codex_home,
      if(active?, do: "step-models.json", else: "turn-models.json")
    )
  end

  defp thread_journey(ctx, pid, thread) do
    first = turn(ctx, pid, thread, 1, %{}, ctx.baseline)
    assert length(requests(ctx)) == 1
    object = %{ctx.summary => ctx.payload}

    if ctx.method == "turn/start" do
      targeted = turn(ctx, pid, thread, 2, %{"summary" => object}, ctx.summary)
      followup = turn(ctx, pid, thread, 3, %{}, ctx.summary)
      null = turn(ctx, pid, thread, 4, %{"summary" => nil}, ctx.summary)
      [first, targeted, followup, null]
    else
      assert request(ctx, pid, "thread/settings/update", %{
               "threadId" => thread,
               "summary" => object
             }) === %{}

      events = collect(pid, &settings?(&1, thread, ctx.summary), [], now() + 20_000)
      assert_selected(ctx, events, thread, ctx.summary)
      assert length(requests(ctx)) == 1
      assert_idle(pid)
      followup = turn(ctx, pid, thread, 2, %{}, ctx.summary)
      null = turn(ctx, pid, thread, 3, %{"summary" => nil}, ctx.summary)
      [first, followup, null]
    end
  end

  defp turn(ctx, pid, thread, index, extra, summary) do
    params = Map.merge(%{"threadId" => thread, "input" => text(marker(index))}, extra)
    result = request(ctx, pid, "turn/start", params)
    turn = Map.fetch!(Map.fetch!(result, "turn"), "id")
    assert result["turn"]["status"] == "inProgress"
    events = collect(pid, &completed?(&1, thread, turn), [], now() + 20_000)
    assert_finished(events, thread, turn)

    if index == 2 and ctx.method == "turn/start",
      do: assert_selected(ctx, events, thread, summary)

    assert length(requests(ctx)) == index
    assert_provider(ctx, Enum.at(requests(ctx), index - 1), thread, turn, index, summary)
    assert_idle(pid)
    turn
  end

  defp active_journey(ctx, pid, thread) do
    result = request(ctx, pid, "turn/start", %{"threadId" => thread, "input" => text(marker(1))})
    turn = result["turn"]["id"]
    events = collect(pid, &(&1.kind == :server_request), [], now() + 20_000)
    assert [tool] = Enum.filter(events, &(&1.kind == :server_request))
    assert_tool(pid, thread, turn, tool)
    assert [first] = requests(ctx)
    assert_provider(ctx, first, thread, turn, 1, ctx.baseline)
    target = %{"threadId" => thread, "turnId" => turn}

    for patch <- [%{"summary" => %{ctx.summary => ctx.payload}}, %{}, %{"summary" => nil}] do
      assert request(ctx, pid, "turn/settings/update", Map.merge(target, patch)) === %{
               "status" => "applied"
             }

      assert requests(ctx) === [first]
      assert_tool(pid, thread, turn, tool)
    end

    assert :ok =
             Session.respond(pid, tool.handle, {
               :ok,
               %{
                 "contentItems" => [
                   %{"type" => "inputText", "text" => "Synthetic lookup completed"}
                 ],
                 "success" => true
               }
             })

    completed = collect(pid, &completed?(&1, thread, turn), [], now() + 20_000)
    assert_finished(events ++ completed, thread, turn)
    assert [^first, continued] = requests(ctx)
    assert_provider(ctx, continued, thread, turn, 1, ctx.summary)
    assert [output] = Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "fixture-call-1"
    assert output["output"] == "Synthetic lookup completed"
    refute Enum.any?(events ++ completed, &settings?(&1, thread, ctx.summary))

    future_result =
      request(ctx, pid, "turn/start", %{"threadId" => thread, "input" => text(marker(2))})

    future = future_result["turn"]["id"]
    future_events = collect(pid, &completed?(&1, thread, future), [], now() + 20_000)
    assert_finished(future_events, thread, future)
    assert [^first, ^continued, provider] = requests(ctx)
    assert_provider(ctx, provider, thread, future, 2, ctx.baseline)
    [turn, future]
  end

  defp assert_tool(pid, thread, turn, tool) do
    assert tool.wire["method"] == "item/tool/call"
    assert tool.handle.id === tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] === %{
             "threadId" => thread,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }

    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp assert_selected(ctx, events, thread, summary) do
    assert [settings] =
             for(
               event <- events,
               settings?(event, thread, summary),
               do: event.wire["params"]["threadSettings"]
             )

    assert Map.take(settings, ["model", "modelProvider", "effort", "summary"]) === %{
             "model" => ctx.model,
             "modelProvider" => "fixture",
             "effort" => "low",
             "summary" => summary
           }
  end

  defp assert_provider(ctx, provider, thread, turn, index, summary) do
    assert provider["model"] === ctx.model

    expected =
      if summary == "none",
        do: %{"effort" => "low"},
        else: %{"effort" => "low", "summary" => summary}

    assert Map.fetch!(provider, "reasoning") === expected
    metadata = provider["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["thread_id"] == thread and metadata["turn_id"] == turn
    assert metadata["history_initialization"] == "new"

    assert Map.delete(hd(provider["input"]), "id") === %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => ctx.instructions}]
           }

    assert Enum.count(provider["input"], fn item ->
             item["type"] == "message" and item["role"] == "user" and
               item["content"] === [%{"type" => "input_text", "text" => marker(index)}]
           end) == 1
  end

  defp assert_applied_history(ctx, path) do
    expanded = Path.expand(path)
    assert String.starts_with?(expanded, Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(expanded)
    assert size > 0 and size <= 4_194_304
    bytes = File.read!(expanded)
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048

    records =
      Enum.map(lines, fn line ->
        assert byte_size(line) <= 262_144
        JSON.decode!(line)
      end)

    snapshots =
      for %{"type" => "event_msg", "payload" => %{"type" => "thread_settings_applied"} = payload} <-
            records,
          do: payload["thread_settings"]

    expected = if ctx.method == "turn/settings/update", do: ctx.baseline, else: ctx.summary
    assert snapshots != []
    assert List.last(snapshots)["reasoning_summary"] === expected
    assert File.read!(expanded) === bytes
  end

  defp request(ctx, pid, method, params) do
    count = length(Agent.get(ctx.capture, & &1))
    id = "owned-summary-unit-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = wire} =
             Session.request(pid, method, params, id: id)

    assert wire === %{"id" => id, "result" => result}

    assert Agent.get(ctx.capture, &Enum.drop(&1, count)) === [
             %{"id" => id, "method" => method, "params" => params}
           ]

    result
  end

  defp collect(pid, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    if Enum.any?(events, predicate) do
      events
    else
      assert now() < deadline, "Native summary unit event deadline"
      assert %{phase: :ready, gap: nil} = Session.status(pid)

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native summary unit event gap")
      after
        10 -> :ok
      end

      collect(pid, predicate, events, deadline)
    end
  end

  defp settings?(event, thread, summary),
    do:
      event.wire["method"] == "thread/settings/updated" and
        event.wire["params"]["threadId"] == thread and
        event.wire["params"]["threadSettings"]["summary"] == summary

  defp completed?(event, thread, turn),
    do:
      event.wire["method"] == "turn/completed" and
        event.wire["params"]["threadId"] == thread and
        event.wire["params"]["turn"]["id"] == turn

  defp assert_finished(events, thread, turn) do
    assert [finished] = Enum.filter(events, &completed?(&1, thread, turn))
    assert finished.wire["params"]["turn"]["status"] == "completed"

    assert [answer] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["threadId"] == thread,
               event.wire["params"]["turnId"] == turn,
               event.wire["params"]["item"]["type"] == "agentMessage",
               do: event.wire["params"]["item"]
             )

    assert answer["text"] === @answer
    assert_idle_marker(events)
  end

  defp assert_idle_marker(events), do: refute(Enum.any?(events, &(&1.wire["method"] == "error")))

  defp assert_idle(pid),
    do:
      assert(
        %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
          Session.status(pid)
      )

  defp baseline("auto"), do: "concise"
  defp baseline(_summary), do: "auto"
  defp marker(index), do: "Owned summary unit input turn #{index} 163"
  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp restore_script(nil), do: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
  defp restore_script(previous), do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous)

  defp requests(ctx) do
    assert File.stat!(ctx.fixture.requests).size <= 4_194_304
    ModelFixture.requests(ctx.fixture)
  end

  defp assert_retained(ctx) do
    for {path, bytes} <- ctx.originals, do: assert(File.read!(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp native_process(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash("/proc/#{native}/exe") == @binary_sha
    native
  end

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned summary unit process #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: Path.expand(ctx.binary),
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_summary_unit_input", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
