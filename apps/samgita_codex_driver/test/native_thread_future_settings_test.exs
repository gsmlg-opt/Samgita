defmodule SamgitaCodexDriver.NativeThreadFutureSettingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture,
    only: [call: 3, upstream_error: 4, thread: 3, start_turn: 3, finish_turn: 3, notification: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/active_turn_settings_fixture.py", __DIR__)
  @model_a "step-settings-a"
  @model_b "step-settings-b"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Synthetic lookup that waits for an explicit test response",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-future-settings-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "active")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    next_cwd = Path.join(root, "future-workspace")
    Enum.each([next_cwd, Path.join(root, "tmp")], &File.mkdir!/1)
    %{binary: binary, root: root, fixture: fixture, next_cwd: next_cwd}
  end

  test "thread publication changes future capture while the active turn retains its settings and environment",
       ctx do
    {pid, id, turn, tool, events} = active(ctx)

    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "model" => @model_b,
             "effort" => "high",
             "summary" => "detailed",
             "cwd" => ctx.next_cwd
           }) == %{}

    # The response acknowledges queueing. Only the matching applied snapshot is
    # the barrier before dependent requests or assertions about future defaults.
    events = await_settings(pid, id, ctx.next_cwd, events, deadline())
    assert_pending(ctx, pid, id, turn, tool)

    assert call(pid, "thread/settings/update", %{"threadId" => id}) == %{}

    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "model" => nil,
             "effort" => nil,
             "summary" => nil,
             "cwd" => nil
           }) == %{}

    # Both requests are no-ops; do not wait for notifications they need not emit.
    assert_pending(ctx, pid, id, turn, tool)
    finish_active(ctx, pid, id, turn, tool, events)
    future = start_turn(pid, id, text("Use the future synthetic settings"))
    finish_turn(pid, id, future)

    assert [first, continued, next] = ModelFixture.requests(ctx.fixture)
    assert_initial(first)
    assert_initial(continued)
    assert environment_texts(continued) == environment_texts(first)
    assert_environment(List.last(environment_texts(first)), ctx.fixture.workspace)
    assert next["model"] == @model_b
    assert next["reasoning"] == %{"effort" => "high", "summary" => "detailed"}
    assert_environment(List.last(environment_texts(next)), ctx.next_cwd)
    assert_idle(pid)
  end

  test "native malformed settings and unknown targets preserve the pending tool and future defaults",
       ctx do
    {pid, id, turn, tool, events} = active(ctx)

    for invalid <- [
          %{},
          %{"threadId" => nil},
          %{"threadId" => 17},
          %{"threadId" => id, "model" => 17},
          %{"threadId" => id, "effort" => 17},
          %{"threadId" => id, "summary" => 17},
          %{"threadId" => id, "summary" => "unsupported"},
          %{"threadId" => id, "cwd" => 17}
        ] do
      error = upstream_error(pid, "thread/settings/update", invalid, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert_pending(ctx, pid, id, turn, tool)
    end

    malformed =
      upstream_error(pid, "thread/settings/update", %{"threadId" => "invalid-thread"},
        validation: :wire
      )

    assert malformed["code"] == -32_600
    assert String.starts_with?(malformed["message"], "invalid thread id:")

    missing = "00000000-0000-4000-8000-000000000001"

    assert upstream_error(pid, "thread/settings/update", %{"threadId" => missing},
             validation: :wire
           ) == %{
             "code" => -32_600,
             "message" => "thread not found: #{missing}"
           }

    assert_pending(ctx, pid, id, turn, tool)
    finish_active(ctx, pid, id, turn, tool, events)
    future = start_turn(pid, id, text("Use the unchanged synthetic defaults"))
    finish_turn(pid, id, future)
    assert [first, continued, next] = ModelFixture.requests(ctx.fixture)
    Enum.each([first, continued, next], &assert_initial/1)
    assert environment_texts(continued) == environment_texts(first)
    assert_environment(List.last(environment_texts(next)), ctx.fixture.workspace)
    assert_idle(pid)
  end

  defp active(ctx) do
    pid = start(ctx)
    id = thread(ctx, pid, %{"model" => @model_a, "dynamicTools" => [@lookup]})
    turn = start_turn(pid, id, text("Initial synthetic future-settings input"))
    {tool, events} = await_tool(pid, [], deadline())
    assert_pending(ctx, pid, id, turn, tool)
    assert [first] = ModelFixture.requests(ctx.fixture)
    assert_initial(first)
    {pid, id, turn, tool, events}
  end

  defp await_tool(pid, events, until) do
    events = drain(pid, events)
    refute notification(events, "turn/completed")

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] -> {tool, events}
      [] -> wait(pid, until, fn -> await_tool(pid, events, until) end)
      _ -> flunk("Unexpected additional native interaction")
    end
  end

  defp await_settings(pid, id, cwd, events, until) do
    events = drain(pid, events)
    refute notification(events, "turn/completed")

    matching =
      Enum.filter(events, fn event ->
        event.wire["method"] == "thread/settings/updated" and
          event.wire["params"]["threadId"] == id and
          event.wire["params"]["threadSettings"]["model"] == @model_b
      end)

    case matching do
      [event] ->
        settings = event.wire["params"]["threadSettings"]
        assert settings["modelProvider"] == "fixture"
        assert settings["effort"] == "high"
        assert settings["summary"] == "detailed"
        assert settings["cwd"] == cwd
        events

      [] ->
        wait(pid, until, fn -> await_settings(pid, id, cwd, events, until) end)

      _ ->
        flunk("Unexpected duplicate applied settings snapshot")
    end
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid)
    events ++ incoming
  end

  defp wait(pid, until, next) do
    remaining = max(until - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex_driver, ^pid, :events_available} ->
        next.()

      {:codex_driver, ^pid, {:gap, _}} ->
        flunk("Unexpected event gap awaiting native settings evidence")
    after
      remaining -> flunk("Native settings evidence deadline")
    end
  end

  defp assert_pending(ctx, pid, id, turn, tool) do
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert tool.kind == :server_request
    assert tool.wire["method"] == "item/tool/call"
    assert is_integer(tool.wire["id"]) or is_binary(tool.wire["id"])
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => id,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }
  end

  defp finish_active(ctx, pid, id, turn, tool, events) do
    assert_pending(ctx, pid, id, turn, tool)

    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok,
                %{
                  "contentItems" => [
                    %{"type" => "inputText", "text" => "Synthetic lookup completed"}
                  ],
                  "success" => true
                }}
             )

    events = events ++ finish_turn(pid, id, turn)

    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == id
      assert params["turn"]["id"] == turn
    end

    assert [_, continued] = ModelFixture.requests(ctx.fixture)
    assert [output] = Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "fixture-call-1"
    assert output["output"] == "Synthetic lookup completed"
    assert_idle(pid)
  end

  defp environment_texts(request) do
    for item <- request["input"],
        item["role"] == "user",
        content <- Map.get(item, "content", []),
        value = content["text"],
        is_binary(value),
        String.starts_with?(value, "<environment_context>"),
        do: value
  end

  defp assert_environment(value, cwd) do
    assert is_binary(value)
    assert value =~ "<cwd>#{cwd}</cwd>"
    assert value =~ "<workspace_roots><root>#{cwd}</root></workspace_roots>"
  end

  defp assert_initial(request) do
    assert request["model"] == @model_a
    assert request["reasoning"] == %{"effort" => "low", "summary" => "concise"}
    refute Map.has_key?(request, "service_tier")
  end

  defp assert_idle(pid),
    do: assert(%{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid))

  defp deadline, do: System.monotonic_time(:millisecond) + 10_000
  defp text(value), do: [%{"type" => "text", "text" => value}]

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: ["app-server", "--listen", "stdio://"],
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
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
               %{"name" => "samgita_future_settings", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
