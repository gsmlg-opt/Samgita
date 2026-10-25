defmodule SamgitaCodexDriver.NativeThreadStartSourceValuesTest do
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
  @moduletag timeout: 120_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed thread-start source fixture instructions."
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

      if wire["method"] in ["thread/start", "turn/start"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 8 and byte_size(encoded) <= 4096 do
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
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "supported_reasoning_levels" => [
        %{"effort" => "low", "description" => "Synthetic low metadata"}
      ],
      "supports_reasoning_summary_parameter" => true,
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "auto"\n) <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native start-source values preserve separate histories and label only their owning runtime",
       ctx do
    pid = start(ctx)

    rows =
      Enum.reduce(Enum.with_index(cases(), 1), [], fn {{extra, initialization, marker}, index},
                                                      previous ->
        # In particular, the clear-source request must leave all earlier
        # completed public histories intact before and after its own turn.
        assert_histories(pid, previous)
        before = File.read!(ctx.fixture.requests)
        result = request(ctx, pid, "thread/start", Map.merge(thread_params(ctx), extra))
        thread = Map.fetch!(result, "thread")
        id = Map.fetch!(thread, "id")
        path = Map.fetch!(thread, "path")
        assert is_binary(id) and id != ""
        assert is_binary(path) and path != ""
        assert Map.fetch!(thread, "turns") == []
        refute Enum.any?(previous, &(&1.id == id or &1.path == path))

        {started, _events} =
          await_notice(pid, "thread/started", &(&1["thread"]["id"] == id), [], deadline(5000))

        assert Map.fetch!(started, "thread") |> Map.fetch!("id") == id
        assert Map.fetch!(started, "thread") |> Map.fetch!("path") == path
        assert Map.fetch!(started, "thread") |> Map.fetch!("turns") == []
        assert File.read!(ctx.fixture.requests) == before
        apply_summary(pid, id)
        assert File.read!(ctx.fixture.requests) == before

        turn =
          request(ctx, pid, "turn/start", %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => marker}]
          })["turn"]["id"]

        assert is_binary(turn)
        complete_turn(pid, id, turn)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        assert_provider(List.last(requests), id, turn, initialization, marker)
        saved = read(pid, id)
        assert Map.fetch!(saved, "id") == id
        assert Map.fetch!(saved, "path") == path
        assert Map.fetch!(saved, "preview") == marker
        assert [saved_turn] = Map.fetch!(saved, "turns")
        assert_text_turn(saved_turn, turn, marker)
        assert File.regular?(path)
        assert_histories(pid, previous)

        previous ++
          [%{id: id, path: path, turn: turn, marker: marker, turns: saved["turns"]}]
      end)

    assert length(rows) == 4
    assert_histories(pid, rows)
    assert_fixture(ctx, pid)
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    journal = File.read!(ctx.fixture.requests)
    captures = Agent.get(ctx.capture, & &1)
    assert Enum.count(captures, &(&1["method"] == "thread/start")) == 4
    assert Enum.count(captures, &(&1["method"] == "turn/start")) == 4

    old_native = native_id(pid)
    assert :ok = close(pid)
    replacement = start(ctx)
    assert native_id(replacement) != old_native
    assert TurnFixture.call(replacement, "thread/loaded/list", %{})["data"] == []

    # Cold reads observe persisted histories without loading a runtime or
    # issuing any new turn. No rollout-byte flush assumption is involved.
    assert_histories(replacement, rows)
    assert TurnFixture.call(replacement, "thread/loaded/list", %{})["data"] == []
    assert Agent.get(ctx.capture, & &1) === captures
    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert_fixture(ctx, replacement)
    assert :ok = close(replacement)
  end

  defp cases do
    [
      {%{}, "new", "owned-start-source-omitted λ"},
      {%{"sessionStartSource" => nil}, "new", "owned-start-source-null λ"},
      {%{"sessionStartSource" => "startup"}, "new", "owned-start-source-startup λ"},
      {%{"sessionStartSource" => "clear"}, "cleared", "owned-start-source-clear λ"}
    ]
  end

  defp thread_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "ephemeral" => false,
      "historyMode" => "legacy"
    }
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-start-source-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp apply_summary(pid, thread) do
    assert TurnFixture.call(pid, "thread/settings/update", %{
             "threadId" => thread,
             "summary" => "concise"
           }) == %{}

    {notice, _events} =
      await_notice(
        pid,
        "thread/settings/updated",
        &(&1["threadId"] == thread and &1["threadSettings"]["summary"] == "concise"),
        [],
        deadline(5000)
      )

    settings = Map.fetch!(notice, "threadSettings")
    assert Map.fetch!(settings, "summary") == "concise"
    assert Map.fetch!(settings, "effort") == "low"
    assert Map.fetch!(settings, "model") == "mock-model"
  end

  defp complete_turn(pid, thread, turn) do
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
             TurnFixture.notification(events, "item/completed", fn params ->
               params["threadId"] == thread and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)
  end

  defp assert_provider(request, thread, turn, initialization, marker) do
    assert Map.fetch!(request, "model") == "mock-model"
    assert request["reasoning"] == %{"effort" => "low", "summary" => "concise"}

    assert %{
             "thread_id" => ^thread,
             "turn_id" => ^turn,
             "history_initialization" => ^initialization
           } = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1

    for {_extra, _initialization, other} <- cases(), other != marker do
      refute Enum.any?(user_texts, &String.contains?(&1, other))
    end
  end

  defp assert_histories(pid, rows) do
    for original <- rows do
      saved = read(pid, original.id)
      assert Map.fetch!(saved, "id") == original.id
      assert Map.fetch!(saved, "path") == original.path
      assert Map.fetch!(saved, "preview") == original.marker
      assert Map.fetch!(saved, "turns") === original.turns
      assert [turn] = saved["turns"]
      assert_text_turn(turn, original.turn, original.marker)
      assert File.regular?(original.path)
    end
  end

  defp assert_text_turn(turn, id, marker) do
    assert Map.fetch!(turn, "id") == id
    assert Map.fetch!(turn, "status") == "completed"
    assert Enum.map(turn["items"], & &1["type"]) == ["userMessage", "agentMessage"]
    [user, assistant] = turn["items"]

    assert user["content"] == [
             %{"type" => "text", "text" => marker, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "text") == @answer
  end

  defp read(pid, thread),
    do:
      TurnFixture.call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]

  defp await_notice(pid, method, predicate, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native start-source event buffer exceeded its bound"

    case TurnFixture.notification(events, method, predicate) do
      nil ->
        assert Session.status(pid).phase == :ready

        assert System.monotonic_time(:millisecond) < until,
               "native start-source #{method} deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during source scenario")
        after
          10 -> :ok
        end

        await_notice(pid, method, predicate, events, until)

      notice ->
        {notice, events}
    end
  end

  defp assert_fixture(ctx, pid) do
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp native_id(pid) do
    native = TurnFixture.call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid) do
    native = native_id(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
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
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
               %{"name" => "owned_thread_start_source_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
