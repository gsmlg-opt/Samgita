defmodule SamgitaCodexDriver.NativeStandaloneSourceSelectorTest do
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
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @standalone_sha "528c11baca43b3be05112c0be1fb1c4a3d5c53f1b6d628f5bf42ebd7803e7a9e"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @needle "Owned standalone source selector 163 λ🙂"
  @answer "Deterministic local fixture answer"
  @instructions "Owned ordinary standalone source selector instructions."
  @metadata "internal_chat_message_metadata_passthrough"
  @projection ~w(id source preview cwd modelProvider path historyMode turns sessionId parentThreadId forkedFromId threadSource)
  @schemas %{
    "ThreadSearchParams.json" =>
      "5c3bbb9d37d7d83f3f7747423427ff9c8b0f1154ac8cd7c832995a763dfa8e61",
    "ThreadSearchResponse.json" =>
      "52db70b7c6a95f5c0bb9150104df17ab68ea6abe793951a1b3cf5efa68903313"
  }
  @app_bytes "\"appServer\"\n"
  @unknown_bytes "\"unknown\"\n"
  @custom_bytes """
  {
    "additionalProperties": false,
    "properties": {
      "custom": {
        "type": "string"
      }
    },
    "required": [
      "custom"
    ],
    "title": "CustomSessionSource",
    "type": "object"
  }
  """
  @string_bytes """
  {
    "type": "string"
  }
  """
  @app_sha "622214a100066aceb1d1ab827c78dee8aaf32f7cd66e8c02400287fe6cb589c3"
  @unknown_sha "53331ee8a3d89d5e956086b9c9ffaa709efef795a17c43bbc9666bb622947f8e"
  @custom_sha "d9e145b3bb9eb5bc34a7e8705de3058f42fe714883c960d7f41e5f4fb37378d9"
  @string_sha "bf0b727f7b1c6d07c7312c6c7760fd34302744385611a86804210c77d80b0cc7"
  @notification_sha "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1"
  @cli_bytes "\"cli\"\n"
  @exec_bytes "\"exec\"\n"
  @cli_sha "3e32720a84f76aa3c6d43c98afe5b44c70938bfb1eac76f371d1a60838da8b4a"
  @exec_sha "c20d3fcfc0c2bd2a6ecb30670b66a69dce7b92ca87e3cefd922f3ec19b917e82"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next, :out, encoded) do
            :ok -> {:ok, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case capture_events(events, next) do
            :ok -> {:ok, events, next}
            {:error, error} -> {:error, error, next}
          end

        other ->
          other
      end
    end

    defp capture_events(events, state) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok -> capture_message(state, encoded)
        _, :ok -> {:cont, :ok}
      end)
    end

    defp capture_message(state, encoded) do
      case record(state, :in, encoded) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if length(ledger.records) < 1024 and size <= 262_144 and ledger.bytes + size <= 8_388_608 do
          frame = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}
          {:ok, %{records: [frame | ledger.records], bytes: ledger.bytes + size}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_APP_SERVER_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: separately pinned CODEX_APP_SERVER_BINARY required"

    assert hash(File.read!(binary)) === @standalone_sha
    assert hash(File.read!(@provider)) === @provider_sha
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-standalone-source-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    resources = :atomics.new(7, [])

    on_exit(fn ->
      assert Enum.all?(1..7, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)
    on_exit(fn -> close_provider(fixture, resources) end)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: Path.expand(binary), fixture: fixture, root: root, resources: resources}

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(fixture.bin, "rg"))
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      [config, Path.join(fixture.codex_home, "turn-models.json"), @provider, __ENV__.file] ++
        Enum.map(
          ~w(model_fixture turn_fixture native_launch_fixture stdio_session_fixture),
          &Path.join(__DIR__, "support/#{&1}.ex")
        ) ++
        Enum.map(Map.keys(@schemas), &schema_path/1)

    assert requests(ctx) === []
    Map.put(ctx, :inputs, Map.new(inputs, &{&1, bounded_file(&1)}))
  end

  test "standalone sources produce genuine histories selected by two cold native readers", ctx do
    specifications = [
      {"appserver", "mcp", "appServer", "A"},
      {"unknown", "unknown", "unknown", "U"},
      {"AtLaS", %{"custom" => "atlas"}, %{"custom" => "atlas"}, "C"},
      {"vscode", "vscode", "vscode", "V"}
    ]

    {rows, producers} =
      specifications
      |> Enum.with_index(1)
      |> Enum.map_reduce([], fn
        {{selector, core, public, label}, index}, sessions ->
          session = start(ctx, selector, index + 1)

          row =
            produce(ctx, session, %{
              core: core,
              public: public,
              text: label <> ": " <> @needle,
              index: index
            })

          close(session)
          assert_thread_started(session, row)
          frozen = canonical(ctx, row)
          assert frozen.user["id"] === hd(row.items)["id"]
          assert frozen.assistant["id"] === List.last(row.items)["id"]
          {Map.put(row, :bytes, frozen.bytes), sessions ++ [session]}
      end)

    assert length(Enum.uniq(Enum.map(rows, & &1.id))) === 4
    assert length(rollouts(ctx)) === 4
    assert length(requests(ctx)) === 4
    journal = bounded_file(ctx.fixture.requests)
    assert_retained(ctx, rows, journal)

    readers =
      for slot <- [6, 7] do
        reader = start(ctx, "vscode", slot)
        assert_unloaded(ctx, reader)
        discoveries = matrix(ctx, reader, rows)
        assert_physical_owners(discoveries)
        assert_unloaded(ctx, reader)

        for row <- rows do
          observed = history(ctx, reader, row)
          assert observed === row
        end

        assert_unloaded(ctx, reader)
        assert_idle(reader)
        assert_retained(ctx, rows, journal)
        close(reader)
        assert_retained(ctx, rows, journal)
        %{session: reader, discoveries: discoveries}
      end

    [first, second] = readers
    assert stable_discoveries(first.discoveries) === stable_discoveries(second.discoveries)
    sessions = producers ++ Enum.map(readers, & &1.session)
    assert length(Enum.uniq(Enum.map(sessions, & &1.native))) === 6
    assert_inventory(sessions)
    assert_retained(ctx, rows, journal)
    assert hash(File.read!(ctx.binary)) === @standalone_sha
    close_provider(ctx.fixture, ctx.resources)
  end

  @tag :standalone_thread_started_sources
  test "standalone cli and exec produce original source-exact thread started notifications",
       ctx do
    {rows, sessions} =
      [{"cli", "cli", "CLI"}, {"exec", "exec", "Exec"}]
      |> Enum.with_index(1)
      |> Enum.map_reduce([], fn {{selector, source, label}, index}, sessions ->
        session = start(ctx, selector, index + 1)

        row =
          produce(ctx, session, %{
            core: source,
            public: source,
            text: label <> ": " <> @needle,
            index: index
          })

        close(session)
        assert_thread_started(session, row)
        frozen = canonical(ctx, row)
        assert frozen.user["id"] === hd(row.items)["id"]
        assert frozen.assistant["id"] === List.last(row.items)["id"]
        {Map.put(row, :bytes, frozen.bytes), sessions ++ [session]}
      end)

    assert length(Enum.uniq(Enum.map(rows, & &1.id))) === 2
    assert length(Enum.uniq(Enum.map(sessions, & &1.native))) === 2
    assert length(rollouts(ctx)) === 2
    assert length(requests(ctx)) === 2
    journal = bounded_file(ctx.fixture.requests)
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    for row <- rows, do: assert(bounded_file(row.path) === row.bytes)
    assert File.ls!(ctx.fixture.workspace) === []
    assert_started_inventory(sessions)
    assert hash(File.read!(ctx.binary)) === @standalone_sha
    close_provider(ctx.fixture, ctx.resources)
    assert bounded_file(ctx.fixture.requests) === journal
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    for row <- rows, do: assert(bounded_file(row.path) === row.bytes)
  end

  defp assert_thread_started(session, row) do
    records = frames(session)

    assert [request] =
             Enum.filter(
               records,
               &(&1.direction === :out and &1.wire["method"] === "thread/start")
             )

    assert [response] =
             Enum.filter(
               records,
               &(&1.direction === :in and &1.wire["id"] === request.wire["id"])
             )

    assert_exchange(session, request.wire, response.wire)

    assert [notice] =
             Enum.filter(
               records,
               &(&1.direction === :in and &1.wire["method"] === "thread/started")
             )

    assert JSON.decode!(notice.encoded) === notice.wire
    refute Map.has_key?(notice.wire, "id")
    assert Enum.sort(Map.keys(notice.wire)) === ["emittedAtMs", "method", "params"]
    assert Enum.sort(Map.keys(notice.wire["params"])) === ["thread"]
    notified = Map.fetch!(notice.wire["params"], "thread")
    initial = Map.fetch!(response.wire["result"], "thread")
    emitted = Map.fetch!(notice.wire, "emittedAtMs")
    assert is_integer(emitted) and emitted > 0
    assert is_integer(initial["createdAt"]) and initial["createdAt"] > 0
    assert initial["createdAt"] * 1000 <= emitted and emitted <= System.system_time(:millisecond)
    assert Map.take(notified, @projection) === Map.take(initial, @projection)
    assert Map.take(notified, @projection) === Map.put(row.projection, "preview", "")
    assert notified["id"] === row.id and notified["source"] === row.public
    assert notified["path"] === row.path and notified["turns"] === []

    # Resolve this exact notification graph; search/start-response aliases and
    # equal node hashes never stand in for original incoming notification bytes.
    path =
      Path.join(
        :code.priv_dir(:samgita_protocol_codex),
        "upstream/0.163.0/experimental/ServerNotification.json"
      )

    bytes = bounded_file(path)
    assert hash(bytes) === @notification_sha
    root = JSON.decode!(bytes)
    branch = root |> Map.fetch!("oneOf") |> Enum.at(1)
    assert get_in(branch, ["properties", "method", "enum"]) === ["thread/started"]

    assert get_in(branch, ["properties", "params"]) === %{
             "$ref" => "#/definitions/ThreadStartedNotification"
           }

    assert get_in(root, ["definitions", "ThreadStartedNotification", "properties", "thread"]) ===
             %{"$ref" => "#/definitions/Thread"}

    assert get_in(root, ["definitions", "Thread", "properties", "source", "allOf"]) === [
             %{"$ref" => "#/definitions/SessionSource"}
           ]

    # Validate only the selected source owners below. Other native Thread
    # fields remain captured opaquely; no unrelated output contract is claimed.
    assert_started_source_owner(root, notified["source"])
  end

  defp assert_started_source_owner(root, source) do
    for binding <- notification_source_bindings(source),
        do: assert_started_binding(root, binding)
  end

  defp notification_source_bindings(source) do
    case source do
      "cli" ->
        [{2386, "/definitions/SessionSource/oneOf/0/enum/0", @cli_bytes, @cli_sha, source}]

      "exec" ->
        [{2388, "/definitions/SessionSource/oneOf/0/enum/2", @exec_bytes, @exec_sha, source}]

      "appServer" ->
        [{2389, "/definitions/SessionSource/oneOf/0/enum/3", @app_bytes, @app_sha, source}]

      "unknown" ->
        [
          {2390, "/definitions/SessionSource/oneOf/0/enum/4", @unknown_bytes, @unknown_sha,
           source}
        ]

      %{"custom" => "atlas"} ->
        [
          {2391, "/definitions/SessionSource/oneOf/1", @custom_bytes, @custom_sha, source},
          {2392, "/definitions/SessionSource/oneOf/1/properties/custom", @string_bytes,
           @string_sha, source["custom"]}
        ]

      "vscode" ->
        []
    end
  end

  defp assert_started_binding(root, {owner, pointer, bytes, digest, value}) do
    assert owner in [2386, 2388, 2389, 2390, 2391, 2392]
    node = notification_node(root, pointer)
    assert node === JSON.decode!(bytes)
    assert hash(bytes) === digest
    if is_map(node), do: assert(:ok = Schema.validate(node, value)), else: assert(node === value)
  end

  defp notification_node(root, pointer) do
    pointer
    |> String.trim_leading("/")
    |> String.split("/")
    |> Enum.reduce(root, fn part, current ->
      if is_list(current),
        do: Enum.at(current, String.to_integer(part)),
        else: Map.fetch!(current, part)
    end)
  end

  defp assert_started_inventory(sessions) do
    outgoing =
      for session <- sessions, %{direction: :out, wire: wire} <- frames(session), do: wire

    for method <-
          ~w(initialize initialized server/diagnostics thread/start turn/start thread/read thread/items/list),
        do: assert(Enum.count(outgoing, &(&1["method"] === method)) === 2)

    probes_and_pages = Enum.count(outgoing, &(&1["method"] === "thread/turns/list"))
    assert probes_and_pages >= 4 and probes_and_pages <= 402

    allowed =
      ~w(initialize initialized server/diagnostics thread/start turn/start thread/read thread/items/list thread/turns/list)

    assert Enum.all?(outgoing, &(&1["method"] in allowed))
    for session <- sessions, do: assert_started_session_inventory(session)
  end

  defp assert_started_session_inventory(session) do
    records = frames(session)
    sent = Enum.filter(records, &(&1.direction === :out and Map.has_key?(&1.wire, "id")))
    replies = Enum.filter(records, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    ids = Enum.map(sent, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === length(ids)
    assert length(sent) === length(replies)
    for request <- sent, do: assert_started_request(session, replies, request)
    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp assert_started_request(session, replies, request) do
    assert [response] = Enum.filter(replies, &(&1.wire["id"] === request.wire["id"]))
    assert_exchange(session, request.wire, response.wire)
  end

  defp produce(ctx, session, source) do
    assert length(requests(ctx)) === source.index - 1

    initial =
      call(session, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated",
        "threadSource" => "user"
      })["thread"]

    id = Map.fetch!(initial, "id")
    assert is_binary(id) and id != ""
    assert initial["source"] === source.public

    turn =
      call(session, "turn/start", %{
        "threadId" => id,
        "input" => [%{"type" => "text", "text" => source.text}]
      })["turn"]["id"]

    assert is_binary(turn) and turn != ""
    events = complete_turn(session, id, turn, [], now() + 20_000)

    streamed =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == id,
          event.wire["params"]["turnId"] == turn,
          do: event.wire["params"]["item"]

    assert [user, assistant] = streamed
    assert user["type"] === "userMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => source.text}
           ]

    assert %{"type" => "agentMessage", "text" => @answer} = assistant
    assert length(requests(ctx)) === source.index
    request = Enum.at(requests(ctx), source.index - 1)
    assert request["model"] === "mock-model"

    assert %{"thread_id" => ^id, "turn_id" => ^turn} =
             JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Enum.count(
             request["input"],
             &(&1["role"] == "user" and
                 &1["content"] === [%{"type" => "input_text", "text" => source.text}])
           ) === 1

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    await_items(session, id, turn, now() + 5_000, 200)
    path = await_rollout(ctx, id, turn, now() + 5_000, 200)
    assert initial["path"] === path
    row = Map.merge(source, %{id: id, turn: turn, path: path})
    saved = history(ctx, session, row)
    assert saved.items === streamed
    assert_idle(session)
    saved
  end

  defp history(ctx, session, source) do
    thread =
      call(session, "thread/read", %{"threadId" => source.id, "includeTurns" => false})["thread"]

    projection = %{
      "id" => source.id,
      "source" => source.public,
      "preview" => source.text,
      "cwd" => ctx.fixture.workspace,
      "modelProvider" => "fixture",
      "path" => source.path,
      "historyMode" => "paginated",
      "turns" => [],
      "sessionId" => source.id,
      "parentThreadId" => nil,
      "forkedFromId" => nil,
      "threadSource" => "user"
    }

    assert Map.take(thread, @projection) === projection
    page = call(session, "thread/turns/list", turns_params(source.id))
    assert page["nextCursor"] === nil
    assert [turn] = page["data"]
    assert turn["id"] === source.turn and turn["status"] === "completed"
    assert turn["error"] === nil and turn["itemsView"] === "full"
    assert [user, assistant] = turn["items"]
    assert user["type"] === "userMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => source.text}
           ]

    assert %{"type" => "agentMessage", "text" => @answer} = assistant

    items =
      call(session, "thread/items/list", %{
        "threadId" => source.id,
        "turnId" => source.turn,
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert items["nextCursor"] === nil
    assert Enum.map(items["data"], & &1["turnId"]) === [source.turn, source.turn]
    assert Enum.map(items["data"], & &1["item"]) === [user, assistant]
    raw = canonical(ctx, source)
    assert user["id"] === raw.user["id"] and assistant["id"] === raw.assistant["id"]

    Map.merge(source, %{
      projection: projection,
      items: [user, assistant],
      turns: [turn],
      bytes: raw.bytes
    })
  end

  defp canonical(ctx, source) do
    assert String.starts_with?(
             Path.expand(source.path),
             Path.expand(ctx.fixture.codex_home) <> "/"
           )

    bytes = bounded_file(source.path)
    records = jsonl(bytes)
    assert [%{"type" => "session_meta", "payload" => first} | _] = records

    assert Map.take(
             first,
             ~w(id source cwd model_provider history_mode cli_version thread_source session_id)
           ) === %{
             "id" => source.id,
             "source" => source.core,
             "cwd" => ctx.fixture.workspace,
             "model_provider" => "fixture",
             "history_mode" => "paginated",
             "cli_version" => "0.163.0",
             "thread_source" => "user",
             "session_id" => source.id
           }

    assert Map.get(first, "parent_thread_id") === nil and Map.get(first, "forked_from_id") === nil

    payloads =
      for %{"type" => "response_item", "payload" => payload} <- records,
          get_in(payload, [@metadata, "turn_id"]) == source.turn,
          do: payload

    assert [_user] =
             Enum.filter(
               payloads,
               &(&1["role"] == "user" and
                   &1["content"] === [%{"type" => "input_text", "text" => source.text}])
             )

    assert [answer] = Enum.filter(payloads, &(&1["role"] == "assistant"))
    assert answer["id"] === "fixture-message-#{source.index}"
    assert answer["content"] === [%{"type" => "output_text", "text" => @answer}]
    {user, assistant} = canonical_events(records, source)
    %{bytes: bytes, user: user, assistant: assistant}
  end

  defp canonical_events(records, source) do
    events = for %{"type" => "event_msg", "payload" => event} <- records, do: event

    assert [completed] =
             Enum.filter(
               events,
               &(&1["type"] == "task_complete" and &1["turn_id"] == source.turn)
             )

    assert completed["last_agent_message"] === @answer and Map.get(completed, "error") === nil

    items =
      for %{"type" => "item_completed", "turn_id" => turn, "item" => item} <- events,
          turn == source.turn,
          do: item

    assert [user, assistant] = items
    assert user["type"] === "UserMessage"

    assert Enum.map(user["content"], &Map.take(&1, ["type", "text"])) === [
             %{"type" => "text", "text" => source.text}
           ]

    assert assistant["type"] === "AgentMessage"
    assert assistant["content"] === [%{"type" => "Text", "text" => @answer}]
    assert assistant["id"] === "fixture-message-#{source.index}"
    for item <- items, do: assert(is_binary(item["id"]) and item["id"] != "")
    refute user["id"] == assistant["id"]
    {user, assistant}
  end

  defp matrix(ctx, reader, rows) do
    filters = [
      {["appServer"], ["appServer"]},
      {["unknown"], ["unknown"]},
      {["vscode"], ["vscode"]},
      {["appServer", "unknown"], ["appServer", "unknown"]},
      {["appServer", "unknown", "vscode"], ["appServer", "unknown", "vscode"]},
      {:omitted, [%{"custom" => "atlas"}, "vscode"]}
    ]

    for method <- ["thread/list", "thread/search"], {kinds, sources} <- filters do
      params =
        if method == "thread/list",
          do: %{"limit" => 100, "useStateDbOnly" => true},
          else: %{"limit" => 100, "searchTerm" => @needle}

      params = if kinds == :omitted, do: params, else: Map.put(params, "sourceKinds", kinds)
      result = call(reader, method, params)
      assert Map.fetch!(result, "nextCursor") === nil
      data = Map.fetch!(result, "data")

      threads =
        if method == "thread/search", do: Enum.map(data, &Map.fetch!(&1, "thread")), else: data

      expected = Enum.filter(rows, &(&1.public in sources))
      ids = Enum.map(threads, &Map.fetch!(&1, "id"))
      assert length(ids) === length(expected) and length(Enum.uniq(ids)) === length(ids)
      assert MapSet.new(ids) === MapSet.new(Enum.map(expected, & &1.id))

      for thread <- threads do
        original = Enum.find(expected, &(&1.id == thread["id"]))
        assert Map.take(thread, @projection) === Map.put(original.projection, "threadSource", nil)
      end

      assert_snippets(method, data, expected)

      assert length(requests(ctx)) === 4
      %{method: method, params: params, result: result}
    end
  end

  defp assert_snippets("thread/search", data, expected) do
    for row <- data do
      original = Enum.find(expected, &(&1.id == row["thread"]["id"]))
      assert row["snippet"] === original.text
    end
  end

  defp assert_snippets("thread/list", _data, _expected), do: :ok

  defp assert_physical_owners(discoveries) do
    params = schema("ThreadSearchParams.json")
    response = schema("ThreadSearchResponse.json")
    kinds = get_in(params, ["definitions", "ThreadSourceKind", "enum"])
    variants = get_in(response, ["definitions", "SessionSource", "oneOf"])

    bindings = [
      {6076, Enum.at(kinds, 3), @app_bytes, @app_sha},
      {6082, Enum.at(kinds, 9), @unknown_bytes, @unknown_sha},
      {6101, get_in(Enum.at(variants, 0), ["enum"]) |> Enum.at(3), @app_bytes, @app_sha},
      {6102, get_in(Enum.at(variants, 0), ["enum"]) |> Enum.at(4), @unknown_bytes, @unknown_sha},
      {6103, Enum.at(variants, 1), @custom_bytes, @custom_sha},
      {6104, get_in(Enum.at(variants, 1), ["properties", "custom"]), @string_bytes, @string_sha}
    ]

    assert Enum.map(bindings, &elem(&1, 0)) === [6076, 6082, 6101, 6102, 6103, 6104]

    for {_owner, node, bytes, digest} <- bindings do
      assert node === JSON.decode!(bytes)
      assert hash(bytes) === digest
    end

    searches = Enum.filter(discoveries, &(&1.method == "thread/search"))

    for query <- searches do
      assert_search_owners(query, params, kinds, variants)
    end
  end

  defp assert_search_owners(query, params, kinds, variants) do
    assert :ok = Schema.validate(params, query.params, max_depth: 64)

    for value <- Map.get(query.params, "sourceKinds", []),
        value in ["appServer", "unknown"],
        do: assert(value === Enum.at(kinds, if(value == "appServer", do: 3, else: 9)))

    for row <- query.result["data"], do: assert_source_owner(row["thread"]["source"], variants)
  end

  defp assert_source_owner("appServer" = source, _variants),
    do: assert(source === JSON.decode!(@app_bytes))

  defp assert_source_owner("unknown" = source, _variants),
    do: assert(source === JSON.decode!(@unknown_bytes))

  defp assert_source_owner(%{"custom" => "atlas"} = source, variants) do
    assert :ok = Schema.validate(Enum.at(variants, 1), source)

    assert :ok =
             Schema.validate(
               get_in(Enum.at(variants, 1), ["properties", "custom"]),
               source["custom"]
             )
  end

  defp assert_source_owner("vscode", _variants), do: :ok

  defp stable_discoveries(discoveries) do
    # Preserve original full replies in the captures. Compare only the stable
    # content/source projection; independent native read-state receipts are not
    # normalized or asserted equal across different reader processes.
    Enum.map(discoveries, fn query ->
      rows = Enum.map(query.result["data"], &discovery_projection(query.method, &1))

      {query.method, query.params, query.result["nextCursor"], rows}
    end)
  end

  defp discovery_projection("thread/search", row),
    do: %{thread: Map.take(row["thread"], @projection), snippet: row["snippet"]}

  defp discovery_projection("thread/list", row), do: Map.take(row, @projection)

  defp await_items(session, thread, turn, until, probes) do
    page = call(session, "thread/turns/list", turns_params(thread))
    assert page["nextCursor"] === nil
    assert is_list(page["data"]) and length(page["data"]) <= 1

    case page["data"] do
      [
        %{
          "id" => ^turn,
          "status" => "completed",
          "items" => [%{"type" => "userMessage"}, %{"type" => "agentMessage"}]
        }
      ] ->
        :ok

      _ ->
        readiness(until, probes)
        await_items(session, thread, turn, until, probes - 1)
    end
  end

  defp await_rollout(ctx, thread, turn, until, probes) do
    paths = rollouts(ctx)
    assert length(paths) <= 4

    found =
      Enum.find(paths, fn path ->
        bytes = File.read!(path)
        assert byte_size(bytes) <= 4_194_304

        records =
          if byte_size(bytes) > 0 and String.ends_with?(bytes, "\n"), do: jsonl(bytes), else: []

        case records do
          [%{"type" => "session_meta", "payload" => %{"id" => ^thread}} | _] ->
            Enum.any?(
              records,
              &(&1["type"] == "event_msg" and &1["payload"]["type"] == "task_complete" and
                  &1["payload"]["turn_id"] == turn)
            )

          _ ->
            false
        end
      end)

    if found,
      do: found,
      else:
        (
          readiness(until, probes)
          await_rollout(ctx, thread, turn, until, probes - 1)
        )
  end

  defp readiness(until, probes) do
    assert probes > 1 and now() < until, "Owned native persistence readiness exhausted"
    Process.sleep(25)
  end

  defp complete_turn(session, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(session.pid, 256)
    events = events ++ incoming

    assert length(events) <= 256 and
             byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    completed =
      TurnFixture.notification(
        events,
        "turn/completed",
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

    if completed do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
               completed

      events
    else
      remaining = until - now()
      assert remaining > 0, "Owned native turn completion deadline"

      receive do
        {:codex_driver, pid, :events_available} when pid == session.pid ->
          complete_turn(session, thread, turn, events, until)

        {:codex_driver, pid, {:gap, _}} when pid == session.pid ->
          flunk("Unexpected native event gap")
      after
        remaining -> flunk("Owned native turn completion deadline")
      end
    end
  end

  defp start(ctx, selector, slot) do
    before = requests(ctx)

    capture =
      start_supervised!(
        Supervisor.child_spec({Agent, fn -> %{records: [], bytes: 0} end}, id: make_ref())
      )

    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 262_144,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args([
                        "--listen",
                        "stdio://",
                        "--session-source",
                        selector
                      ]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 262_144,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    :atomics.put(ctx.resources, slot, 1)
    native = :atomics.new(1, [])

    session = %{
      pid: pid,
      connection: connection,
      capture: capture,
      identity: native,
      slot: slot,
      resources: ctx.resources
    }

    on_exit(fn -> close(session) end)
    id = request_id()
    info = %{"name" => "owned_standalone_source_selector", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = reply} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      reply
    )

    os_pid = call(session, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(native, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @standalone_sha
    assert requests(ctx) === before
    Map.put(session, :native, os_pid)
  end

  defp call(session, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(session.pid, wire, timeout_ms: 5_000)

    assert_exchange(session, wire, response)
    result
  end

  defp assert_exchange(session, wire, response) do
    assert [sent, received] = Enum.filter(frames(session), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and received.wire === response
    assert JSON.decode!(sent.encoded) === wire and sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(sessions) do
    outgoing =
      for session <- sessions, %{direction: :out, wire: wire} <- frames(session), do: wire

    for {method, count} <- [
          {"initialize", 6},
          {"initialized", 6},
          {"server/diagnostics", 6},
          {"thread/start", 4},
          {"turn/start", 4},
          {"thread/list", 12},
          {"thread/search", 12},
          {"thread/read", 12},
          {"thread/items/list", 12},
          {"thread/loaded/list", 6}
        ],
        do: assert(Enum.count(outgoing, &(&1["method"] == method)) === count)

    polls = Enum.count(outgoing, &(&1["method"] == "thread/turns/list"))
    assert polls >= 16 and polls <= 812

    allowed =
      ~w(initialize initialized server/diagnostics thread/start turn/start thread/list thread/search thread/read thread/items/list thread/loaded/list thread/turns/list)

    assert Enum.all?(outgoing, &(&1["method"] in allowed))

    for session <- sessions do
      records = frames(session)
      sent = Enum.filter(records, &(&1.direction == :out and Map.has_key?(&1.wire, "id")))
      replies = Enum.filter(records, &(&1.direction == :in and Map.has_key?(&1.wire, "id")))
      assert length(sent) === length(replies)
      ids = Enum.map(sent, & &1.wire["id"])
      assert length(Enum.uniq(ids)) === length(sent)
      for frame <- records, do: assert(JSON.decode!(frame.encoded) === frame.wire)
    end
  end

  defp assert_unloaded(ctx, session) do
    assert call(session, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert length(requests(ctx)) === 4
  end

  defp assert_idle(session) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(session.pid)
    assert Session.uncertain_operations(session.pid) === []
    assert {:ok, _events} = Session.drain(session.pid, 256)
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
    :atomics.put(session.resources, session.slot, 2)
  end

  defp close_provider(fixture, resources) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
    :atomics.put(resources, 1, 2)
  end

  defp assert_retained(ctx, rows, journal) do
    assert bounded_file(ctx.fixture.requests) === journal
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    for row <- rows, do: assert(bounded_file(row.path) === row.bytes)
    assert length(rollouts(ctx)) === 4
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= 4_194_304
    bytes = File.read!(path)
    assert byte_size(bytes) <= 4_194_304
    bytes
  end

  defp jsonl(bytes) do
    assert String.ends_with?(bytes, "\n")
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 2048

    Enum.map(lines, fn line ->
      assert byte_size(line) <= 262_144
      JSON.decode!(line)
    end)
  end

  defp requests(ctx) do
    value = JSON.decode!(bounded_file(ctx.fixture.requests))
    assert is_list(value) and length(value) <= 4
    value
  end

  defp frames(session), do: Agent.get(session.capture, &Enum.reverse(&1.records))

  defp rollouts(ctx),
    do: Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl"))

  defp turns_params(thread),
    do: %{"threadId" => thread, "itemsView" => "full", "sortDirection" => "asc", "limit" => 100}

  defp schema_path(name),
    do:
      Path.join(
        :code.priv_dir(:samgita_protocol_codex),
        "upstream/0.163.0/experimental/v2/" <> name
      )

  defp schema(name), do: schema_path(name) |> File.read!() |> JSON.decode!()
  defp request_id, do: "owned-standalone-source-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
