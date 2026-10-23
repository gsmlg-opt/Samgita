defmodule SamgitaCodexDriver.NativeProjectsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @missing_thread "67e55044-10b1-426f-9247-bb680e5fe0c8"

  setup context do
    context = TurnFixture.setup(context)

    File.write!(
      Path.join(context.fixture.codex_home, "config.toml"),
      "\n[features]\nsqlite = true\n",
      [:append]
    )

    context
  end

  test "project creation is durable and idempotent while invalid roots and keys preserve state",
       context do
    pid = start(context, experimental: true)

    params = %{
      "name" => "  Synthetic project  ",
      "roots" => roots(context),
      "metadata" => %{"color" => "blue"},
      "idempotencyKey" => "fixture-create"
    }

    created = call(pid, "project/create", params)["project"]
    assert created["name"] == "Synthetic project"
    assert created["roots"] == params["roots"]
    assert created["metadata"] == params["metadata"]
    assert is_integer(created["createdAt"])
    assert is_integer(created["updatedAt"])
    assert created["recencyAt"] == nil
    assert changes(pid) == [project_change(created, "created")]

    replay = Map.merge(params, %{"name" => "Changed replay", "roots" => [], "metadata" => %{}})
    assert call(pid, "project/create", replay)["project"] == created
    assert project(pid, created) == created
    assert changes(pid) == []

    alias_path = Path.join(context.root, "workspace-alias")
    File.ln_s!(context.fixture.workspace, alias_path)

    for {invalid, message} <- [
          {%{"name" => " \n "}, "project name must not be empty"},
          {%{"idempotencyKey" => " "}, "idempotencyKey must not be empty"},
          {%{"idempotencyKey" => String.duplicate("k", 513)},
           "idempotencyKey must be at most 512 bytes"},
          {%{"roots" => roots(context) ++ roots(context)}, "duplicate project root"},
          {%{"roots" => roots(context) ++ [%{"path" => alias_path}]},
           "duplicate resolved project root"}
        ] do
      error = upstream_error(pid, "project/create", Map.merge(params, invalid))
      assert error["code"] == -32_602
      assert error["message"] =~ message
      assert projects(pid) == [created]
      assert changes(pid) == []
    end

    resumed = restart(context, pid)
    assert project(resumed, created) == created
    assert projects(resumed) == [created]
    assert ModelFixture.requests(context.fixture) == []
  end

  test "project import commits membership atomically and replay does not reassign threads",
       context do
    pid = start(context, experimental: true)
    id = persisted_thread(context, pid, "Synthetic imported history")
    ephemeral = thread(context, pid, %{"ephemeral" => true})
    assert changes(pid) == []

    for {ids, message} <- [
          {[id, id], "duplicate thread id"},
          {[id, @missing_thread], "thread not found"},
          {[id, ephemeral], "thread not found"}
        ] do
      error =
        upstream_error(pid, "project/import", %{
          "name" => "Rejected import",
          "roots" => [],
          "threads" => ids,
          "idempotencyKey" => "rejected-#{List.last(ids)}"
        })

      assert error["code"] == -32_602
      assert error["message"] =~ message
      assert projects(pid) == []
      assert read_thread(pid, id)["projectId"] == nil
      assert changes(pid) == []
    end

    params = %{
      "name" => "Imported project",
      "roots" => roots(context),
      "threads" => [id],
      "idempotencyKey" => "fixture-import"
    }

    imported = call(pid, "project/import", params)["project"]

    assert changes(pid) == [
             project_change(imported, "created"),
             thread_change(id, imported["id"])
           ]

    assert read_thread(pid, id)["projectId"] == imported["id"]
    assert thread_ids(pid, %{"projectId" => imported["id"]}) == [id]
    assert thread_ids(pid, %{"projectId" => nil}) == []

    replay = Map.merge(params, %{"name" => "Ignored replay", "threads" => []})
    assert call(pid, "project/import", replay)["project"] == imported
    assert projects(pid) == [imported]
    assert read_thread(pid, id)["projectId"] == imported["id"]
    assert changes(pid) == []

    resumed = restart(context, pid)

    assert call(resumed, "thread/resume", %{"threadId" => id})["thread"]["projectId"] ==
             imported["id"]

    assert thread_ids(resumed, %{"projectId" => imported["id"]}) == [id]
    assert length(ModelFixture.requests(context.fixture)) == 1
  end

  test "project updates preserve omitted and null fields and clear explicit empty collections",
       context do
    pid = start(context, experimental: true)
    created = create(pid, "Original", roots(context), %{"color" => "blue"})

    id =
      persisted_thread(context, pid, "Synthetic update membership", %{
        "projectId" => created["id"]
      })

    original = project(pid, created)
    changes(pid)

    for fields <- [%{}, %{"name" => nil, "roots" => nil, "metadata" => nil}] do
      assert call(pid, "project/update", Map.put(fields, "projectId", created["id"]))["project"] ==
               original

      assert project(pid, created) == original
      assert changes(pid) == []
    end

    params = %{
      "projectId" => created["id"],
      "name" => "  Renamed  ",
      "roots" => [],
      "metadata" => %{}
    }

    updated = call(pid, "project/update", params)["project"]
    assert updated["id"] == original["id"]
    assert updated["name"] == "Renamed"
    assert updated["roots"] == []
    assert updated["metadata"] == %{}
    assert updated["createdAt"] == original["createdAt"]
    assert updated["recencyAt"] == original["recencyAt"]
    assert changes(pid) == [project_change(updated, "updated")]
    assert read_thread(pid, id)["projectId"] == updated["id"]

    assert call(pid, "project/update", params)["project"] == updated
    assert changes(pid) == []

    assert upstream_error(pid, "project/update", %{"projectId" => updated["id"], "name" => " "})[
             "code"
           ] == -32_602

    assert project(pid, updated) == updated
    assert changes(pid) == []
    assert length(ModelFixture.requests(context.fixture)) == 1
  end

  test "project movement and pagination preserve position while recency excludes archived members",
       context do
    pid = start(context, experimental: true)
    first = create(pid, "First")
    second = create(pid, "Second")
    empty = create(pid, "Empty")
    persisted_thread(context, pid, "Synthetic first recency", %{"projectId" => first["id"]})

    second_thread =
      persisted_thread(context, pid, "Synthetic second recency", %{"projectId" => second["id"]})

    changes(pid)

    assert call(pid, "project/move", %{
             "projectId" => empty["id"],
             "beforeProjectId" => first["id"]
           }) == %{}

    assert changes(pid) == [project_change(empty, "updated")]
    assert project_pages(pid) == [empty["id"], first["id"], second["id"]]

    recent = projects(pid, %{"sortKey" => "recencyAt"})
    assert List.last(recent)["id"] == empty["id"]

    assert MapSet.new(Enum.map(Enum.take(recent, 2), & &1["id"])) ==
             MapSet.new([first["id"], second["id"]])

    assert Enum.all?(Enum.take(recent, 2), &is_integer(&1["recencyAt"]))
    assert call(pid, "thread/archive", %{"threadId" => second_thread}) == %{}
    assert project(pid, second)["recencyAt"] == nil
    assert project(pid, first)["recencyAt"] != nil

    for params <- [
          %{"sortDirection" => "desc"},
          %{"sortKey" => "recencyAt", "cursor" => "0|#{first["id"]}"}
        ] do
      assert upstream_error(pid, "project/list", params)["code"] == -32_602
    end

    assert project_pages(pid) == [empty["id"], first["id"], second["id"]]
    assert length(ModelFixture.requests(context.fixture)) == 2
  end

  test "deleting a project clears membership and preserves cold-resumed thread history and files",
       context do
    pid = start(context, experimental: true)
    created = create(pid, "Disposable classification", roots(context))
    sentinel = Path.join(context.fixture.workspace, "preserved.txt")
    File.write!(sentinel, "Synthetic project deletion must preserve this file")

    id =
      persisted_thread(context, pid, "Synthetic preserved first turn", %{
        "projectId" => created["id"]
      })

    turn = start_turn(pid, id, [%{"type" => "text", "text" => "Synthetic preserved second turn"}])
    finish_turn(pid, id, turn)
    before_delete = history(pid, id)
    assert length(before_delete) == 2
    changes(pid)

    assert call(pid, "project/delete", %{"projectId" => created["id"]}) == %{}
    assert changes(pid) == [project_change(created, "deleted"), thread_change(id, nil)]
    assert upstream_error(pid, "project/read", %{"projectId" => created["id"]})["code"] == -32_602
    assert projects(pid) == []
    assert read_thread(pid, id)["projectId"] == nil
    assert history(pid, id) == before_delete
    assert thread_ids(pid, %{"projectId" => nil}) == [id]
    assert File.read!(sentinel) == "Synthetic project deletion must preserve this file"

    resumed = restart(context, pid)
    assert call(resumed, "thread/resume", %{"threadId" => id})["thread"]["projectId"] == nil
    assert history(resumed, id) == before_delete
    assert thread_ids(resumed, %{"projectId" => nil}) == [id]
    assert File.read!(sentinel) == "Synthetic project deletion must preserve this file"
    assert length(ModelFixture.requests(context.fixture)) == 2
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(resumed)
  end

  defp roots(context), do: [%{"path" => context.fixture.workspace}]

  defp create(pid, name, roots \\ [], metadata \\ %{}) do
    call(pid, "project/create", %{
      "name" => name,
      "roots" => roots,
      "metadata" => metadata,
      "idempotencyKey" => "fixture-#{name}"
    })["project"]
  end

  defp project(pid, project),
    do: call(pid, "project/read", %{"projectId" => project["id"]})["project"]

  defp projects(pid, params \\ %{}), do: call(pid, "project/list", params)["data"]

  defp persisted_thread(context, pid, text, extra \\ %{}) do
    id = thread(context, pid, extra)
    turn = start_turn(pid, id, [%{"type" => "text", "text" => text}])
    finish_turn(pid, id, turn)
    id
  end

  defp read_thread(pid, id), do: call(pid, "thread/read", %{"threadId" => id})["thread"]

  defp thread_ids(pid, params) do
    params =
      Map.merge(%{"modelProviders" => [], "sourceKinds" => [], "useStateDbOnly" => true}, params)

    Enum.map(call(pid, "thread/list", params)["data"], & &1["id"])
  end

  defp history(pid, id) do
    call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]["turns"]
    |> Enum.map(fn turn ->
      {turn["id"], Enum.map(turn["items"], &Map.take(&1, ["id", "type", "text", "content"]))}
    end)
  end

  defp restart(context, pid) do
    count = length(ModelFixture.requests(context.fixture))
    assert :ok = Session.close(pid)
    resumed = start(context, experimental: true)
    assert length(ModelFixture.requests(context.fixture)) == count
    resumed
  end

  defp project_pages(pid, cursor \\ nil, ids \\ []) do
    page = call(pid, "project/list", %{"limit" => 1, "cursor" => cursor})
    assert [project] = page["data"]
    refute project["id"] in ids
    ids = ids ++ [project["id"]]
    if page["nextCursor"], do: project_pages(pid, page["nextCursor"], ids), else: ids
  end

  # Session returns RPC results separately. These assertions cover only the
  # order and association of buffered notifications, not their wire order
  # relative to the RPC response.
  defp changes(pid) do
    assert {:ok, events} = Session.drain(pid)

    for event <- events, event.wire["method"] in ["project/changed", "thread/project/updated"] do
      Map.take(event.wire, ["method", "params"])
    end
  end

  defp project_change(project, change) do
    %{
      "method" => "project/changed",
      "params" => %{"projectId" => project["id"], "changeType" => change}
    }
  end

  defp thread_change(id, project_id) do
    %{
      "method" => "thread/project/updated",
      "params" => %{"threadId" => id, "projectId" => project_id}
    }
  end
end
