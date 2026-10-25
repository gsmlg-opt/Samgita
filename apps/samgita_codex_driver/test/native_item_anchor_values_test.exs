defmodule SamgitaCodexDriver.NativeItemAnchorValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 100_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned fixed item-anchor fixture instructions."
  @markers ["owned-item-anchor-first λ", "owned-item-anchor-middle 🙂", "owned-item-anchor-last"]
  @answer "Deterministic local fixture answer"

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

      if wire["method"] == "thread/items/list" do
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
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(model_reasoning_effort = "low"\nmodel_reasoning_summary = "auto"\n) <>
        ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native item anchors exclude their selected item while optional paging values retain order",
       ctx do
    pid = start(ctx)

    thread =
      TurnFixture.call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]

    id = Map.fetch!(thread, "id")
    path = Map.fetch!(thread, "path")
    assert Map.fetch!(thread, "historyMode") == "paginated"
    assert ModelFixture.requests(ctx.fixture) == []

    turns =
      for {marker, count} <- Enum.with_index(@markers, 1) do
        turn =
          TurnFixture.call(pid, "turn/start", %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => marker}]
          })["turn"]["id"]

        events = complete_turn(pid, id, turn, [], deadline(20_000))
        entries = event_entries(events, id, turn, marker)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == count
        assert_provider(List.last(requests), marker)
        %{id: turn, marker: marker, entries: entries}
      end

    entries = Enum.flat_map(turns, & &1.entries)
    assert length(entries) == 6
    assert entries |> Enum.map(& &1["item"]["id"]) |> Enum.uniq() |> length() == 6
    history = read(pid, id)
    assert Map.fetch!(history, "id") == id
    assert Map.fetch!(history, "path") == path
    assert File.regular?(path)
    assert_history(history, turns)
    journal = File.read!(ctx.fixture.requests)
    query = %{"threadId" => id, "limit" => 2}
    assert_default_pages(ctx, pid, query, entries)
    assert_opaque_pages(ctx, pid, query, entries, "asc")
    assert_opaque_pages(ctx, pid, query, Enum.reverse(entries), "desc")
    assert_anchors(ctx, pid, id, Enum.at(turns, 1))

    current = read(pid, id)
    assert_history(current, turns)

    assert Map.take(current, ["id", "path", "preview", "turns"]) ===
             Map.take(history, ["id", "path", "preview", "turns"])

    assert File.regular?(path)
    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert length(Agent.get(ctx.capture, & &1)) == 19
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = close(pid)
  end

  defp assert_default_pages(ctx, pid, query, ascending) do
    for {extra, expected} <- [
          {%{}, Enum.take(ascending, 2)},
          {%{"cursor" => nil}, Enum.take(ascending, 2)},
          {%{"sortDirection" => nil}, Enum.take(ascending, 2)},
          {%{"cursor" => nil, "sortDirection" => nil}, Enum.take(ascending, 2)},
          {%{"sortDirection" => "asc"}, Enum.take(ascending, 2)},
          {%{"sortDirection" => "desc"}, ascending |> Enum.reverse() |> Enum.take(2)},
          {%{"cursor" => nil, "sortDirection" => "desc"},
           ascending |> Enum.reverse() |> Enum.take(2)}
        ] do
      page = request(ctx, pid, Map.merge(query, extra))
      assert Map.fetch!(page, "data") === expected
      assert is_binary(Map.fetch!(page, "nextCursor"))
    end
  end

  defp assert_opaque_pages(ctx, pid, query, expected, direction) do
    chunks = Enum.chunk_every(expected, 2)
    assert length(chunks) == 3
    initial = Map.put(query, "sortDirection", direction)

    {_params, _seen, observed} =
      Enum.reduce(Enum.with_index(chunks), {initial, [], []}, fn {rows, index},
                                                                 {params, seen, observed} ->
        page = request(ctx, pid, params)
        assert Map.fetch!(page, "data") === rows
        cursor = Map.fetch!(page, "nextCursor")

        if index == 2 do
          assert cursor == nil
        else
          assert is_binary(cursor) and cursor != ""
          refute cursor in seen
        end

        {Map.put(initial, "cursor", cursor), [cursor | seen], observed ++ page["data"]}
      end)

    assert observed === expected
  end

  defp assert_anchors(ctx, pid, thread, turn) do
    [user, assistant] = turn.entries

    cases = [
      {user, %{}, [assistant]},
      {user, %{"sortDirection" => nil}, [assistant]},
      {user, %{"sortDirection" => "asc"}, [assistant]},
      {user, %{"sortDirection" => "desc"}, []},
      {assistant, %{"sortDirection" => "desc"}, [user]},
      {assistant, %{"sortDirection" => "asc"}, []}
    ]

    for {anchor, direction, expected} <- cases do
      params = %{
        "threadId" => thread,
        "turnId" => turn.id,
        "limit" => 2,
        "cursor" => %{"type" => "item", "itemId" => anchor["item"]["id"]}
      }

      page = request(ctx, pid, Map.merge(params, direction))
      assert Map.fetch!(page, "data") === expected
      assert Map.fetch!(page, "nextCursor") == nil
      if expected == [], do: assert(Map.fetch!(page, "backwardsCursor") == nil)
    end
  end

  defp request(ctx, pid, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-item-anchor-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "thread/items/list", params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => "thread/items/list", "params" => params}
    result
  end

  defp event_entries(events, thread, turn, marker) do
    completed = item_events(events, "item/completed", thread, turn)
    assert Enum.map(completed, & &1["item"]["type"]) == ["userMessage", "agentMessage"]
    [user, assistant] = completed

    assert user["item"]["content"] == [
             %{"type" => "text", "text" => marker, "text_elements" => []}
           ]

    assert assistant["item"]["text"] == @answer

    Enum.map(completed, fn event ->
      item = Map.fetch!(event, "item")
      id = Map.fetch!(item, "id")
      assert is_binary(id) and id != ""

      assert [began] =
               Enum.filter(item_events(events, "item/started", thread, turn), fn notice ->
                 notice["item"]["id"] == id
               end)

      started = Map.fetch!(began, "startedAtMs")
      ended = Map.fetch!(event, "completedAtMs")
      assert is_integer(started) and started > 0
      assert is_integer(ended) and ended >= started

      %{
        "turnId" => turn,
        "item" => item,
        "startedAtMs" => started,
        "completedAtMs" => ended
      }
    end)
  end

  defp item_events(events, method, thread, turn) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["threadId"] == thread,
        event.wire["params"]["turnId"] == turn,
        do: event.wire["params"]
  end

  defp assert_history(history, turns) do
    actual = Map.fetch!(history, "turns")
    assert length(actual) == 3

    for {saved, expected} <- Enum.zip(actual, turns) do
      assert Map.fetch!(saved, "id") == expected.id
      assert Map.fetch!(saved, "status") == "completed"
      assert Map.fetch!(saved, "items") === Enum.map(expected.entries, & &1["item"])
    end
  end

  defp assert_provider(request, marker) do
    assert request["model"] == "mock-model"

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
  end

  defp complete_turn(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native item-anchor event buffer exceeded its bound"

    found =
      TurnFixture.notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if found do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} = found
      events
    else
      assert Session.status(pid).phase == :ready
      assert System.monotonic_time(:millisecond) < until, "native item-anchor turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during item-anchor turn")
      after
        10 -> :ok
      end

      complete_turn(pid, thread, turn, events, until)
    end
  end

  defp read(pid, thread),
    do:
      TurnFixture.call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]

  defp close(pid) do
    native = TurnFixture.call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
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
               %{"name" => "owned_item_anchor_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
