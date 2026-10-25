defmodule SamgitaCodexDriver.NativeCompactionItemSelectionTest do
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
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned compaction item fixture instructions."
  @marker "Owned compaction seed λ🙂"
  @compact_prompt "Owned explicit compaction summary prompt λ🙂"
  @answer "Deterministic local fixture answer"

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
      "compact_prompt = #{JSON.encode!(@compact_prompt)}\n" <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new([config, Path.join(ctx.fixture.codex_home, "turn-models.json")], fn path ->
        {path, snapshot(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "native local compaction item survives first cold selective read without execution", ctx do
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

    seed =
      call(warm, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(seed) and byte_size(seed) > 0
    seeded = collect(warm, thread, seed, [], deadline(20_000))

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^seed, "status" => "completed"}}] =
             params(seeded, "turn/completed")

    assert [%{"item" => %{"type" => "agentMessage", "text" => @answer}}] =
             Enum.filter(
               params(seeded, "item/completed"),
               &(&1["item"]["type"] == "agentMessage")
             )

    assert [_seed_request] = ModelFixture.requests(ctx.fixture)
    before_ms = System.system_time(:millisecond)
    assert call(warm, "thread/compact/start", %{"threadId" => thread}) == %{}
    events = collect(warm, thread, nil, [], deadline(20_000))
    after_ms = System.system_time(:millisecond)
    turn = assert_provider(ctx, thread, seed)
    refute turn == seed
    expected = assert_live(events, thread, turn, before_ms, after_ms)
    saved = assert_history(warm, thread, turn, seed, expected)
    path = Map.fetch!(saved, "path")
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular

    retained =
      Map.merge(ctx.inputs, %{
        path => snapshot(path),
        ctx.fixture.requests => snapshot(ctx.fixture.requests)
      })

    item_id = hd(expected["data"])["item"]["id"]
    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => [item_id]}
    assert_selection(warm, query, expected, seed)
    assert_retained(ctx, warm, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # First content read after replacement, before resume or full history hydration.
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected, seed)
    cold_saved = assert_history(cold, thread, turn, seed, expected)
    assert Map.fetch!(cold_saved, "turns") === Map.fetch!(saved, "turns")
    assert Map.fetch!(cold_saved, "path") == path
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp assert_live(events, thread, turn, before_ms, after_ms) do
    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn}}] =
             params(events, "turn/started")

    assert [begin] = compaction_events(events, "item/started")
    assert [finish] = compaction_events(events, "item/completed")
    item_id = Map.fetch!(begin["item"], "id")
    assert_uuid_v7(item_id, before_ms, after_ms)
    item = %{"id" => item_id, "type" => "contextCompaction"}
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

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          event.wire["params"]["item"]["type"] == "contextCompaction",
          do: event.wire["method"]

    assert order == ["item/started", "item/completed"]

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    %{
      "data" => [
        %{
          "turnId" => turn,
          "item" => item,
          "startedAtMs" => began_at,
          "completedAtMs" => ended_at
        }
      ]
    }
  end

  defp assert_provider(ctx, thread, seed) do
    assert [seed_request, compact_request] = ModelFixture.requests(ctx.fixture)

    assert %{"thread_id" => ^thread, "turn_id" => ^seed} = metadata(seed_request)
    assert %{"thread_id" => ^thread, "turn_id" => turn} = metadata(compact_request)
    assert is_binary(turn) and byte_size(turn) > 0

    for request <- [seed_request, compact_request] do
      assert Map.fetch!(request, "model") == "mock-model"
      assert Enum.count(texts(request), &(&1 == @marker)) == 1
    end

    assert Enum.count(texts(compact_request), &(&1 == @compact_prompt)) == 1
    assert Enum.count(texts(compact_request), &(&1 == @answer)) == 1
    refute Enum.any?(texts(seed_request), &(&1 == @compact_prompt))
    turn
  end

  defp metadata(request),
    do: JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

  defp texts(request),
    do: for(item <- request["input"], part <- Map.get(item, "content", []), do: part["text"])

  defp assert_history(pid, thread, turn, seed, expected) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"

    assert [%{"status" => "completed", "error" => nil}] =
             Enum.filter(saved["turns"], &(&1["id"] == turn))

    assert [%{"status" => "completed", "error" => nil}] =
             Enum.filter(saved["turns"], &(&1["id"] == seed))

    seed_items = for row <- saved["turns"], row["id"] == seed, item <- row["items"], do: item

    assert [%{"content" => [%{"type" => "text", "text" => @marker}]}] =
             Enum.filter(seed_items, &(&1["type"] == "userMessage"))

    assert [%{"text" => @answer}] =
             Enum.filter(seed_items, &(&1["type"] == "agentMessage"))

    selected = for row <- saved["turns"], row["id"] == turn, item <- row["items"], do: item

    assert Enum.filter(selected, &(&1["type"] == "contextCompaction")) ===
             [hd(expected["data"])["item"]]

    saved
  end

  defp assert_selection(pid, query, expected, seed) do
    assert call(pid, "thread/items/read", query) === expected
    [item_id] = query["itemIds"]

    assert call(pid, "thread/items/read", %{
             query
             | "itemIds" => ["owned-absent-compaction-item", item_id, item_id]
           }) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-compaction-item"]}) ===
             %{"data" => []}

    assert call(pid, "thread/items/read", %{query | "turnId" => seed}) === %{"data" => []}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, bytes} <- inputs, do: assert(snapshot(path) === bytes)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp assert_uuid_v7(id, before_ms, after_ms) do
    assert is_binary(id)

    assert Regex.match?(
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
             id
           )

    {created_at, ""} = id |> String.replace("-", "") |> String.slice(0, 12) |> Integer.parse(16)
    assert before_ms <= created_at and created_at <= after_ms
  end

  defp collect(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         params(events, "turn/completed"),
         &(&1["threadId"] == thread and (is_nil(turn) or &1["turn"]["id"] == turn))
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native compaction-item turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected compaction-item gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp compaction_events(events, method),
    do: Enum.filter(params(events, method), &(&1["item"]["type"] == "contextCompaction"))

  defp call(pid, method, params) do
    id = "owned-compaction-item-#{System.unique_integer([:positive, :monotonic])}"
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
               %{"name" => "owned_compaction_item_selection", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
