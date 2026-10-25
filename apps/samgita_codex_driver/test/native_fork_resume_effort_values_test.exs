defmodule SamgitaCodexDriver.NativeForkResumeEffortValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed fork and resume effort fixture instructions."
  @answer "Deterministic local fixture answer"

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

      if wire["method"] in ["thread/fork", "thread/resume", "turn/start"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 8 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
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
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    # A supported low preset is not a default. Omitting the model default makes
    # null native effort and absent inference effort independently observable.
    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Synthetic low metadata"}
      ],
      "supports_reasoning_summary_parameter" => true,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    effort =
      case tags[:configured_effort] do
        nil -> ""
        "low" -> ~s(model_reasoning_effort = "low"\n)
      end

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      effort <>
        ~s(model_reasoning_summary = "auto"\ncli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      for path <- [config, Path.join(ctx.fixture.codex_home, "turn-models.json")], into: %{} do
        bytes = File.read!(path)
        {path, %{bytes: bytes, sha256: hash(bytes)}}
      end

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs})
  end

  test "absent effort stays null in fork and cold resume and is absent from inference", ctx do
    qualify(ctx, nil, "absent")
  end

  @tag configured_effort: "low"
  test "configured low survives fork and explicit-model cold resume into inference", ctx do
    qualify(ctx, "low", "low")
  end

  defp qualify(ctx, expected_effort, label) do
    assert File.ls!(ctx.fixture.workspace) == []
    first = start(ctx)
    first_native = native_id(first)
    name = "Owned fork-resume effort #{label}"
    child_marker = "owned-fork-effort-#{label}"
    parent_marker = "owned-resume-effort-#{label}"

    parent_id =
      call(first, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "legacy",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(parent_id) and byte_size(parent_id) > 0
    assert call(first, "thread/name/set", %{"threadId" => parent_id, "name" => name}) == %{}
    parent = read(first, parent_id)

    assert %{"id" => ^parent_id, "name" => ^name, "historyMode" => "legacy", "turns" => []} =
             parent

    parent_path = Map.fetch!(parent, "path")
    assert File.regular?(parent_path)
    parent_bytes = File.read!(parent_path)
    assert ModelFixture.requests(ctx.fixture) == []

    fork = request(ctx, first, "thread/fork", %{"threadId" => parent_id, "model" => "mock-model"})
    assert Map.fetch!(fork, "reasoningEffort") === expected_effort
    child = Map.fetch!(fork, "thread")
    child_id = Map.fetch!(child, "id")
    assert is_binary(child_id) and byte_size(child_id) > 0
    refute child_id == parent_id
    assert Map.fetch!(child, "forkedFromId") == parent_id
    assert Map.fetch!(child, "historyMode") == "legacy"
    assert Map.fetch!(child, "turns") == []
    child_path = Map.fetch!(child, "path")
    assert File.regular?(child_path)
    refute child_path == parent_path
    assert_parent(first, parent, parent_bytes)
    assert ModelFixture.requests(ctx.fixture) == []

    apply_summary(first, child_id, expected_effort)
    assert ModelFixture.requests(ctx.fixture) == []
    child_turn = turn(ctx, first, child_id, child_marker)
    assert [child_provider] = ModelFixture.requests(ctx.fixture)

    assert_provider(
      child_provider,
      child_id,
      child_turn,
      expected_effort,
      child_marker,
      parent_marker
    )

    first_journal = File.read!(ctx.fixture.requests)
    assert_parent(first, parent, parent_bytes)
    child_saved = assert_history(first, child_id, child_turn, child_marker)
    assert Map.fetch!(child_saved, "path") == child_path
    assert File.read!(ctx.fixture.requests) === first_journal
    assert_retained(ctx, first)
    close(first, first_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == first_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_parent(cold, parent, parent_bytes)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert File.read!(ctx.fixture.requests) === first_journal

    # The explicit model override deliberately avoids the distinct production
    # branch that clears configured effort when empty saved metadata lacks it.
    resume =
      request(ctx, cold, "thread/resume", %{"threadId" => parent_id, "model" => "mock-model"})

    assert Map.fetch!(resume, "reasoningEffort") === expected_effort
    assert Map.fetch!(resume, "thread")["id"] == parent_id
    assert Map.fetch!(resume, "thread")["turns"] == []
    assert File.read!(ctx.fixture.requests) === first_journal

    apply_summary(cold, parent_id, expected_effort)
    assert File.read!(ctx.fixture.requests) === first_journal
    parent_turn = turn(ctx, cold, parent_id, parent_marker)
    refute parent_turn == child_turn
    assert [^child_provider, parent_provider] = ModelFixture.requests(ctx.fixture)

    assert_provider(
      parent_provider,
      parent_id,
      parent_turn,
      expected_effort,
      parent_marker,
      child_marker
    )

    final_journal = File.read!(ctx.fixture.requests)
    parent_saved = assert_history(cold, parent_id, parent_turn, parent_marker)
    assert Map.fetch!(parent_saved, "name") == name
    assert Map.fetch!(parent_saved, "path") == parent_path
    child_after = assert_history(cold, child_id, child_turn, child_marker)
    assert Map.fetch!(child_after, "path") == child_path
    assert Map.fetch!(child_after, "turns") === Map.fetch!(child_saved, "turns")
    assert File.read!(ctx.fixture.requests) === final_journal
    assert length(Agent.get(ctx.capture, & &1)) == 4
    assert_retained(ctx, cold)
    close(cold, cold_native)
    assert File.read!(ctx.fixture.requests) === final_journal
  end

  defp apply_summary(pid, thread, expected_effort) do
    assert call(pid, "thread/settings/update", %{"threadId" => thread, "summary" => "concise"}) ==
             %{}

    {notice, _events} =
      await_notice(
        pid,
        "thread/settings/updated",
        &(&1["threadId"] == thread and &1["threadSettings"]["summary"] == "concise"),
        [],
        deadline(5_000)
      )

    settings = Map.fetch!(notice, "threadSettings")
    assert Map.fetch!(settings, "summary") == "concise"
    assert Map.fetch!(settings, "effort") === expected_effort
  end

  defp turn(ctx, pid, thread, marker) do
    turn =
      request(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0

    {completed, events} =
      await_notice(
        pid,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn),
        [],
        deadline(20_000)
      )

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             completed

    assert %{"item" => %{"type" => "agentMessage", "text" => @answer}} =
             notification(events, "item/completed", fn params ->
               params["threadId"] == thread and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)

    turn
  end

  defp assert_provider(provider, thread, turn, effort, marker, other_marker) do
    assert Map.fetch!(provider, "model") == "mock-model"

    expected_reasoning =
      case effort do
        nil -> %{"summary" => "concise"}
        "low" -> %{"summary" => "concise", "effort" => "low"}
      end

    assert Map.fetch!(provider, "reasoning") === expected_reasoning

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(provider["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(provider["input"])

    user_texts =
      for item <- provider["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
    refute Enum.any?(user_texts, &String.contains?(&1, other_marker))
  end

  defp assert_parent(pid, parent, bytes) do
    saved = read(pid, Map.fetch!(parent, "id"))

    for key <- ["id", "name", "path"] do
      assert Map.fetch!(saved, key) === Map.fetch!(parent, key)
    end

    assert Map.fetch!(saved, "historyMode") == "legacy"
    assert Map.fetch!(saved, "turns") == []
    assert File.read!(Map.fetch!(parent, "path")) === bytes
  end

  defp assert_history(pid, thread, turn, marker) do
    saved = read(pid, thread)
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "legacy"
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = saved["turns"]
    assert [%{"type" => "userMessage", "content" => content}, assistant] = items
    assert [%{"type" => "text", "text" => ^marker}] = content
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
    saved
  end

  defp read(pid, id),
    do: call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    wire = envelope(method, params)
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [%{encoded: encoded, wire: captured}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert captured === wire
    assert JSON.decode!(encoded) === wire
    result
  end

  defp call(pid, method, params) do
    wire = envelope(method, params)
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    result
  end

  defp envelope(method, params) do
    %{
      "id" => "owned-fork-resume-effort-#{System.unique_integer([:positive, :monotonic])}",
      "method" => method,
      "params" => params
    }
  end

  defp await_notice(pid, method, predicate, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    assert length(events) <= 256,
           "Native fork/resume effort event buffer exceeded its count bound"

    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    receive do
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during fork/resume effort")
    after
      0 -> :ok
    end

    case notification(events, method, predicate) do
      nil ->
        assert System.monotonic_time(:millisecond) < until,
               "native fork/resume effort #{method} deadline"

        receive do
          {:codex_driver, ^pid, :events_available} ->
            :ok

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected event gap during fork/resume effort")
        after
          10 -> :ok
        end

        await_notice(pid, method, predicate, events, until)

      notice ->
        {notice, events}
    end
  end

  defp assert_retained(ctx, pid) do
    for {path, expected} <- ctx.inputs do
      bytes = File.read!(path)
      assert bytes === expected.bytes
      assert hash(bytes) == expected.sha256
    end

    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp native_id(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
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
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
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
               %{"name" => "owned_fork_resume_effort_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
