defmodule SamgitaCodexDriver.NativeTokenContextWindowTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/thread_event_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @text "Owned stream 1 é🙂\nDone."

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, tags.model_overrides)
    ctx
  end

  @tag model_overrides: %{
         "context_window" => 100_003,
         "max_context_window" => 200_009,
         "effective_context_window_percent" => 73
       },
       expected_window: 73_002
  test "explicit context window wins and effective percentage uses integer division", ctx do
    qualify(ctx)
  end

  @tag model_overrides: %{
         "max_context_window" => 200_009,
         "effective_context_window_percent" => 73
       },
       expected_window: 146_006
  test "omitted context window falls back to the independently prescribed maximum", ctx do
    qualify(ctx)
  end

  @tag model_overrides: %{"effective_context_window_percent" => 73}, expected_window: nil
  test "absent catalog windows produce an explicitly present null usage window", ctx do
    qualify(ctx)
  end

  defp qualify(ctx) do
    pid = start(ctx)
    config = Path.join(ctx.fixture.codex_home, "config.toml")
    config_bytes = File.read!(config)

    thread =
      TurnFixture.thread(ctx, pid, %{
        "historyMode" => "paginated",
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    marker = "Owned token context window"
    turn = TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => marker}])
    events = collect(pid, [], deadline(20_000))
    usages = params(events, "thread/tokenUsage/updated")
    assert usages != []

    expected = %{
      "inputTokens" => 7,
      "cachedInputTokens" => 3,
      "cacheWriteInputTokens" => 0,
      "outputTokens" => 11,
      "reasoningOutputTokens" => 2,
      "totalTokens" => 18
    }

    for usage <- usages do
      assert Map.fetch!(usage, "threadId") === thread
      assert Map.fetch!(usage, "turnId") === turn
      tokens = Map.fetch!(usage, "tokenUsage")
      assert Map.fetch!(tokens, "last") === expected
      assert Map.fetch!(tokens, "total") === expected
      assert Map.fetch!(tokens, "modelContextWindow") === Map.fetch!(ctx, :expected_window)
    end

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = saved["turns"]
    assert Enum.find(items, &(&1["type"] == "agentMessage"))["text"] === @text
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert Enum.any?(TurnFixture.provider_content(ctx.fixture), &(&1["text"] == marker))
    assert File.read!(config) === config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp collect(pid, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "token usage event count exceeded its bound"

    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576,
           "token usage event bytes exceeded their bound"

    if params(events, "turn/completed") != [] do
      events
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native token usage deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during token usage")
      after
        10 -> :ok
      end

      collect(pid, events, until)
    end
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
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

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_token_context_window", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true
               }
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
end
