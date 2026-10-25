defmodule SamgitaCodexDriver.NativeStandaloneWebSearchTest do
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
  @script Path.expand("../../../scripts/codex/standalone_web_search_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @marker "Owned standalone web lifecycle λ🙂"
  @page "https://standalone-web.synthetic.invalid/owned-page"

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
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\nstandalone_web_search = true\napps = false\nplugins = false\n" <>
        "recommended_plugins = false\nshell_snapshot = false\n"
    )

    inputs =
      Map.new([config, Path.join(ctx.fixture.codex_home, "turn-models.json")], fn path ->
        {path, snapshot(path)}
      end)

    ctx
    |> Map.put(:inputs, inputs)
    |> Map.put(:search_journal, Path.join(ctx.root, "search-requests.json"))
  end

  test "native web.run starts with null action and retains opaque final results after restart",
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
        ctx.fixture.requests => snapshot(ctx.fixture.requests),
        ctx.search_journal => snapshot(ctx.search_journal)
      })

    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => Enum.map(items(), & &1["id"])}
    assert_selection(warm, query, expected)
    assert_retained(ctx, warm, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    # Select completed items before any operation can hydrate the old thread.
    assert call(cold, "thread/items/read", query) === expected
    assert_selection(cold, query, expected)
    cold_saved = assert_history(cold, thread, turn)
    assert cold_saved["turns"] === saved["turns"]
    assert cold_saved["path"] == path
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {file, bytes} <- retained, do: assert(snapshot(file) === bytes)
  end

  defp commands do
    [
      %{"search_query" => [%{"q" => "Owned standalone first λ"}, %{"q" => "Owned second"}]},
      %{"open" => [%{"ref_id" => @page, "lineno" => 7}]},
      %{"find" => [%{"ref_id" => "owned-search-reference", "pattern" => "Owned needle 🙂"}]},
      %{"time" => [%{"utc_offset" => "+00:00"}]}
    ]
  end

  defp items do
    results = [
      %{
        "type" => "text_result",
        "ref_id" => "owned-search-reference",
        "url" => @page,
        "title" => "Owned result λ",
        "future_field" => %{"enabled" => true, "nested" => [nil, 7, %{"label" => "🙂"}]}
      },
      %{"type" => "owned_future_result", "opaque" => [false, %{"preserved" => "α"}]}
    ]

    [
      item(
        1,
        "Owned standalone first λ ...",
        %{
          "type" => "search",
          "query" => nil,
          "queries" => ["Owned standalone first λ", "Owned second"]
        },
        results
      ),
      item(2, @page, %{"type" => "openPage", "url" => @page}, []),
      item(
        3,
        "'Owned needle 🙂'",
        %{
          "type" => "findInPage",
          "url" => nil,
          "pattern" => "Owned needle 🙂"
        },
        nil
      ),
      item(4, "", %{"type" => "other"}, nil)
    ]
  end

  defp item(index, query, action, results),
    do: %{
      "type" => "webSearch",
      "id" => "owned-standalone-web-#{index}",
      "query" => query,
      "action" => action,
      "results" => results
    }

  defp assert_live(events, thread, turn, before_ms, after_ms) do
    started = web_events(events, "item/started")
    completed = web_events(events, "item/completed")
    ids = Enum.map(items(), & &1["id"])
    assert Enum.map(started, & &1["item"]["id"]) == ids
    assert Enum.map(completed, & &1["item"]["id"]) == ids

    order =
      for event <- events,
          event.wire["method"] in ["item/started", "item/completed"],
          event.wire["params"]["item"]["type"] == "webSearch",
          do: {event.wire["method"], event.wire["params"]["item"]["id"]}

    assert order == Enum.flat_map(ids, &[{"item/started", &1}, {"item/completed", &1}])

    entries =
      for {final, begin, finish} <- Enum.zip([items(), started, completed]) do
        began_at = Map.fetch!(begin, "startedAtMs")
        ended_at = Map.fetch!(finish, "completedAtMs")
        assert is_integer(began_at) and is_integer(ended_at)
        assert before_ms <= began_at and began_at <= ended_at and ended_at <= after_ms
        placeholder = %{final | "query" => "", "action" => nil, "results" => nil}

        assert begin === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => placeholder,
                 "startedAtMs" => began_at
               }

        assert finish === %{
                 "threadId" => thread,
                 "turnId" => turn,
                 "item" => final,
                 "completedAtMs" => ended_at
               }

        %{
          "turnId" => turn,
          "item" => final,
          "startedAtMs" => began_at,
          "completedAtMs" => ended_at
        }
      end

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    %{"data" => entries}
  end

  defp assert_provider(ctx, thread, turn, before_ms, after_ms) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 5

    final_outputs =
      Enum.filter(List.last(requests)["input"], &(&1["type"] == "function_call_output"))

    assert Enum.map(final_outputs, & &1["call_id"]) ==
             Enum.map(1..4, &"owned-standalone-web-#{&1}")

    output_ids = Map.new(final_outputs, &{&1["call_id"], Map.fetch!(&1, "id")})
    assert MapSet.size(MapSet.new(Map.values(output_ids))) == 4

    for id <- Map.values(output_ids) do
      assert is_binary(id)

      assert Regex.match?(
               ~r/^fco_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
               id
             )
    end

    for {request, index} <- Enum.with_index(requests, 1) do
      assert request["model"] == "mock-model"

      assert %{"thread_id" => ^thread, "turn_id" => ^turn} =
               JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

      assert [%{"name" => "web", "tools" => [%{"name" => "run", "type" => "function"}]}] =
               Enum.filter(request["tools"], &(&1["name"] == "web"))

      outputs = Enum.filter(request["input"], &(&1["type"] == "function_call_output"))

      expected_outputs =
        for previous <- 1..(index - 1)//1 do
          %{
            "type" => "function_call_output",
            "id" => Map.fetch!(output_ids, "owned-standalone-web-#{previous}"),
            "call_id" => "owned-standalone-web-#{previous}",
            "output" => [
              %{"type" => "input_text", "text" => "Owned standalone result #{previous} λ"}
            ]
          }
        end

      assert outputs == expected_outputs
    end

    searches = read_search(ctx)
    assert length(searches) == 4

    assert [%{"internal_chat_message_metadata_passthrough" => %{"create_time" => created_at}}] =
             hd(searches)["body"]["input"]

    assert is_number(created_at) and created_at > 0
    created_ms = trunc(created_at * 1_000)
    assert before_ms <= created_ms and created_ms <= after_ms

    expected_metadata = %{
      "content_item_kinds" => ["user.text"],
      "create_time" => created_at,
      "turn_id" => turn
    }

    for {record, command, index} <- Enum.zip([searches, commands(), 1..4]) do
      assert record["path"] == "/v1/alpha/search"
      request = record["body"]
      assert request["commands"] == command
      assert request["model"] == "mock-model"
      assert request["id"] == thread

      assert request["settings"] == %{
               "allowed_callers" => ["direct"],
               "external_web_access" => false
             }

      assert is_integer(request["max_output_tokens"]) and request["max_output_tokens"] > 0

      assert request["input"] == [
               %{
                 "type" => "message",
                 "role" => "user",
                 "content" => [%{"type" => "input_text", "text" => @marker}],
                 "internal_chat_message_metadata_passthrough" => expected_metadata
               }
             ]

      assert %{"thread_id" => ^thread, "turn_id" => ^turn} = JSON.decode!(record["turn_metadata"])

      expected_response = %{"output" => "Owned standalone result #{index} λ"}

      expected_response =
        if index == 3,
          do: expected_response,
          else: Map.put(expected_response, "results", Enum.at(items(), index - 1)["results"])

      assert record["response"] === expected_response
    end
  end

  defp assert_history(pid, thread, turn) do
    saved = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert saved["id"] == thread
    assert saved["historyMode"] == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "error" => nil, "items" => rows}] =
             saved["turns"]

    assert Enum.filter(rows, &(&1["type"] == "webSearch")) === items()

    assert [%{"text" => "Owned standalone web finished"}] =
             Enum.filter(rows, &(&1["type"] == "agentMessage"))

    assert [%{"content" => [%{"type" => "text", "text" => @marker}]}] =
             Enum.filter(rows, &(&1["type"] == "userMessage"))

    saved
  end

  defp assert_selection(pid, query, expected) do
    assert call(pid, "thread/items/read", query) === expected

    for entry <- expected["data"] do
      assert call(pid, "thread/items/read", %{query | "itemIds" => [entry["item"]["id"]]}) === %{
               "data" => [entry]
             }
    end

    duplicated = [
      "owned-absent-standalone-item" | Enum.reverse(query["itemIds"]) ++ query["itemIds"]
    ]

    assert call(pid, "thread/items/read", %{query | "itemIds" => duplicated}) === expected

    assert call(pid, "thread/items/read", %{query | "itemIds" => ["owned-absent-standalone-item"]}) ===
             %{"data" => []}
  end

  defp assert_retained(ctx, pid, inputs) do
    for {path, bytes} <- inputs, do: assert(snapshot(path) === bytes)
    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert length(read_search(ctx)) == 4
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp read_search(ctx), do: ctx.search_journal |> File.read!() |> JSON.decode!()

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
      assert System.monotonic_time(:millisecond) < until, "native standalone-web turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected standalone-web event gap")
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
    id = "owned-standalone-web-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params},
               timeout_ms: 5_000
             )

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
               %{"name" => "owned_standalone_web", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
