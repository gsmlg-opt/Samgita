defmodule SamgitaCodexDriver.NativeTurnPersonalityTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @answer "Deterministic local fixture answer"
  @literal """
  Owned turn personality base λ
  # Personality
  Owned fixed style {{ personality }}
  ## Details
  Owned existing detail.
  # Rules
  Owned stable rule.
  """
  @stripped """
  Owned turn personality base λ
  # Rules
  Owned stable rule.
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

      if wire["method"] in ["thread/start", "turn/start"] or
           (wire["method"] == "thread/settings/update" and
              Map.has_key?(wire["params"], "personality")) do
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
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @literal}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(personality = "pragmatic"\n) <>
        "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  for initial <- ["none", "friendly"] do
    @initial initial
    test "turn personality preserves omission/null and existing #{@initial} instructions", ctx do
      qualify(ctx, @initial)
    end
  end

  for name <- ~w(none friendly pragmatic), payload <- [nil, %{}] do
    @tag initial_personality: %{name => payload}, canonical_personality: name
    test "fresh tagged #{name} with #{inspect(payload)} selects canonical metadata and original instructions",
         ctx do
      pid = start(ctx)
      thread = new_thread(ctx, pid, ctx.initial_personality)
      assert ModelFixture.requests(ctx.fixture) == []
      snapshot(ctx, pid, thread, ctx.canonical_personality, 0)
      expected = if ctx.canonical_personality == "none", do: @stripped, else: @literal

      turn = ordinary_turn(ctx, pid, thread, "owned-tagged-initial-personality", expected, 1)
      assert_saved(ctx, pid, thread, [turn], 1)
      assert :ok = Session.close(pid)
    end
  end

  test "idle tagged personality updates preserve inherited instructions for omitted-personality turns",
       ctx do
    pid = start(ctx)
    thread = new_thread(ctx, pid, "none")
    first = ordinary_turn(ctx, pid, thread, "owned-idle-personality-original", @stripped, 1)

    turns =
      for {{input, canonical}, index} <- Enum.with_index(unit_personalities(), 1) do
        requests = ModelFixture.requests(ctx.fixture)
        summary = if rem(index, 2) == 0, do: "concise", else: "detailed"
        params = %{"threadId" => thread, "personality" => input, "summary" => summary}
        assert call(pid, "thread/settings/update", params) == %{}
        sent = captured(ctx, "thread/settings/update")
        assert length(sent) == index
        assert List.last(sent)["params"] === params

        snapshot_event(
          pid,
          thread,
          canonical,
          summary,
          [],
          System.monotonic_time(:millisecond) + 5_000
        )

        assert ModelFixture.requests(ctx.fixture) == requests

        ordinary_turn(
          ctx,
          pid,
          thread,
          "owned-idle-personality-followup-#{index}",
          @stripped,
          index + 1
        )
      end

    assert length(turns) == 6
    assert_saved(ctx, pid, thread, [first | turns], 7)
    assert :ok = Session.close(pid)
  end

  defp qualify(ctx, initial) do
    pid = start(ctx)
    thread = new_thread(ctx, pid, initial)

    expected_instructions = if initial == "none", do: @stripped, else: @literal

    assert ModelFixture.requests(ctx.fixture) == []
    snapshot(ctx, pid, thread, initial, 0)

    canonical_cases = [
      {%{}, initial},
      {%{"personality" => nil}, initial},
      {%{"personality" => "pragmatic"}, "pragmatic"},
      {%{}, "pragmatic"},
      {%{"personality" => nil}, "pragmatic"},
      {%{"personality" => "friendly"}, "friendly"},
      {%{"personality" => "none"}, "none"},
      {%{"personality" => nil}, "none"},
      {%{}, "none"}
    ]

    cases =
      canonical_cases ++
        Enum.map(unit_personalities(), fn {input, canonical} ->
          {%{"personality" => input}, canonical}
        end)

    assert length(canonical_cases) == 9
    assert length(cases) == 15

    turns =
      for {{extra, expected}, index} <- Enum.with_index(cases, 1) do
        marker = "owned-turn-personality-#{initial}-#{index}"
        input = [%{"type" => "text", "text" => marker}]
        params = Map.merge(%{"threadId" => thread, "input" => input}, extra)
        turn = call(pid, "turn/start", params)["turn"]["id"]
        sent = captured(ctx, "turn/start")
        assert length(sent) == index
        assert List.last(sent)["params"] === params

        assert Map.has_key?(List.last(sent)["params"], "personality") ==
                 Map.has_key?(extra, "personality")

        events =
          complete_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)

        refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        request = List.last(requests)
        assert request["model"] == "mock-model"
        refute Map.has_key?(request, "instructions")

        assert %{
                 "type" => "message",
                 "role" => "developer",
                 "content" => [%{"type" => "input_text", "text" => ^expected_instructions}]
               } = hd(request["input"])

        user_texts =
          for item <- request["input"],
              item["role"] == "user",
              content <- item["content"],
              content["type"] == "input_text",
              do: content["text"]

        assert Enum.count(user_texts, &(&1 == marker)) == 1
        snapshot(ctx, pid, thread, expected, index)
        turn
      end

    assert length(Enum.uniq(turns)) == 15
    before = ModelFixture.requests(ctx.fixture)
    captures = Agent.get(ctx.capture, & &1)
    invalid = %{"threadId" => thread, "input" => [], "personality" => "unknown-owned-style"}
    assert {:error, %Error{code: :schema_violation}} = Session.request(pid, "turn/start", invalid)
    assert Agent.get(ctx.capture, & &1) == captures

    error = upstream_error(pid, "turn/start", invalid, validation: :wire)
    assert error["code"] == -32_600
    assert error["message"] =~ "unknown variant `unknown-owned-style`"
    assert ModelFixture.requests(ctx.fixture) == before
    snapshot(ctx, pid, thread, "pragmatic", 16)
    assert ModelFixture.requests(ctx.fixture) == before

    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Enum.map(saved["turns"], & &1["id"]) == turns
    assert Enum.all?(saved["turns"], &(&1["status"] == "completed"))
    assert File.ls!(ctx.fixture.workspace) == []
    assert File.read!(ctx.config) == ctx.config_bytes
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert :ok = Session.close(pid)
  end

  defp unit_personalities,
    do:
      for(
        name <- ~w(none friendly pragmatic),
        payload <- [nil, %{}],
        do: {%{name => payload}, name}
      )

  defp captured(ctx, method),
    do: Agent.get(ctx.capture, &Enum.filter(&1, fn wire -> wire["method"] == method end))

  defp new_thread(ctx, pid, initial) do
    thread =
      TurnFixture.thread(ctx, pid, %{
        "personality" => initial,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    assert [sent] = captured(ctx, "thread/start")

    assert sent["params"] === %{
             "model" => "mock-model",
             "modelProvider" => "fixture",
             "cwd" => ctx.fixture.workspace,
             "sandbox" => "danger-full-access",
             "approvalPolicy" => "never",
             "ephemeral" => false,
             "personality" => initial
           }

    thread
  end

  defp ordinary_turn(ctx, pid, thread, marker, instructions, count) do
    params = %{"threadId" => thread, "input" => [%{"type" => "text", "text" => marker}]}
    turn = call(pid, "turn/start", params)["turn"]["id"]
    sent = captured(ctx, "turn/start")
    assert length(sent) == count
    assert List.last(sent)["params"] === params
    refute Map.has_key?(List.last(sent)["params"], "personality")
    events = complete_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    request = List.last(requests)
    assert request["model"] == "mock-model"
    refute Map.has_key?(request, "instructions")

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
    turn
  end

  defp assert_saved(ctx, pid, thread, turns, count) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Enum.map(saved["turns"], & &1["id"]) == turns
    assert length(Enum.uniq(turns)) == count
    assert Enum.all?(saved["turns"], &(&1["status"] == "completed"))

    for turn <- saved["turns"] do
      assert [%{"type" => "userMessage"}, %{"type" => "agentMessage", "text" => @answer}] =
               turn["items"]
    end

    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert File.ls!(ctx.fixture.workspace) == []
    assert File.read!(ctx.config) == ctx.config_bytes
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp complete_turn(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    completed = notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    if completed do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               completed

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
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "native turn completion deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        20 -> :ok
      end

      complete_turn(pid, thread, turn, events, deadline)
    end
  end

  # A distinct summary update is an observable public snapshot barrier. It
  # never submits personality or a turn, and must not call the model provider.
  defp snapshot(ctx, pid, thread, expected, index) do
    requests = ModelFixture.requests(ctx.fixture)
    summary = if rem(index, 2) == 0, do: "concise", else: "detailed"

    assert call(pid, "thread/settings/update", %{"threadId" => thread, "summary" => summary}) ==
             %{}

    snapshot_event(
      pid,
      thread,
      expected,
      summary,
      [],
      System.monotonic_time(:millisecond) + 5_000
    )

    assert ModelFixture.requests(ctx.fixture) == requests
  end

  defp snapshot_event(pid, thread, expected, summary, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    match =
      notification(events, "thread/settings/updated", fn params ->
        params["threadId"] == thread and params["threadSettings"]["summary"] == summary
      end)

    if match do
      assert Map.fetch!(match["threadSettings"], "personality") === expected
    else
      assert System.monotonic_time(:millisecond) < deadline, "applied settings snapshot deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        10 -> :ok
      end

      snapshot_event(pid, thread, expected, summary, events, deadline)
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
               %{"name" => "owned_turn_personality", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
