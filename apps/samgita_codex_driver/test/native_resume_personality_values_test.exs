defmodule SamgitaCodexDriver.NativeResumePersonalityValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @literal """
  Owned resume personality base λ
  # Personality
  Owned original style {{ personality }}
  ## Details
  Owned original style detail.
  # Rules
  Owned inherited rule.
  """
  @inherited """
  Owned resume personality base λ
  # Rules
  Owned inherited rule.
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

      if wire["method"] == "thread/resume" do
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

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

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

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "subscribed warm resume ignores personality overrides and retains existing instructions",
       ctx do
    pid = start(ctx)
    thread = new_thread(ctx, pid)
    original = complete(ctx, pid, thread, "owned-warm-original", 1)
    snapshot(ctx, pid, thread, "none", "concise")

    turns =
      Enum.reduce(
        Enum.with_index(
          [
            %{},
            %{"personality" => nil},
            %{"personality" => "none"},
            %{"personality" => "friendly"}
          ],
          1
        ),
        [original],
        fn {extra, index}, prior ->
          # Keep the original connection subscribed throughout. This is rejoin,
          # not the idle cache replacement branch of a subscriber-free thread.
          assert call(pid, "thread/loaded/list", %{})["data"] == [thread]
          assert_history(resume(ctx, pid, thread, extra)["thread"], thread, prior)
          summary = if rem(index, 2) == 1, do: "detailed", else: "concise"
          snapshot(ctx, pid, thread, "none", summary)
          turn = complete(ctx, pid, thread, "owned-warm-followup-#{index}", index + 1)
          expected = prior ++ [turn]
          assert_history(read(pid, thread), thread, expected)
          expected
        end
      )

    assert length(Enum.uniq(turns)) == 5
    assert_functional_state(ctx, pid, 5)
    assert File.read!(ctx.config) == ctx.config_bytes
    assert :ok = Session.close(pid)
  end

  test "cold resume uses configured fallback for omission null and explicit overrides without rewriting base",
       ctx do
    first = start(ctx)

    parents =
      for {{label, extra, personality}, index} <- Enum.with_index(cold_cases(), 1) do
        thread = new_thread(ctx, first)
        turn = complete(ctx, first, thread, "owned-cold-original-#{label}", index)
        assert_history(read(first, thread), thread, [turn])
        %{thread: thread, original: turn, label: label, extra: extra, personality: personality}
      end

    {current, completed} =
      Enum.reduce(Enum.with_index(parents, 1), {first, []}, fn {parent, index}, {prior, rows} ->
        count = 4 + index - 1
        cold = restart(ctx, prior, count)
        assert call(cold, "thread/loaded/list", %{})["data"] == []

        assert_history(
          resume(ctx, cold, parent.thread, parent.extra)["thread"],
          parent.thread,
          [parent.original]
        )

        # Each parent was saved with configured summary auto and no settings
        # updates. A distinct concise update exposes an independent live snapshot
        # without supplying personality or submitting a turn.
        snapshot(ctx, cold, parent.thread, parent.personality, "concise")

        turn =
          complete(ctx, cold, parent.thread, "owned-cold-followup-#{parent.label}", count + 1)

        assert_history(read(cold, parent.thread), parent.thread, [parent.original, turn])
        {cold, rows ++ [{parent.thread, [parent.original, turn]}]}
      end)

    for {thread, turns} <- completed, do: assert_history(read(current, thread), thread, turns)
    assert length(Enum.uniq(Enum.map(parents, & &1.thread))) == 4
    assert_functional_state(ctx, current, 8)
    assert File.read!(ctx.config) == ctx.config_bytes
    assert :ok = Session.close(current)
  end

  defp cold_cases do
    [
      {"omitted", %{}, "pragmatic"},
      {"null", %{"personality" => nil}, "pragmatic"},
      {"friendly", %{"personality" => "friendly"}, "friendly"},
      {"none", %{"personality" => "none"}, "none"}
    ]
  end

  defp new_thread(ctx, pid) do
    TurnFixture.thread(ctx, pid, %{
      "personality" => "none",
      "historyMode" => "legacy",
      "approvalPolicy" => "never",
      "sandbox" => "danger-full-access"
    })
  end

  defp resume(ctx, pid, thread, extra) do
    requests = ModelFixture.requests(ctx.fixture)
    before = length(Agent.get(ctx.capture, & &1))
    params = Map.put(extra, "threadId", thread)
    response = call(pid, "thread/resume", params)
    sent = Agent.get(ctx.capture, & &1)
    assert length(sent) == before + 1
    assert List.last(sent)["params"] === params
    assert ModelFixture.requests(ctx.fixture) == requests
    response
  end

  defp read(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp assert_history(saved, thread, turns) do
    assert saved["id"] == thread
    assert Enum.map(saved["turns"], & &1["id"]) == turns
    assert Enum.all?(saved["turns"], &(&1["status"] == "completed"))
  end

  defp complete(ctx, pid, thread, marker, count) do
    turn = TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => marker}])
    collect_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == count
    request = List.last(requests)
    assert request["model"] == "mock-model"
    refute Map.has_key?(request, "instructions")

    assert %{
             "type" => "message",
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @inherited}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
    # Observe completed stored history without assuming the read flushes it.
    assert Enum.any?(read(pid, thread)["turns"], &(&1["id"] == turn))
    turn
  end

  defp collect_turn(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    completed =
      notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if completed do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               completed

      refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    else
      assert System.monotonic_time(:millisecond) < deadline, "native resume turn deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during resume turn")
      after
        20 -> :ok
      end

      collect_turn(pid, thread, turn, events, deadline)
    end
  end

  defp snapshot(ctx, pid, thread, personality, summary) do
    requests = ModelFixture.requests(ctx.fixture)

    assert call(pid, "thread/settings/update", %{"threadId" => thread, "summary" => summary}) ==
             %{}

    snapshot_event(
      pid,
      thread,
      personality,
      summary,
      [],
      System.monotonic_time(:millisecond) + 5000
    )

    assert ModelFixture.requests(ctx.fixture) == requests
  end

  defp snapshot_event(pid, thread, personality, summary, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    found =
      notification(events, "thread/settings/updated", fn params ->
        params["threadId"] == thread and params["threadSettings"]["summary"] == summary
      end)

    if found do
      assert Map.fetch!(found["threadSettings"], "personality") === personality
    else
      assert System.monotonic_time(:millisecond) < deadline, "native resume snapshot deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during resume snapshot")
      after
        10 -> :ok
      end

      snapshot_event(pid, thread, personality, summary, events, deadline)
    end
  end

  defp assert_functional_state(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp restart(ctx, pid, count) do
    assert_functional_state(ctx, pid, count)
    original = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(original)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{original}")
    cold = start(ctx)
    replacement = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(replacement) and replacement != original
    assert_functional_state(ctx, cold, count)
    cold
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
               %{"name" => "owned_resume_personality", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
