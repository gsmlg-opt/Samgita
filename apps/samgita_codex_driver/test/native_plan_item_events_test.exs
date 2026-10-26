defmodule SamgitaCodexDriver.NativePlanItemEventsTest do
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
  @script Path.expand("../../../scripts/codex/plan_item_events_fixture.py", __DIR__)
  @streamed_script Path.expand("../../../scripts/codex/streamed_plan_events_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned Plan item fixture instructions."
  @marker "Owned proposed Plan event λ🙂"
  @plan "# Owned next plan λ🙂\n- first\n- second\n"
  @streamed_final "# Owned final λ🙂\n- accepted source\n"
  @streamed_deltas ["# Draft λ🙂\n", "- streamed\n"]
  @default_text "<proposed_plan>\n# Owned next plan λ🙂\n- first\n- second\n</proposed_plan>"
  @mode_instructions "Owned collaboration input alias instructions λ🙂."

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    script = if tags[:plan_profile] == :streamed, do: @streamed_script, else: @script
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", script)

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
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [config, Path.join(ctx.fixture.codex_home, "turn-models.json"), @script, script],
        fn path ->
          {path, snapshot(path)}
        end
      )

    Map.merge(ctx, %{inputs: inputs, plan_profile: tags[:plan_profile]})
  end

  test "native proposed Plan keeps literal identity and trailing newline through first cold read",
       ctx do
    qualify(ctx, @plan)
  end

  @tag plan_profile: :streamed
  test "native Plan streams exact draft deltas while final text governs warm and first cold history",
       ctx do
    qualify(ctx, @streamed_final)
  end

  for mode <- ~w(default code pair_programming execute custom) do
    @tag collaboration_input: mode
    test "native collaboration input #{mode} applies Default and retains literal assistant history",
         ctx do
      qualify_default(ctx, ctx.collaboration_input)
    end
  end

  defp qualify_default(ctx, mode) do
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
    update_mode(ctx, warm, thread, "plan", "plan")
    update_mode(ctx, warm, thread, mode, "default")
    update_mode(ctx, warm, thread, "plan", "plan")
    before_ms = System.system_time(:millisecond)

    turn =
      call(warm, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}],
        "collaborationMode" => collaboration(mode)
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(warm, thread, turn, [], deadline(20_000))

    expected =
      assert_default_live(events, thread, turn, before_ms, System.system_time(:millisecond))

    assert_provider(ctx, thread, turn)
    [request] = ModelFixture.requests(ctx.fixture)

    assert Enum.any?(request["input"], fn row ->
             row["role"] == "developer" and
               Enum.any?(row["content"], &String.contains?(&1["text"] || "", @mode_instructions))
           end)

    saved = assert_default_history(warm, thread, turn)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    records = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert [context] = for(row <- records, row["type"] == "turn_context", do: row["payload"])
    assert context["turn_id"] == turn
    assert context["collaboration_mode"] === collaboration("default")

    retained =
      Map.merge(ctx.inputs, %{
        path => snapshot(path),
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    [row] = expected["data"]
    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => [row["item"]["id"]]}
    assert_selection(warm, query, expected)
    assert_retained(ctx, warm, retained)
    close(warm, warm_native)
    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected)
    cold_saved = assert_default_history(cold, thread, turn)
    assert Map.fetch!(cold_saved, "turns") === Map.fetch!(saved, "turns")
    assert Map.fetch!(cold_saved, "path") == path
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp collaboration(mode) do
    %{
      "mode" => mode,
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => nil,
        "developer_instructions" => @mode_instructions
      }
    }
  end

  defp update_mode(ctx, pid, thread, input, canonical) do
    assert {:ok, _prior} = Session.drain(pid)

    assert call(pid, "thread/settings/update", %{
             "threadId" => thread,
             "collaborationMode" => collaboration(input)
           }) == %{}

    await_mode(ctx, pid, thread, canonical, [], deadline(5_000))
  end

  defp await_mode(ctx, pid, thread, mode, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert ModelFixture.requests(ctx.fixture) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    refute Enum.any?(events, &(&1.kind == :server_request))

    matches =
      for event <- events,
          event.wire["method"] == "thread/settings/updated",
          event.wire["params"]["threadId"] == thread,
          do: event.wire["params"]["threadSettings"]

    case matches do
      [settings] ->
        assert settings["collaborationMode"] === collaboration(mode)
        assert settings["model"] == "mock-model"
        assert settings["modelProvider"] == "fixture"
        assert settings["cwd"] == ctx.fixture.workspace

      [] ->
        assert System.monotonic_time(:millisecond) < until, "native applied-mode deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected applied-mode gap")
        after
          10 -> :ok
        end

        await_mode(ctx, pid, thread, mode, events, until)

      _ ->
        flunk("Duplicate native applied-mode snapshot")
    end
  end

  defp assert_default_live(events, thread, turn, before_ms, after_ms) do
    assert [begin] = assistant_events(events, "item/started")
    assert [finish] = assistant_events(events, "item/completed")
    began_at = Map.fetch!(begin, "startedAtMs")
    ended_at = Map.fetch!(finish, "completedAtMs")
    assert is_integer(began_at) and is_integer(ended_at)
    assert before_ms <= began_at and began_at <= ended_at and ended_at <= after_ms
    assert %{"threadId" => ^thread, "turnId" => ^turn} = begin
    assert %{"threadId" => ^thread, "turnId" => ^turn} = finish
    assert begin["item"]["id"] == "owned-proposed-plan-message"
    assert finish["item"]["id"] == begin["item"]["id"]
    assert finish["item"]["text"] === @default_text
    assert finish["item"]["phase"] == "final_answer"
    assert plan_events(events, "item/started") == []
    assert plan_events(events, "item/completed") == []
    assert params(events, "item/plan/delta") == []

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => finish["item"],
          "startedAtMs" => began_at,
          "completedAtMs" => ended_at
        }
      ]
    }
  end

  defp assistant_events(events, method),
    do: Enum.filter(params(events, method), &(&1["item"]["type"] == "agentMessage"))

  defp assert_default_history(pid, thread, turn) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => rows}] =
             saved["turns"]

    assert [assistant] = Enum.filter(rows, &(&1["type"] == "agentMessage"))
    assert assistant["id"] == "owned-proposed-plan-message"
    assert assistant["text"] === @default_text
    assert assistant["phase"] == "final_answer"
    refute Enum.any?(rows, &(&1["type"] == "plan"))

    assert [%{"content" => [%{"type" => "text", "text" => @marker}]}] =
             Enum.filter(rows, &(&1["type"] == "userMessage"))

    saved
  end

  defp qualify(ctx, plan) do
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
        "input" => [%{"type" => "text", "text" => @marker}],
        "collaborationMode" => %{
          "mode" => "plan",
          "settings" => %{
            "model" => "mock-model",
            "reasoning_effort" => nil,
            "developer_instructions" => nil
          }
        }
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(warm, thread, turn, [], deadline(20_000))
    after_ms = System.system_time(:millisecond)
    expected = assert_live(events, thread, turn, before_ms, after_ms, plan)
    assert_deltas(ctx, events, thread, turn, before_ms, after_ms, plan)
    assert_provider(ctx, thread, turn)
    saved = assert_history(warm, thread, turn, plan)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    retained =
      Map.merge(ctx.inputs, %{
        path => snapshot(path),
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => [turn <> "-plan"]}
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
    cold_saved = assert_history(cold, thread, turn, plan)
    assert Map.fetch!(cold_saved, "turns") === Map.fetch!(saved, "turns")
    assert Map.fetch!(cold_saved, "path") == path
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp item(turn, plan), do: %{"type" => "plan", "id" => turn <> "-plan", "text" => plan}

  defp assert_live(events, thread, turn, before_ms, after_ms, plan) do
    assert [begin] = plan_events(events, "item/started")
    assert [finish] = plan_events(events, "item/completed")
    began_at = Map.fetch!(begin, "startedAtMs")
    ended_at = Map.fetch!(finish, "completedAtMs")
    assert is_integer(began_at) and is_integer(ended_at)
    assert before_ms <= began_at and began_at <= ended_at and ended_at <= after_ms

    assert begin === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => %{"type" => "plan", "id" => turn <> "-plan", "text" => ""},
             "startedAtMs" => began_at
           }

    assert finish === %{
             "threadId" => thread,
             "turnId" => turn,
             "item" => item(turn, plan),
             "completedAtMs" => ended_at
           }

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          event.wire["params"]["item"]["type"] == "plan",
          do: event.wire["method"]

    assert order == ["item/started", "item/completed"]

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => item(turn, plan),
          "startedAtMs" => began_at,
          "completedAtMs" => ended_at
        }
      ]
    }
  end

  defp assert_deltas(ctx, events, thread, turn, before_ms, after_ms, plan) do
    deltas = Enum.filter(events, &(&1.wire["method"] == "item/plan/delta"))

    if ctx.plan_profile == :streamed do
      assert Enum.map(deltas, & &1.wire["params"]) ===
               Enum.map(@streamed_deltas, fn delta ->
                 %{
                   "threadId" => thread,
                   "turnId" => turn,
                   "itemId" => turn <> "-plan",
                   "delta" => delta
                 }
               end)

      for event <- deltas do
        assert event.kind == :notification
        assert Enum.sort(Map.keys(event.wire)) == ~w(emittedAtMs method params)
        emitted_at = Map.fetch!(event.wire, "emittedAtMs")
        assert is_integer(emitted_at) and before_ms <= emitted_at and emitted_at <= after_ms
      end

      lifecycle =
        for event <- events,
            event.wire["method"] == "item/plan/delta" or
              (event.wire["method"] in ["item/started", "item/completed"] and
                 event.wire["params"]["item"]["type"] == "plan"),
            do: event.wire["method"]

      assert lifecycle == ["item/started", "item/plan/delta", "item/plan/delta", "item/completed"]
      assert plan === @streamed_final
      refute Enum.map_join(deltas, & &1.wire["params"]["delta"]) == plan
    else
      assert deltas == []
      assert plan === @plan
    end
  end

  defp assert_provider(ctx, thread, turn) do
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    texts =
      for row <- request["input"],
          row["role"] == "user",
          part <- row["content"],
          do: part["text"]

    assert Enum.count(texts, &(&1 == @marker)) == 1
  end

  defp assert_history(pid, thread, turn, plan) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => rows}] =
             saved["turns"]

    assert Enum.filter(rows, &(&1["type"] == "plan")) === [item(turn, plan)]
    refute Enum.any?(rows, &(&1["text"] == Enum.join(@streamed_deltas)))

    assert [%{"content" => [%{"type" => "text", "text" => @marker}]}] =
             Enum.filter(rows, &(&1["type"] == "userMessage"))

    saved
  end

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === expected
    [id] = query["itemIds"]

    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => ["owned-absent-plan-item", id, id]
           }) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-plan-item"]}) ===
             %{"data" => []}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, bytes} <- inputs, do: assert(snapshot(path) === bytes)
    assert length(ModelFixture.requests(ctx.fixture)) == 1
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
      assert System.monotonic_time(:millisecond) < until, "native Plan-item turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected Plan-item gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp plan_events(events, method),
    do: Enum.filter(params(events, method), &(&1["item"]["type"] == "plan"))

  defp call(pid, method, params) do
    id = "owned-plan-item-#{System.unique_integer([:positive, :monotonic])}"
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
               %{"name" => "owned_plan_item_events", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
