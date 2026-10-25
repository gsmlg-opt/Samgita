defmodule SamgitaCodexDriver.NativeSleepItemEventsTest do
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

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/sleep_item_events_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned sleep item fixture instructions."
  @marker "Owned sleep item λ🙂"

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

    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n" <>
        ~s(\n[features.sleep_tool]\nenabled = true\nmode = "always_on"\n) <>
        ~s(\n[features.current_time_reminder]\nenabled = false\nclock_source = "system"\n)
    )

    inputs =
      Map.new([config, Path.join(ctx.fixture.codex_home, "turn-models.json")], fn path ->
        {path, snapshot(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "native clock.sleep retains its requested duration through events and first cold selection",
       ctx do
    warm = start(ctx)
    warm_native = native_id(warm)

    thread =
      call(warm, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    before_ms = System.system_time(:millisecond)

    turn =
      call(warm, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(warm, thread, turn, [], deadline(20_000))
    after_ms = System.system_time(:millisecond)
    expected = assert_live(events, thread, turn, before_ms, after_ms)
    assert_provider(ctx, thread, turn, before_ms, after_ms)
    saved = assert_history(warm, thread, turn)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    retained =
      Map.merge(ctx.inputs, %{
        path => snapshot(path),
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => Enum.map(items(), & &1["id"])}
    assert_selection(warm, query, expected)
    assert_retained(ctx, warm, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # First content read after replacement, before resume or full history hydration.
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected)
    cold_saved = assert_history(cold, thread, turn)
    assert Map.fetch!(cold_saved, "turns") === Map.fetch!(saved, "turns")
    assert Map.fetch!(cold_saved, "path") == path
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp items do
    [%{"type" => "sleep", "id" => "owned-sleep-item", "durationMs" => 1}]
  end

  defp assert_live(events, thread, turn, before_ms, after_ms) do
    started = sleep_events(events, "item/started")
    finished = sleep_events(events, "item/completed")
    ids = Enum.map(items(), & &1["id"])
    assert Enum.map(started, & &1["item"]["id"]) == ids
    assert Enum.map(finished, & &1["item"]["id"]) == ids

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          item = event.wire["params"]["item"],
          item["type"] == "sleep",
          do: {event.wire["method"], item["id"]}

    assert order == Enum.flat_map(ids, &[{"item/started", &1}, {"item/completed", &1}])

    entries =
      for {item, begin, finish} <- Enum.zip([items(), started, finished]) do
        began_at = Map.fetch!(begin, "startedAtMs")
        ended_at = Map.fetch!(finish, "completedAtMs")
        assert is_integer(began_at) and is_integer(ended_at)
        assert before_ms <= began_at and began_at <= ended_at and ended_at <= after_ms

        assert begin === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => item,
                 "startedAtMs" => began_at
               }

        assert finish === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => item,
                 "completedAtMs" => ended_at
               }

        %{
          "turnId" => turn,
          "item" => item,
          "startedAtMs" => began_at,
          "completedAtMs" => ended_at
        }
      end

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    %{"data" => entries}
  end

  defp assert_provider(ctx, thread, turn, before_ms, after_ms) do
    assert [first, continued] = ModelFixture.requests(ctx.fixture)

    for request <- [first, continued] do
      assert Map.fetch!(request, "model") == "mock-model"

      assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
               JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

      assert [clock] =
               Enum.filter(
                 request["tools"],
                 &(&1["type"] == "namespace" and &1["name"] == "clock")
               )

      assert [tool] = Enum.filter(clock["tools"], &(&1["name"] == "sleep"))
      assert tool["type"] == "function" and tool["strict"] == false

      assert tool["description"] ==
               "Pause execution for a specified duration. The sleep ends early when new input arrives for the active turn. Returns the elapsed wall-clock time."

      assert tool["parameters"] == %{
               "type" => "object",
               "properties" => %{
                 "duration_ms" => %{
                   "type" => "number",
                   "description" =>
                     "How long to sleep in milliseconds. Must be between 1 and 43200000."
                 }
               },
               "required" => ["duration_ms"],
               "additionalProperties" => false
             }

      developer = hd(request["input"])
      id = Map.fetch!(developer, "id")
      assert is_binary(id) and String.starts_with?(id, "msg_")

      assert developer == %{
               "type" => "message",
               "id" => id,
               "role" => "developer",
               "content" => [%{"type" => "input_text", "text" => @instructions}]
             }

      texts =
        for item <- request["input"],
            item["role"] == "user",
            part <- item["content"],
            do: part["text"]

      assert Enum.count(texts, &(&1 == @marker)) == 1
    end

    assert Enum.filter(first["input"], &(&1["type"] in ["function_call", "function_call_output"])) ==
             []

    assert [native_call] = Enum.filter(continued["input"], &(&1["type"] == "function_call"))

    assert Map.take(native_call, ["type", "namespace", "name", "call_id", "arguments"]) == %{
             "type" => "function_call",
             "namespace" => "clock",
             "name" => "sleep",
             "call_id" => "owned-sleep-item",
             "arguments" => ~s({"duration_ms":1})
           }

    assert_native_id(Map.fetch!(native_call, "id"), "fc")
    assert [output] = Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))
    id = Map.fetch!(output, "id")
    assert_native_id(id, "fco")
    text = Map.fetch!(output, "output")

    assert [_, elapsed_text] =
             Regex.run(~r/\AWall time: ([0-9]+\.[0-9]{4}) seconds\nSleep completed\.\z/, text)

    assert {elapsed, ""} = Float.parse(elapsed_text)
    assert elapsed >= 0.001
    assert elapsed <= (after_ms - before_ms) / 1_000 + 0.001

    assert output == %{
             "type" => "function_call_output",
             "id" => id,
             "call_id" => "owned-sleep-item",
             "output" => "Wall time: #{elapsed_text} seconds\nSleep completed."
           }
  end

  defp assert_native_id(id, prefix) do
    assert is_binary(id)

    assert Regex.match?(
             ~r/\A#{prefix}_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/,
             id
           )
  end

  defp assert_history(pid, thread, turn) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => rows}] =
             saved["turns"]

    assert Enum.filter(rows, &(&1["type"] == "sleep")) === items()

    assert [%{"text" => "Deterministic local fixture answer"}] =
             Enum.filter(rows, &(&1["type"] == "agentMessage"))

    assert [%{"content" => [%{"type" => "text", "text" => @marker}]}] =
             Enum.filter(rows, &(&1["type"] == "userMessage"))

    saved
  end

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === expected

    for entry <- expected["data"] do
      assert call(pid, "thread/items/read", %{query | "itemIds" => [entry["item"]["id"]]}) ===
               %{"data" => [entry]}
    end

    duplicated = [
      "owned-absent-sleep-item" | Enum.reverse(query["itemIds"]) ++ query["itemIds"]
    ]

    assert call(pid, "thread/items/read", %{query | "itemIds" => duplicated}) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-sleep-item"]}) ===
             %{"data" => []}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, bytes} <- inputs, do: assert(snapshot(path) === bytes)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp collect(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         params(events, "turn/completed"),
         &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native sleep-item turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected sleep-item gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp sleep_events(events, method),
    do: Enum.filter(params(events, method), &(&1["item"]["type"] == "sleep"))

  defp call(pid, method, params) do
    id = "owned-sleep-event-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    result
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp native_id(pid) do
    id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(id)
    assert hash(File.read!("/proc/#{id}/exe")) == @binary_sha
    id
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
               "RUST_LOG" => "off",
               "NO_COLOR" => "1"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_sleep_item_events", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
