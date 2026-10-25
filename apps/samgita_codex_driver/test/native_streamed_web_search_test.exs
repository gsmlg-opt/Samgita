defmodule SamgitaCodexDriver.NativeStreamedWebSearchTest do
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
  @script Path.expand("../../../scripts/codex/streamed_web_search_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned streamed web item fixture instructions."
  @marker "Owned streamed web actions λ🙂"
  @answer "Deterministic local fixture answer"
  @page "https://streamed-web.synthetic.invalid/owned-page"

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
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      Map.new([config, Path.join(ctx.fixture.codex_home, "turn-models.json")], fn path ->
        {path, snapshot(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "streamed native web placeholders become final actions and survive first cold selection",
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
    assert_provider(ctx, thread, turn)
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

    # This is the first content read after native replacement. Do not resume or
    # hydrate history before requiring the final items instead of placeholders.
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
    [
      web_item("primary", "Owned primary λ", %{
        "type" => "search",
        "query" => "Owned primary λ",
        "queries" => ["Owned different first", "Owned different second"]
      }),
      web_item("fallback", "Owned fallback first ...", %{
        "type" => "search",
        "query" => nil,
        "queries" => ["Owned fallback first", "Owned fallback second"]
      }),
      web_item("open", @page, %{"type" => "openPage", "url" => @page}),
      web_item("find", "'Owned needle 🙂' in " <> @page, %{
        "type" => "findInPage",
        "url" => @page,
        "pattern" => "Owned needle 🙂"
      }),
      web_item("primary-queries-omitted", "Owned nullable primary λ", %{
        "type" => "search",
        "query" => "Owned nullable primary λ",
        "queries" => nil
      }),
      web_item("primary-queries-null", "Owned nullable primary λ", %{
        "type" => "search",
        "query" => "Owned nullable primary λ",
        "queries" => nil
      }),
      web_item("search-fields-omitted", "", %{
        "type" => "search",
        "query" => nil,
        "queries" => nil
      }),
      web_item("search-fields-null", "", %{
        "type" => "search",
        "query" => nil,
        "queries" => nil
      }),
      web_item("open-url-omitted", "", %{"type" => "openPage", "url" => nil}),
      web_item("open-url-null", "", %{"type" => "openPage", "url" => nil}),
      web_item("find-url-omitted", "'Owned lone pattern 🙂'", %{
        "type" => "findInPage",
        "url" => nil,
        "pattern" => "Owned lone pattern 🙂"
      }),
      web_item("find-url-null", "'Owned lone pattern 🙂'", %{
        "type" => "findInPage",
        "url" => nil,
        "pattern" => "Owned lone pattern 🙂"
      }),
      web_item("find-pattern-omitted", @page, %{
        "type" => "findInPage",
        "url" => @page,
        "pattern" => nil
      }),
      web_item("find-pattern-null", @page, %{
        "type" => "findInPage",
        "url" => @page,
        "pattern" => nil
      }),
      web_item("find-fields-omitted", "", %{
        "type" => "findInPage",
        "url" => nil,
        "pattern" => nil
      }),
      web_item("find-fields-null", "", %{
        "type" => "findInPage",
        "url" => nil,
        "pattern" => nil
      })
    ]
  end

  defp web_item(name, query, action),
    do: %{
      "type" => "webSearch",
      "id" => "owned-streamed-web-" <> name,
      "query" => query,
      "action" => action,
      "results" => nil
    }

  defp assert_live(events, thread, turn, before_ms, after_ms) do
    started = web_events(events, "item/started")
    finished = web_events(events, "item/completed")
    ids = Enum.map(items(), & &1["id"])
    assert Enum.map(started, & &1["item"]["id"]) == ids
    assert Enum.map(finished, & &1["item"]["id"]) == ids

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          item = event.wire["params"]["item"],
          item["type"] == "webSearch",
          do: {event.wire["method"], item["id"]}

    assert order == Enum.flat_map(ids, &[{"item/started", &1}, {"item/completed", &1}])

    entries =
      for {item, begin, finish} <- Enum.zip([items(), started, finished]) do
        began_at = Map.fetch!(begin, "startedAtMs")
        ended_at = Map.fetch!(finish, "completedAtMs")
        assert is_integer(began_at) and is_integer(ended_at)
        assert before_ms <= began_at and began_at <= ended_at and ended_at <= after_ms

        placeholder = %{item | "query" => "", "action" => %{"type" => "other"}}

        assert begin === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => placeholder,
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

  defp assert_provider(ctx, thread, turn) do
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert Map.fetch!(request, "model") == "mock-model"

    assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

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

  defp assert_history(pid, thread, turn) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => rows}] =
             saved["turns"]

    assert Enum.filter(rows, &(&1["type"] == "webSearch")) === items()

    assert [%{"type" => "agentMessage", "text" => @answer}] =
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

    duplicated = ["owned-absent-web-item" | Enum.reverse(query["itemIds"]) ++ query["itemIds"]]
    assert call(pid, "thread/items/read", %{query | "itemIds" => duplicated}) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-web-item"]}) ===
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
      assert System.monotonic_time(:millisecond) < until, "native streamed-web turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected streamed-web event gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp web_events(events, method),
    do: Enum.filter(params(events, method), &(&1["item"]["type"] == "webSearch"))

  defp call(pid, method, params) do
    id = "owned-streamed-web-#{System.unique_integer([:positive, :monotonic])}"
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
               %{"name" => "owned_streamed_web_items", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
