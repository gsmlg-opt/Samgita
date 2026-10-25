defmodule SamgitaCodexDriver.NativeTurnListNullValuesTest do
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
  @instructions "Owned fixed turn-list null fixture instructions."
  @markers [
    "owned-turn-list-null-first λ",
    "owned-turn-list-null-middle 🙂",
    "owned-turn-list-null-last"
  ]
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

      if wire["method"] in ["thread/turns/list", "thread/archive"] do
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

  test "native null turn-list defaults retain completed summaries through an owned archive",
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
    assert Map.fetch!(thread, "historyMode") == "paginated"
    assert ModelFixture.requests(ctx.fixture) == []

    turns =
      for {marker, count} <- Enum.with_index(@markers, 1) do
        turn =
          TurnFixture.call(pid, "turn/start", %{
            "threadId" => id,
            "input" => [%{"type" => "text", "text" => marker}]
          })["turn"]["id"]

        {_notice, events} =
          await_notice(
            pid,
            "turn/completed",
            &(&1["threadId"] == id and &1["turn"]["id"] == turn),
            [],
            deadline(20_000)
          )

        items = completed_items(events, id, turn, marker)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == count
        assert_provider(List.last(requests), marker)
        %{id: turn, items: items}
      end

    assert turns |> Enum.map(& &1.id) |> Enum.uniq() |> length() == 3
    original = read(pid, id)
    assert_history(original, id, turns)
    original_path = Map.fetch!(original, "path")
    assert File.regular?(original_path)
    journal = File.read!(ctx.fixture.requests)
    assert_membership(ctx, pid, false, [id])
    assert_membership(ctx, pid, true, [])
    query = %{"threadId" => id, "limit" => 2}
    assert_null_pages(ctx, pid, query, turns)
    assert_null_continuation(ctx, pid, id, turns)
    before_archive = read(pid, id)
    assert_history(before_archive, id, turns)
    assert before_archive["turns"] === original["turns"]
    assert File.read!(ctx.fixture.requests) == journal

    assert request(ctx, pid, "thread/archive", %{"threadId" => id}) == %{}

    {archived, _events} =
      await_notice(pid, "thread/archived", &(&1["threadId"] == id), [], deadline(5000))

    assert Map.fetch!(archived, "threadId") == id
    assert_membership(ctx, pid, false, [])
    assert_membership(ctx, pid, true, [id])

    # Archived history remains available by its stable ID. Observe the actual
    # completed operation; no rollout-byte flush or restart ordering is assumed.
    retained = read(pid, id)
    assert_history(retained, id, turns)
    assert retained["turns"] === original["turns"]
    assert retained["preview"] == original["preview"]
    archived_path = Map.fetch!(retained, "path")
    assert is_binary(archived_path) and archived_path != original_path
    assert Path.basename(archived_path) == Path.basename(original_path)
    assert Path.dirname(archived_path) == Path.join(ctx.fixture.codex_home, "archived_sessions")
    assert File.regular?(archived_path)

    page =
      request(
        ctx,
        pid,
        "thread/turns/list",
        Map.merge(query, %{
          "itemsView" => nil,
          "sortDirection" => nil
        })
      )

    assert_page(page, turns |> Enum.reverse() |> Enum.take(2), "summary")
    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    captures = Agent.get(ctx.capture, & &1)
    assert Enum.count(captures, &(&1["method"] == "thread/turns/list")) == 12
    assert Enum.count(captures, &(&1["method"] == "thread/archive")) == 1
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = close(pid)
  end

  defp assert_null_pages(ctx, pid, query, turns) do
    descending = turns |> Enum.reverse() |> Enum.take(2)
    ascending = Enum.take(turns, 2)

    # These two-item turns have identical summary/full contents. The empty
    # notLoaded control distinguishes detail loading, not general truncation.
    for {extra, expected, view} <- [
          {%{}, descending, "summary"},
          {%{"itemsView" => nil}, descending, "summary"},
          {%{"sortDirection" => nil}, descending, "summary"},
          {%{"itemsView" => nil, "sortDirection" => nil}, descending, "summary"},
          {%{"itemsView" => "summary", "sortDirection" => "desc"}, descending, "summary"},
          {%{"itemsView" => "full", "sortDirection" => "asc"}, ascending, "full"},
          {%{"itemsView" => "notLoaded", "sortDirection" => nil}, descending, "notLoaded"},
          {%{"itemsView" => nil, "sortDirection" => "asc"}, ascending, "summary"}
        ] do
      page = request(ctx, pid, "thread/turns/list", Map.merge(query, extra))
      assert_page(page, expected, view)
      assert is_binary(Map.fetch!(page, "nextCursor"))
    end
  end

  defp assert_null_continuation(ctx, pid, thread, turns) do
    initial = %{
      "threadId" => thread,
      "limit" => 1,
      "itemsView" => nil,
      "sortDirection" => nil
    }

    {_params, _cursors, seen} =
      Enum.reduce(Enum.with_index(Enum.reverse(turns)), {initial, [], []}, fn {turn, index},
                                                                              {params, cursors,
                                                                               seen} ->
        page = request(ctx, pid, "thread/turns/list", params)
        assert_page(page, [turn], "summary")
        cursor = Map.fetch!(page, "nextCursor")

        if index == 2 do
          assert cursor == nil
        else
          assert is_binary(cursor) and cursor != ""
          refute cursor in cursors
        end

        {Map.put(initial, "cursor", cursor), [cursor | cursors], seen ++ [turn.id]}
      end)

    assert seen == Enum.map(Enum.reverse(turns), & &1.id)
  end

  defp assert_page(page, expected, view) do
    actual = Map.fetch!(page, "data")
    assert Enum.map(actual, & &1["id"]) == Enum.map(expected, & &1.id)

    for {turn, prescribed} <- Enum.zip(actual, expected) do
      assert Map.fetch!(turn, "status") == "completed"
      assert Map.fetch!(turn, "itemsView") == view
      items = if view == "notLoaded", do: [], else: prescribed.items
      assert Map.fetch!(turn, "items") === items
    end
  end

  defp assert_membership(ctx, pid, archived, expected) do
    page =
      TurnFixture.call(pid, "thread/list", %{
        "archived" => archived,
        "cwd" => ctx.fixture.workspace,
        "modelProviders" => ["fixture"],
        "limit" => 20
      })

    assert Enum.map(Map.fetch!(page, "data"), & &1["id"]) == expected
    assert Map.fetch!(page, "nextCursor") == nil
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-turn-list-null-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp completed_items(events, thread, turn, marker) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             TurnFixture.notification(events, "turn/completed", fn params ->
               params["threadId"] == thread and params["turn"]["id"] == turn
             end)

    completed =
      for event <- events,
          event.wire["method"] == "item/completed",
          event.wire["params"]["threadId"] == thread,
          event.wire["params"]["turnId"] == turn,
          do: Map.fetch!(event.wire["params"], "item")

    assert Enum.map(completed, & &1["type"]) == ["userMessage", "agentMessage"]
    [user, assistant] = completed

    assert Map.fetch!(user, "content") == [
             %{"type" => "text", "text" => marker, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "text") == @answer
    assert Enum.all?(completed, &(is_binary(&1["id"]) and &1["id"] != ""))
    assert user["id"] != assistant["id"]
    completed
  end

  defp assert_history(history, id, turns) do
    assert Map.fetch!(history, "id") == id
    actual = Map.fetch!(history, "turns")
    assert length(actual) == 3

    for {saved, expected} <- Enum.zip(actual, turns) do
      assert Map.fetch!(saved, "id") == expected.id
      assert Map.fetch!(saved, "status") == "completed"
      assert Map.fetch!(saved, "items") === expected.items
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

  defp await_notice(pid, method, predicate, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native turn-list null event buffer exceeded its bound"

    case TurnFixture.notification(events, method, predicate) do
      nil ->
        assert Session.status(pid).phase == :ready

        assert System.monotonic_time(:millisecond) < until,
               "native turn-list null #{method} deadline"

        receive do
          {:codex_driver, ^pid, :events_available} ->
            :ok

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected event gap during turn-list null scenario")
        after
          10 -> :ok
        end

        await_notice(pid, method, predicate, events, until)

      notice ->
        {notice, events}
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
               %{"name" => "owned_turn_list_null_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
