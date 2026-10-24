defmodule SamgitaCodexDriver.NativeResumePageFieldsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, upstream_error: 4]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @cases_file Path.join(__DIR__, "fixtures/native_resume_page_cases.json")
  @texts ["Owned resume first λ", "Owned resume second 🙂", "Owned resume third"]
  @answer "Deterministic local fixture answer"

  setup tags do
    ctx = TurnFixture.setup(tags)

    assert Base.encode16(:crypto.hash(:sha256, File.read!(ctx.binary)), case: :lower) ==
             @binary_sha

    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(ctx.root, "tmp"))
    ctx
  end

  test "initial pages retain native direction limit detail and null defaults", ctx do
    pid = start(ctx)
    {id, ids} = completed_history(ctx, pid, "paginated")

    for variant <- @cases_file |> File.read!() |> JSON.decode!() do
      expected_ids = if variant["direction"] == "asc", do: ids, else: Enum.reverse(ids)
      expected_ids = Enum.take(expected_ids, variant["count"])

      # Compare the complete native pages, including cursor keys and exact nulls,
      # then independently assert the expected identities and content. Equality
      # alone would miss a shared default/direction error in both operations.
      expected =
        call(pid, "thread/turns/list", Map.put(variant["params"], "threadId", id))

      resumed =
        resume(pid, id, %{
          "excludeTurns" => true,
          "initialTurnsPage" => variant["params"]
        })

      assert resumed["thread"]["id"] == id, variant["name"]
      assert resumed["thread"]["turns"] == [], variant["name"]
      assert Map.fetch!(resumed, "initialTurnsPage") == expected, variant["name"]
      assert Enum.map(expected["data"], & &1["id"]) == expected_ids, variant["name"]

      for turn <- expected["data"] do
        assert turn["status"] == "completed"
        assert turn["itemsView"] == variant["view"]

        if variant["view"] == "notLoaded" do
          assert turn["items"] == []
        else
          assert_text_turn(turn, Enum.at(@texts, Enum.find_index(ids, &(&1 == turn["id"]))))
        end
      end

      if variant["count"] < length(ids) do
        assert is_binary(Map.fetch!(expected, "nextCursor"))
      else
        assert Map.fetch!(expected, "nextCursor") == nil
      end

      assert is_binary(Map.fetch!(expected, "backwardsCursor"))
      assert_no_execution(ctx, pid, 3)
    end
  end

  for mode <- ["legacy", "paginated"] do
    @history_mode mode
    test "#{mode} resume keeps hydration independent from omitted null or requested initial page",
         ctx do
      pid = start(ctx)
      {id, ids} = completed_history(ctx, pid, @history_mode)

      for extra <- [
            %{"excludeTurns" => true},
            %{"excludeTurns" => true, "initialTurnsPage" => nil}
          ] do
        response = resume(pid, id, extra)
        assert response["thread"]["id"] == id
        assert response["thread"]["turns"] == []
        assert Map.fetch!(response, "initialTurnsPage") == nil
        assert_no_execution(ctx, pid, 3)
      end

      for extra <- [
            %{},
            %{"excludeTurns" => false},
            %{"excludeTurns" => false, "initialTurnsPage" => nil}
          ] do
        response = resume(pid, id, extra)
        assert_full_history(response["thread"]["turns"], ids)
        assert Map.fetch!(response, "initialTurnsPage") == nil
        assert_no_execution(ctx, pid, 3)
      end

      response = resume(pid, id, %{"excludeTurns" => false, "initialTurnsPage" => %{}})
      assert_full_history(response["thread"]["turns"], ids)
      page = Map.fetch!(response, "initialTurnsPage")
      assert Enum.map(page["data"], & &1["id"]) == Enum.reverse(ids)
      assert Enum.all?(page["data"], &(&1["itemsView"] == "summary"))
      assert Map.fetch!(page, "nextCursor") == nil
      assert is_binary(Map.fetch!(page, "backwardsCursor"))

      if @history_mode == "legacy" do
        assert Map.fetch!(response, "turnsBackwardsCursor") == nil
        assert Map.fetch!(response, "itemsBackwardsCursor") == nil
      else
        assert is_binary(Map.fetch!(response, "turnsBackwardsCursor"))
        assert is_binary(Map.fetch!(response, "itemsBackwardsCursor"))
      end

      assert_no_execution(ctx, pid, 3)
    end
  end

  test "native page continuation and both inclusive hydration cursors survive cold restart",
       ctx do
    pid = start(ctx)
    {id, [first, second, third]} = completed_history(ctx, pid, "paginated")
    params = %{"limit" => 2, "sortDirection" => "desc", "itemsView" => "full"}
    hot = resume(pid, id, %{"excludeTurns" => true, "initialTurnsPage" => params})
    page = Map.fetch!(hot, "initialTurnsPage")
    assert Enum.map(page["data"], & &1["id"]) == [third, second]

    continuation = params |> Map.put("threadId", id) |> Map.put("cursor", page["nextCursor"])
    older = call(pid, "thread/turns/list", continuation)
    assert Enum.map(older["data"], & &1["id"]) == [first]
    assert Map.fetch!(older, "nextCursor") == nil

    turns_cursor = Map.fetch!(hot, "turnsBackwardsCursor")
    items_cursor = Map.fetch!(hot, "itemsBackwardsCursor")
    assert is_binary(turns_cursor)
    assert is_binary(items_cursor)

    turn_query = %{
      "threadId" => id,
      "cursor" => turns_cursor,
      "limit" => 1,
      "sortDirection" => "desc",
      "itemsView" => "full"
    }

    newest = call(pid, "thread/turns/list", turn_query)
    assert Enum.map(newest["data"], & &1["id"]) == [third]
    assert_text_turn(hd(newest["data"]), List.last(@texts))

    # A backwards cursor includes the newest stored item; ordinary continuation
    # nextCursor excludes the previous page. Check those meanings independently.
    items_query = %{"threadId" => id, "sortDirection" => "desc", "limit" => 100}
    all_items = call(pid, "thread/items/list", items_query)
    assert Map.fetch!(all_items, "nextCursor") == nil
    assert Enum.map(all_items["data"], & &1["turnId"]) |> Enum.uniq() == [third, second, first]
    item_query = Map.put(items_query, "cursor", items_cursor)
    assert call(pid, "thread/items/list", item_query) == all_items
    process = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert :ok = Session.close(pid)

    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == process
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert call(cold, "thread/turns/list", continuation) == older
    assert call(cold, "thread/turns/list", turn_query) == newest
    assert call(cold, "thread/items/list", item_query) == all_items
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    resumed = resume(cold, id, %{"excludeTurns" => true, "initialTurnsPage" => params})
    assert resumed["thread"]["id"] == id
    assert resumed["thread"]["turns"] == []
    assert Map.fetch!(resumed, "initialTurnsPage") == page
    assert call(cold, "thread/loaded/list", %{})["data"] == [id]
    assert_no_execution(ctx, cold, 3)
  end

  test "native malformed nested page fields and stable negotiation cannot replay completed work",
       ctx do
    pid = start(ctx)
    {id, ids} = completed_history(ctx, pid, "paginated")

    for page <- [
          17,
          %{"limit" => -1},
          %{"limit" => 4_294_967_296},
          %{"sortDirection" => "sideways"},
          %{"itemsView" => "everything"}
        ] do
      error =
        upstream_error(pid, "thread/resume", %{"threadId" => id, "initialTurnsPage" => page},
          validation: :wire
        )

      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert_no_execution(ctx, pid, 3)
    end

    assert_full_history(resume(pid, id, %{"excludeTurns" => false})["thread"]["turns"], ids)
    assert :ok = Session.close(pid)
    stable = start(ctx, experimental: false)
    params = %{"threadId" => id, "excludeTurns" => true, "initialTurnsPage" => %{}}

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(stable, "thread/resume", params)

    assert upstream_error(stable, "thread/resume", params, validation: :wire) == %{
             "code" => -32_600,
             "message" => "thread/resume.initialTurnsPage requires experimentalApi capability"
           }

    assert call(stable, "thread/loaded/list", %{})["data"] == []
    assert_no_execution(ctx, stable, 3)
    # Explicit null does not activate an Option-valued experimental field.
    response = resume(stable, id, %{"excludeTurns" => true, "initialTurnsPage" => nil})
    assert response["thread"]["id"] == id
    assert response["thread"]["turns"] == []
    assert_no_execution(ctx, stable, 3)
  end

  defp start(ctx, opts \\ []) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args: ["app-server", "--listen", "stdio://"],
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(fixture.bin, "sh"),
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
               %{"name" => "samgita_resume_page_fields", "version" => "0.1.0"},
               %{"experimentalApi" => Keyword.get(opts, :experimental, true)}
             )

    pid
  end

  defp completed_history(ctx, pid, mode) do
    id = TurnFixture.thread(ctx, pid, %{"historyMode" => mode})

    ids =
      for text <- @texts do
        turn = TurnFixture.start_turn(pid, id, [%{"type" => "text", "text" => text}])
        TurnFixture.finish_turn(pid, id, turn)
        turn
      end

    # Native persistence/projection barrier, not an index polling loop.
    assert_full_history(
      call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]["turns"],
      ids
    )

    assert_no_execution(ctx, pid, 3)
    {id, ids}
  end

  defp resume(pid, id, extra), do: call(pid, "thread/resume", Map.put(extra, "threadId", id))

  defp assert_full_history(turns, ids) do
    assert Enum.map(turns, & &1["id"]) == ids
    for {turn, text} <- Enum.zip(turns, @texts), do: assert_text_turn(turn, text)
  end

  defp assert_text_turn(turn, text) do
    assert turn["status"] == "completed"
    user = Enum.find(turn["items"], &(&1["type"] == "userMessage"))
    assert user
    assert Enum.any?(user["content"], &(&1["type"] == "text" and &1["text"] == text))
    agent = Enum.find(turn["items"], &(&1["type"] == "agentMessage"))
    assert agent
    assert agent["text"] == @answer
  end

  defp assert_no_execution(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
