defmodule SamgitaCodexDriver.NativeThreadStartDefaultValuesTest do
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
  @answer "Deterministic local fixture answer"
  @global "Owned global thread-start instructions λ. Preserve this fixture marker.\n"
  @literal """
  Owned start personality base λ
  # Personality
  Owned literal style {{ personality }}
  ## Details
  Owned literal detail.
  # Rules
  Owned stable start rule.
  """
  @stripped """
  Owned start personality base λ
  # Rules
  Owned stable start rule.
  """

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
      if length(Agent.get(state.capture, & &1)) < 10 and byte_size(encoded) <= 4096 do
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

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @literal}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(personality = "pragmatic"\nmodel_reasoning_summary = "auto"\n) <>
        "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    instructions = Path.join(ctx.fixture.codex_home, "AGENTS.md")
    File.write!(instructions, @global, [:exclusive])
    catalog = Path.join(ctx.fixture.codex_home, "turn-models.json")

    inputs =
      Map.new([config, catalog, instructions], fn path ->
        bytes = File.read!(path)
        {path, %{bytes: bytes, sha256: hash(bytes)}}
      end)

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, inputs: inputs, instructions: instructions})
  end

  test "native starts apply personality values and nullable defaults with loaded instruction sources",
       ctx do
    assert File.ls!(ctx.fixture.workspace) == []
    first = start(ctx)
    original_process = native_id(first)

    rows =
      for {{label, extra, personality, history, instructions}, index} <-
            Enum.with_index(cases(), 1) do
        params =
          Map.merge(
            %{
              "model" => "mock-model",
              "modelProvider" => "fixture",
              "cwd" => ctx.fixture.workspace,
              "ephemeral" => false
            },
            extra
          )

        %{"result" => result} = request(ctx, first, "thread/start", params)
        thread = Map.fetch!(result, "thread")
        id = Map.fetch!(thread, "id")
        assert is_binary(id) and id != ""
        assert Map.fetch!(thread, "historyMode") == history
        sources = Map.fetch!(result, "instructionSources")
        assert is_list(sources) and sources != []
        assert ctx.instructions in sources
        assert length(ModelFixture.requests(ctx.fixture)) == index - 1

        # A summary-only update exposes the applied personality independently;
        # it cannot replace the personality supplied to thread/start.
        assert call(first, "thread/settings/update", %{
                 "threadId" => id,
                 "summary" => "concise"
               }) == %{}

        {notice, _events} =
          await_notice(
            first,
            "thread/settings/updated",
            &(&1["threadId"] == id and &1["threadSettings"]["summary"] == "concise"),
            [],
            deadline(5000)
          )

        settings = Map.fetch!(notice, "threadSettings")
        assert Map.fetch!(settings, "personality") === personality
        assert Map.fetch!(settings, "summary") == "concise"
        assert length(ModelFixture.requests(ctx.fixture)) == index - 1

        marker = "owned-thread-start-default-#{label}"

        %{"result" => %{"turn" => %{"id" => turn}}} =
          request(ctx, first, "turn/start", %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => marker}]
          })

        complete_turn(first, id, turn)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        assert_provider(List.last(requests), instructions, marker)

        if history == "legacy" do
          assert_legacy_turn(first, id, turn, marker)
        end

        %{id: id, turn: turn, history: history, marker: marker}
      end

    assert length(Enum.uniq(Enum.map(rows, & &1.id))) == 5
    assert length(Enum.uniq(Enum.map(rows, & &1.turn))) == 5
    assert length(Agent.get(ctx.capture, & &1)) == 10
    journal = File.read!(ctx.fixture.requests)
    assert_retained(ctx, first)
    assert :ok = Session.close(first)
    refute File.exists?("/proc/#{original_process}")

    cold = start(ctx)
    assert native_id(cold) != original_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    for row <- rows do
      # Metadata-only cold reads observe the stored contract without entering
      # paginated turn reconstruction or claiming its lifecycle emitters.
      saved =
        call(cold, "thread/read", %{"threadId" => row.id, "includeTurns" => false})[
          "thread"
        ]

      assert Map.fetch!(saved, "id") == row.id
      assert Map.fetch!(saved, "historyMode") == row.history

      if row.history == "legacy" do
        assert_legacy_turn(cold, row.id, row.turn, row.marker)
      end
    end

    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert File.read!(ctx.fixture.requests) == journal
    assert length(Agent.get(ctx.capture, & &1)) == 10
    assert_retained(ctx, cold)
    replacement_process = native_id(cold)
    assert :ok = Session.close(cold)
    refute File.exists?("/proc/#{replacement_process}")
  end

  defp cases do
    [
      {"none", %{"personality" => "none", "historyMode" => "legacy"}, "none", "legacy",
       @stripped},
      {"friendly", %{"personality" => "friendly", "historyMode" => "legacy"}, "friendly",
       "legacy", @literal},
      {"pragmatic", %{"personality" => "pragmatic", "historyMode" => "legacy"}, "pragmatic",
       "legacy", @literal},
      {"null", %{"personality" => nil, "historyMode" => nil}, "pragmatic", "paginated", @literal},
      {"omitted", %{}, "pragmatic", "paginated", @literal}
    ]
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    wire = envelope(method, params)
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => _result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [%{encoded: encoded, wire: captured}] =
             Agent.get(ctx.capture, &Enum.drop(&1, before))

    assert captured === wire
    assert JSON.decode!(encoded) === wire
    response
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
      "id" => "owned-thread-start-default-#{System.unique_integer([:positive, :monotonic])}",
      "method" => method,
      "params" => params
    }
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
             notification(events, "item/completed", fn params ->
               params["threadId"] == thread and params["turnId"] == turn and
                 params["item"]["type"] == "agentMessage"
             end)
  end

  defp assert_provider(request, instructions, marker) do
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => ^instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
    assert Enum.any?(user_texts, &String.contains?(&1, String.trim(@global)))
  end

  defp assert_legacy_turn(pid, thread, turn, marker) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "historyMode") == "legacy"
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = saved["turns"]
    assert [%{"type" => "userMessage", "content" => content}, assistant] = items
    assert [%{"type" => "text", "text" => ^marker}] = content
    assert %{"type" => "agentMessage", "text" => @answer} = assistant
  end

  defp await_notice(pid, method, predicate, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native start-default event buffer exceeded its bound"
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    case notification(events, method, predicate) do
      nil ->
        assert Session.status(pid).phase == :ready

        assert System.monotonic_time(:millisecond) < until,
               "native start-default #{method} deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during start defaults")
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
               %{"name" => "owned_thread_start_defaults", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
