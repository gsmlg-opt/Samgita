defmodule SamgitaCodexDriver.NativeMediumConfigEffectsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @instructions "Owned ordinary medium configuration effect fixture instructions."
  @answer "Deterministic local fixture answer"
  @captured ~w(config/read thread/start turn/start)

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      transport_opts = Keyword.delete(opts, :capture)

      with {:ok, state} <- Stdio.open(transport_opts),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ~w(config/read thread/start turn/start) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 24 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [{encoded, wire}]))
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

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-medium-config-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    capture = start_supervised!({Agent, fn -> [] end})
    base = %{binary: binary, capture: capture, setting: tags.setting}
    control = fixture(base, Path.join(root, "control"), :control)
    selected = fixture(base, Path.join(root, "selected"), :medium)

    %{
      control: control,
      selected: selected,
      capture: capture,
      setting: tags.setting,
      inputs: Map.merge(control.inputs, selected.inputs)
    }
  end

  @tag setting: :verbosity
  test "native medium verbosity overrides a distinct catalog default and survives cold startup",
       ctx do
    exercise(ctx)
  end

  @tag setting: :search_context
  test "native medium hosted-search context reaches the provider without executing search",
       ctx do
    exercise(ctx)
  end

  defp fixture(base, root, selection) do
    model = model_fixture(root)
    File.write!(model.requests, "[]")
    ctx = Map.merge(base, %{root: root, fixture: model, selection: selection})

    TurnFixture.configure_model(ctx, %{
      "support_verbosity" => true,
      "default_verbosity" => "low",
      "web_search_tool_type" => "text",
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(model.codex_home, "config.toml")
    write_config(config, base.setting, selection)

    paths = [
      config,
      Path.join(model.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.put(ctx, :inputs, Map.new(paths, &{&1, snapshot(&1)}))
  end

  defp model_fixture(root) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    fixture
  end

  defp write_config(path, setting, selection) do
    original = File.read!(path)

    body =
      if setting == :search_context do
        assert String.contains?(original, "web_search = \"disabled\"\n")
        String.replace(original, "web_search = \"disabled\"\n", "web_search = \"live\"\n")
      else
        original
      end

    File.write!(
      path,
      scalar_selection(setting, selection) <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        body <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n" <>
        table_selection(setting, selection)
    )
  end

  defp scalar_selection(:verbosity, :medium), do: "model_verbosity = \"medium\"\n"
  defp scalar_selection(_setting, _selection), do: ""

  defp table_selection(:search_context, :medium),
    do: "\n[tools.web_search]\ncontext_size = \"medium\"\n"

  defp table_selection(:search_context, :control), do: "\n[tools.web_search]\n"
  defp table_selection(_setting, _selection), do: ""

  defp exercise(ctx) do
    control = start(ctx.control)
    control_native = native_id(ctx.control, control)
    assert_config(ctx.control, control)
    baseline = turn(ctx.control, control, 1)
    assert_retained(ctx.control, control, baseline)
    control_journal = snapshot(ctx.control.fixture.requests)
    close(control, control_native)
    assert_inputs(ctx.inputs)

    warm = start(ctx.selected)
    warm_native = native_id(ctx.selected, warm)
    refute warm_native == control_native
    assert_config(ctx.selected, warm)
    first = turn(ctx.selected, warm, 1)
    assert_retained(ctx.selected, warm, first)
    first_journal = snapshot(ctx.selected.fixture.requests)
    close(warm, warm_native)
    assert_inputs(ctx.inputs)

    cold = start(ctx.selected)
    cold_native = native_id(ctx.selected, cold)
    assert cold_native not in [control_native, warm_native]
    assert call(ctx.selected, cold, "thread/loaded/list", %{})["data"] == []
    assert snapshot(ctx.selected.fixture.requests) === first_journal
    assert_config(ctx.selected, cold)
    assert_retained(ctx.selected, cold, first)
    assert call(ctx.selected, cold, "thread/loaded/list", %{})["data"] == []

    # Cold startup reads persisted configuration; the next explicit new turn is
    # the only new work. No resume, reconnect replay or automatic retry is used.
    second = turn(ctx.selected, cold, 2)
    refute second.thread == first.thread
    refute second.turn == first.turn
    assert_retained(ctx.selected, cold, first)
    assert_retained(ctx.selected, cold, second)
    selected_journal = snapshot(ctx.selected.fixture.requests)
    close(cold, cold_native)
    assert_inputs(ctx.inputs)
    assert snapshot(first.path) === first.snapshot
    assert snapshot(second.path) === second.snapshot
    assert snapshot(baseline.path) === baseline.snapshot
    assert snapshot(ctx.control.fixture.requests) === control_journal
    assert snapshot(ctx.selected.fixture.requests) === selected_journal
    assert length(ModelFixture.requests(ctx.control.fixture)) == 1
    assert length(ModelFixture.requests(ctx.selected.fixture)) == 2
    assert_capture(ctx.capture)
  end

  defp assert_config(ctx, pid) do
    before = snapshot(ctx.fixture.requests)
    config = call(ctx, pid, "config/read", %{"includeLayers" => false})["config"]
    assert_config_selection(config, ctx.setting, ctx.selection)
    assert snapshot(ctx.fixture.requests) === before
    assert_inputs(ctx.inputs)
    assert_idle(pid)
  end

  defp assert_config_selection(config, :verbosity, selection) do
    expected = if selection == :medium, do: "medium", else: nil
    assert Map.fetch!(config, "model_verbosity") === expected
  end

  defp assert_config_selection(config, :search_context, selection) do
    expected = if selection == :medium, do: "medium", else: nil

    assert Map.fetch!(config, "tools") === %{
             "web_search" => %{
               "context_size" => expected,
               "allowed_domains" => nil,
               "location" => nil
             }
           }
  end

  defp turn(ctx, pid, count) do
    previous = ModelFixture.requests(ctx.fixture)
    assert length(previous) == count - 1
    text = "Owned medium #{ctx.setting} #{ctx.selection} turn #{count} λ🙂"

    thread =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    assert ModelFixture.requests(ctx.fixture) == previous

    id =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

    assert is_binary(id) and byte_size(id) > 0
    events = complete_turn(pid, thread, id, [], deadline(20_000))
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    assert Enum.take(requests, count - 1) === previous
    assert_provider(List.last(requests), ctx, thread, id, text)
    saved = saved_history(ctx, pid, thread, id, text, events)
    assert_idle(pid)
    saved
  end

  defp assert_provider(request, ctx, thread, turn, text) do
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    texts =
      for item <- request["input"],
          item["role"] == "user",
          part <- item["content"],
          part["type"] == "input_text",
          do: part["text"]

    assert Enum.count(texts, &(&1 == text)) == 1

    assert Enum.filter(
             request["input"],
             &(&1["type"] in ["function_call", "function_call_output"])
           ) ==
             []

    assert_provider_selection(request, ctx.setting, ctx.selection)
  end

  defp assert_provider_selection(request, :verbosity, selection) do
    expected = if selection == :medium, do: "medium", else: "low"
    assert Map.fetch!(Map.fetch!(request, "text"), "verbosity") === expected
  end

  defp assert_provider_selection(request, :search_context, selection) do
    assert [tool] = Enum.filter(Map.fetch!(request, "tools"), &(&1["type"] == "web_search"))

    if selection == :medium do
      assert Map.fetch!(tool, "search_context_size") === "medium"
    else
      refute Map.has_key?(tool, "search_context_size")
    end
  end

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid, 256)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert Enum.all?(events, &(&1.generation == generation))
    assert Enum.all?(events, &(&1.kind == :notification))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences == Enum.sort(Enum.uniq(sequences))
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))

    completed =
      Enum.find(events, fn event ->
        event.wire["method"] == "turn/completed" and
          event.wire["params"]["threadId"] == thread and
          event.wire["params"]["turn"]["id"] == turn
      end)

    if completed do
      assert completed.wire["params"]["turn"]["status"] == "completed"
      assert completed.wire["params"]["turn"]["error"] == nil
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native medium config turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected medium config event gap")
      after
        10 -> :ok
      end

      complete_turn(pid, thread, turn, events, until)
    end
  end

  defp saved_history(ctx, pid, thread, turn, text, events) do
    saved = read(ctx, pid, thread)
    assert [%{"id" => ^turn, "status" => "completed", "error" => nil} = row] = saved["turns"]
    assert row["itemsView"] == "full"

    completed =
      for event <- events,
          event.wire["method"] == "item/completed",
          do: event.wire["params"]

    assert Enum.map(completed, & &1["item"]["type"]) == ["userMessage", "agentMessage"]
    assert row["items"] === Enum.map(completed, & &1["item"])
    [user, assistant] = row["items"]
    refute user["id"] == assistant["id"]
    assert user["content"] == [%{"type" => "text", "text" => text, "text_elements" => []}]
    assert assistant["text"] == @answer
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    %{thread: thread, turn: turn, path: path, turns: saved["turns"], snapshot: snapshot(path)}
  end

  defp assert_retained(ctx, pid, saved) do
    before = snapshot(ctx.fixture.requests)
    assert_inputs(ctx.inputs)
    assert snapshot(saved.path) === saved.snapshot
    native = read(ctx, pid, saved.thread)
    assert native["id"] == saved.thread
    assert native["historyMode"] == "paginated"
    assert native["path"] == saved.path
    assert native["turns"] === saved.turns
    assert snapshot(saved.path) === saved.snapshot
    assert snapshot(ctx.fixture.requests) === before
    assert File.ls!(ctx.fixture.workspace) == []
    assert_idle(pid)
    assert {:ok, events} = Session.drain(pid, 256)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             method == "error" or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(ctx.inputs)
  end

  defp assert_idle(pid) do
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp read(ctx, pid, thread),
    do: call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp assert_inputs(inputs) do
    for {path, original} <- inputs, do: assert(snapshot(path) === original)
  end

  defp assert_capture(capture) do
    frames = Agent.get(capture, & &1)
    assert length(frames) == 9

    for method <- @captured do
      assert Enum.count(frames, fn {_bytes, wire} -> wire["method"] == method end) == 3
    end
  end

  defp call(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-medium-config-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    if method in @captured do
      assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
      assert actual === wire
      assert JSON.decode!(bytes) === wire
      assert bytes === JSON.encode!(wire)
    else
      assert length(Agent.get(ctx.capture, & &1)) == before
    end

    result
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_medium_config_effects", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
