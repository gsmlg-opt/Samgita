defmodule SamgitaCodexDriver.NativeTurnSharedReasoningValuesTest do
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
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @instructions "Owned fixed ordinary reasoning value fixture instructions."
  @mode_instructions "Owned ordinary collaboration instructions for null effort 163."
  @answer "Deterministic local fixture answer"
  @metadata "internal_chat_message_metadata_passthrough"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

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

      if wire["method"] in ["thread/start", "turn/start"] do
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
    assert hash(@script) == @script_sha
    ctx = fixture_context(binary, tags.profile)

    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Owned default low"},
        %{"effort" => "high", "description" => "Owned selected high"}
      ],
      "default_reasoning_level" => "low",
      "supports_reasoning_summary_parameter" => true,
      "default_reasoning_summary" => "auto",
      "use_responses_lite" => false,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")
    fixed = File.read!(config)

    fixed =
      String.replace(fixed, ~s(approval_policy = "on-request"), ~s(approval_policy = "never"))

    fixed =
      String.replace(
        fixed,
        ~s(sandbox_mode = "read-only"),
        ~s(sandbox_mode = "danger-full-access")
      )

    File.write!(
      config,
      ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "auto"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        fixed <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\n" <>
        "shell_snapshot = false\nbrowser_use = false\ncomputer_use = false\n" <>
        "reasoning_effort_override = false\n"
    )

    originals =
      Enum.map(
        [@script, config, Path.join(ctx.fixture.codex_home, "turn-models.json")],
        &{&1, File.read!(&1)}
      )

    Map.merge(ctx, %{originals: originals, capture: start_supervised!({Agent, fn -> [] end})})
  end

  for profile <- [:concise, :null_effort] do
    @tag profile: profile
    test "direct native #{profile} selection governs this turn and an omitted followup", ctx do
      pid = start(ctx)
      native = native_process(pid)
      assert File.ls!(ctx.fixture.workspace) === []

      started =
        request(ctx, pid, "thread/start", %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.fixture.workspace,
          "historyMode" => "legacy",
          "ephemeral" => false
        })

      assert Map.fetch!(started, "reasoningEffort") === "low"
      thread = Map.fetch!(Map.fetch!(started, "thread"), "id")
      assert is_binary(thread) and thread != ""
      assert requests(ctx) === []

      rows =
        Enum.map(1..3, fn index ->
          row = run_turn(ctx, pid, thread, index)
          assert length(requests(ctx)) == index
          row
        end)

      assert [baseline, targeted, followup] = rows
      assert baseline.id != targeted.id and targeted.id != followup.id
      assert length(Enum.uniq(Enum.map(rows, & &1.id))) == 3
      saved = read_thread(pid, thread)
      assert saved["id"] == thread
      assert_ui_history(saved, rows)
      path = Map.fetch!(saved, "path")
      providers = requests(ctx)
      assert length(providers) == 3
      assert_idle(pid)
      assert_retained(ctx)
      assert :ok = Session.close(pid)
      assert_gone(native)

      # Bind full outbound ordinary history to native-created raw maps, read
      # only after the actual source process has completely closed/reaped.
      {bytes, history} = raw_history(ctx, path, rows)
      assert_provider_histories(providers, history)
      assert File.read!(path) === bytes
      assert requests(ctx) === providers
      assert_retained(ctx)
      assert captured_methods(ctx) === ["thread/start", "turn/start", "turn/start", "turn/start"]
    end
  end

  defp fixture_context(binary, profile) do
    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-turn-shared-reasoning-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        restore_script(previous)
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    %{binary: binary, fixture: fixture, root: root, profile: profile}
  end

  defp restore_script(nil), do: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
  defp restore_script(previous), do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous)

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp run_turn(ctx, pid, thread, index) do
    params =
      Map.merge(
        %{"threadId" => thread, "input" => text(marker(ctx, index))},
        overrides(ctx, index)
      )

    assert_target_wire(ctx, index, params)
    began = System.system_time(:microsecond) / 1_000_000
    response = request(ctx, pid, "turn/start", params)
    turn = Map.fetch!(Map.fetch!(response, "turn"), "id")
    assert is_binary(turn) and turn != ""
    assert response["turn"]["status"] == "inProgress"
    events = collect(pid, thread, turn, [], now() + 20_000)
    ended = System.system_time(:microsecond) / 1_000_000
    assert_completed(events, thread, turn)
    assert_answer(events, thread, turn)
    assert_selected(ctx, index, events, thread)
    assert_no_dispatch(events)
    assert_idle(pid)
    assert length(requests(ctx)) == index
    assert_provider(ctx, Enum.at(requests(ctx), index - 1), thread, turn, index)
    assert_retained(ctx)
    %{id: turn, marker: marker(ctx, index), began: began, ended: ended}
  end

  defp overrides(%{profile: :concise}, 2), do: %{"summary" => "concise"}
  defp overrides(%{profile: :null_effort}, 1), do: %{"collaborationMode" => mode("high")}
  defp overrides(%{profile: :null_effort}, 2), do: %{"collaborationMode" => mode(nil)}
  defp overrides(_ctx, _index), do: %{}

  defp mode(effort),
    do: %{
      "mode" => "default",
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => effort,
        "developer_instructions" => @mode_instructions
      }
    }

  defp marker(ctx, index), do: "Owned direct #{ctx.profile} reasoning value turn #{index} 163"
  defp text(value), do: [%{"type" => "text", "text" => value, "text_elements" => []}]

  defp assert_target_wire(%{profile: :concise}, 2, params),
    do: assert(Map.fetch!(params, "summary") === "concise")

  defp assert_target_wire(%{profile: :null_effort}, 2, params) do
    settings = Map.fetch!(Map.fetch!(params, "collaborationMode"), "settings")
    assert Map.has_key?(settings, "reasoning_effort")
    assert Map.fetch!(settings, "reasoning_effort") === nil

    assert settings === %{
             "model" => "mock-model",
             "reasoning_effort" => nil,
             "developer_instructions" => @mode_instructions
           }
  end

  defp assert_target_wire(_ctx, 3, params) do
    refute Map.has_key?(params, "summary")
    refute Map.has_key?(params, "effort")
    refute Map.has_key?(params, "collaborationMode")
  end

  defp assert_target_wire(_ctx, _index, _params), do: :ok

  defp request(ctx, pid, method, params) do
    before_count = length(Agent.get(ctx.capture, & &1))
    id = "owned-shared-reasoning-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result} = wire} =
             Session.request(pid, method, params, id: id)

    assert wire === %{"id" => id, "result" => result}
    assert [captured] = Agent.get(ctx.capture, &Enum.drop(&1, before_count))
    assert captured === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp assert_selected(%{profile: :concise}, 1, _events, _thread), do: :ok
  defp assert_selected(_ctx, 3, _events, _thread), do: :ok

  defp assert_selected(ctx, index, events, thread) do
    assert [settings] =
             events
             |> Enum.filter(&(&1.wire["method"] == "thread/settings/updated"))
             |> Enum.map(& &1.wire["params"])
             |> Enum.filter(&(&1["threadId"] == thread))
             |> Enum.map(&Map.fetch!(&1, "threadSettings"))

    assert Map.take(settings, ["model", "modelProvider", "effort", "summary"]) === %{
             "model" => "mock-model",
             "modelProvider" => "fixture",
             "effort" => selected_effort(ctx, index),
             "summary" => summary(ctx, index)
           }

    assert_selected_mode(ctx, index, settings)
  end

  defp assert_selected_mode(%{profile: :concise}, _index, _settings), do: :ok

  defp assert_selected_mode(ctx, index, settings),
    do: assert(Map.fetch!(settings, "collaborationMode") === mode(selected_effort(ctx, index)))

  defp selected_effort(%{profile: :null_effort}, 1), do: "high"
  defp selected_effort(%{profile: :null_effort}, _index), do: nil
  defp selected_effort(_ctx, _index), do: "low"
  defp summary(%{profile: :concise}, index) when index > 1, do: "concise"
  defp summary(_ctx, _index), do: "auto"
  defp effective_effort(%{profile: :null_effort}, 1), do: "high"
  defp effective_effort(_ctx, _index), do: "low"

  defp assert_provider(ctx, provider, thread, turn, index) do
    assert Map.fetch!(provider, "model") == "mock-model"

    assert Map.fetch!(provider, "reasoning") === %{
             "effort" => effective_effort(ctx, index),
             "summary" => summary(ctx, index)
           }

    metadata = provider["client_metadata"]["x-codex-turn-metadata"] |> JSON.decode!()
    assert metadata["thread_id"] == thread
    assert metadata["turn_id"] == turn
    assert metadata["history_initialization"] == "new"

    assert Map.delete(hd(provider["input"]), "id") === %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           }

    assert Enum.count(provider["input"], &own_user?(&1, marker(ctx, index))) == 1
    assert_no_provider_tools(provider)
  end

  defp assert_no_provider_tools(provider) do
    refute Enum.any?(provider["input"], fn item ->
             item["type"] in [
               "function_call",
               "function_call_output",
               "custom_tool_call",
               "custom_tool_call_output",
               "tool_search_call",
               "tool_search_output"
             ]
           end)
  end

  defp own_user?(item, marker),
    do:
      item["type"] == "message" and item["role"] == "user" and
        item["content"] === [%{"type" => "input_text", "text" => marker}]

  defp assert_ui_history(saved, rows) do
    turns = Map.fetch!(saved, "turns")
    assert Enum.map(turns, & &1["id"]) === Enum.map(rows, & &1.id)
    for {turn, row} <- Enum.zip(turns, rows), do: assert_ui_turn(turn, row)
  end

  defp assert_ui_turn(turn, row) do
    assert turn["status"] == "completed"

    assert [%{"type" => "userMessage"} = user, %{"type" => "agentMessage"} = assistant] =
             turn["items"]

    assert user["content"] === text(row.marker)
    assert assistant["text"] === @answer
    assert is_binary(user["id"]) and is_binary(assistant["id"])
  end

  defp raw_history(ctx, path, rows) do
    expanded = Path.expand(path)
    assert String.starts_with?(expanded, Path.expand(ctx.fixture.codex_home) <> "/")
    assert %{type: :regular, size: size} = File.stat!(expanded)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(expanded)
    assert byte_size(bytes) == size
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048
    records = Enum.map(lines, &decode_row/1)
    refute Enum.any?(records, &(&1["type"] == "compacted"))
    payloads = for %{"type" => "response_item", "payload" => item} <- records, do: item
    history = Enum.flat_map(Enum.with_index(rows, 1), &raw_turn(payloads, &1))
    ids = Enum.map(history, & &1["id"])
    assert length(Enum.uniq(ids)) == 6
    assert Enum.filter(payloads, &(&1["id"] in ids)) === history
    {bytes, history}
  end

  defp decode_row(line) do
    assert byte_size(line) <= @max_line_bytes
    JSON.decode!(line)
  end

  defp raw_turn(payloads, {row, index}) do
    assert [user] = Enum.filter(payloads, &own_user?(&1, row.marker))
    assert [assistant] = Enum.filter(payloads, &(&1["id"] == "fixture-message-#{index}"))
    assert_raw_user(user, row)
    assert_raw_assistant(assistant, row, index)
    [user, assistant]
  end

  defp assert_raw_user(user, row) do
    id = Map.fetch!(user, "id")
    assert is_binary(id) and String.starts_with?(id, "msg_") and byte_size(id) > 4
    created = user[@metadata]["create_time"]
    assert_time(created, row)

    assert user === %{
             "type" => "message",
             "id" => id,
             "role" => "user",
             "content" => [%{"type" => "input_text", "text" => row.marker}],
             @metadata => %{
               "turn_id" => row.id,
               "create_time" => created,
               "content_item_kinds" => ["user.text"]
             }
           }
  end

  defp assert_time(created, row),
    do:
      assert(is_number(created) and created > 0 and created >= row.began and created <= row.ended)

  defp assert_raw_assistant(assistant, row, index) do
    assert assistant === %{
             "type" => "message",
             "id" => "fixture-message-#{index}",
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @answer}],
             @metadata => %{"turn_id" => row.id, "content_item_kinds" => ["unknown"]}
           }
  end

  defp assert_provider_histories(providers, history) do
    for {provider, index} <- Enum.with_index(providers, 1) do
      expected = history |> Enum.take(2 * index - 1) |> Enum.map(&provider_copy/1)
      users = for %{"role" => "user", "content" => content} <- expected, do: content
      selected = Enum.filter(provider["input"], &ordinary_item?(&1, users))
      assert selected === expected
    end
  end

  defp ordinary_item?(%{"type" => "message", "role" => "assistant"}, _users), do: true

  defp ordinary_item?(%{"type" => "message", "role" => "user"} = item, users),
    do: item["content"] in users

  defp ordinary_item?(_item, _users), do: false

  defp provider_copy(item) do
    # Native source metadata is durable; the custom-provider copy strips it.
    # Current is_prefixed uses underscore/nonempty halves. fixture-message-*
    # lacks an underscore, so its original ID is retained only in persistence.
    copy = Map.delete(item, @metadata)
    if prefixed_id?(item["id"]), do: copy, else: Map.delete(copy, "id")
  end

  defp prefixed_id?(id) do
    case String.split(id, "_", parts: 2) do
      [prefix, suffix] -> prefix != "" and suffix != ""
      _ -> false
    end
  end

  defp collect(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    if completed_turns(events, thread, turn) != [] do
      events
    else
      wait_events(pid, deadline)
      collect(pid, thread, turn, events, deadline)
    end
  end

  defp wait_events(pid, deadline) do
    assert now() < deadline, "Direct reasoning value turn deadline"
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, :events_available} -> :ok
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected direct reasoning value event gap")
    after
      10 -> :ok
    end
  end

  defp completed_turns(events, thread, turn) do
    events
    |> Enum.filter(&(&1.wire["method"] == "turn/completed"))
    |> Enum.map(& &1.wire["params"])
    |> Enum.filter(&(&1["threadId"] == thread and &1["turn"]["id"] == turn))
  end

  defp assert_completed(events, thread, turn) do
    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             completed_turns(events, thread, turn)
  end

  defp assert_answer(events, thread, turn) do
    answers =
      events
      |> Enum.filter(&(&1.wire["method"] == "item/completed"))
      |> Enum.map(& &1.wire["params"])
      |> Enum.filter(&answer_item?(&1, thread, turn))

    assert [
             %{
               "threadId" => ^thread,
               "turnId" => ^turn,
               "item" => %{"type" => "agentMessage", "text" => @answer}
             }
           ] = answers
  end

  defp answer_item?(params, thread, turn),
    do:
      params["threadId"] == thread and params["turnId"] == turn and
        params["item"]["type"] == "agentMessage"

  defp assert_no_dispatch(events),
    do: refute(Enum.any?(events, &(&1.kind == :server_request)))

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
  end

  defp requests(ctx) do
    assert File.stat!(ctx.fixture.requests).size <= @max_file_bytes
    ModelFixture.requests(ctx.fixture)
  end

  defp captured_methods(ctx),
    do: Agent.get(ctx.capture, &Enum.map(&1, fn wire -> wire["method"] end))

  defp read_thread(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

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

  defp hash(path), do: Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)

  defp assert_gone(native, remaining \\ 100) do
    if File.exists?("/proc/#{native}") do
      assert remaining > 0, "Owned direct reasoning process #{native} survived cleanup"
      Process.sleep(10)
      assert_gone(native, remaining - 1)
    else
      :ok
    end
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
               %{"name" => "samgita_turn_shared_reasoning_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
