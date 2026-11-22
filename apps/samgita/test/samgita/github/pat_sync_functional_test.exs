defmodule Samgita.GitHub.PatSyncFunctionalTest do
  use Samgita.DataCase, async: false

  alias Samgita.Domain.{
    GitHubPatConnection,
    GitHubPatItem,
    GitHubPatRepositorySync,
    GitHubPatSelection,
    GitHubPatWorkflowSnapshot
  }

  alias Samgita.GitHub.{Console, PatCipher, PatClient, PatDashboard, PatSync, PatWorkflowRuns}

  alias Samgita.Workers.{
    GitHubPatRepositorySyncWorker,
    GitHubPatSyncWorker,
    GitHubPatWorkflowWorker
  }

  defmodule FixtureClient do
    def workflow_runs(_token, repository), do: Process.get(:workflow_reply).(repository)

    def sync_repository(_token, repository) do
      Process.put(:sync_calls, [repository | Process.get(:sync_calls, [])])

      case Process.get(:sync_outcome) do
        callback when is_function(callback, 0) -> callback.()
        value -> value
      end
    end
  end

  defmodule FixtureHTTP do
    def request(:get, url, _headers, nil, _opts) do
      uri = URI.parse(url)
      params = URI.decode_query(uri.query || "")
      Process.put(:sync_http_calls, [{uri.path, params} | Process.get(:sync_http_calls, [])])

      case Process.get(:sync_http_reply).(uri.path, params) do
        {:rate_limit, seconds} ->
          {:ok, %{status: 429, headers: [{"retry-after", to_string(seconds)}], body: "{}"}}

        {items, :next} ->
          query =
            URI.encode_query(
              Map.put(params, "page", to_string(String.to_integer(params["page"]) + 1))
            )

          {:ok,
           %{
             status: 200,
             headers: [{"link", "<https://api.github.com#{uri.path}?#{query}>; rel=\"next\""}],
             body: Jason.encode!(items)
           }}

        body ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(body)}}
      end
    end
  end

  setup do
    for {key, value} <- [
          github_console_client: FixtureClient,
          github_pat_key_base: String.duplicate("sync-fixture", 4)
        ] do
      original = Application.fetch_env(:samgita, key)
      Application.put_env(:samgita, key, value)

      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:samgita, key, value)
          :error -> Application.delete_env(:samgita, key)
        end
      end)
    end

    id = Ecto.UUID.generate()
    {:ok, ciphertext} = PatCipher.seal("synthetic-sync-fixture", id, 5)

    connection =
      Repo.insert!(%GitHubPatConnection{
        id: id,
        github_id: 5,
        login: "operator",
        ciphertext: ciphertext,
        credential_version: Ecto.UUID.generate(),
        version: Ecto.UUID.generate()
      })

    Repo.insert!(%GitHubPatSelection{
      connection_id: id,
      github_id: 41,
      owner_id: 7,
      owner: "sample",
      name: "one"
    })

    Process.put(
      :sync_outcome,
      {:ok,
       %{
         repository: repository(),
         items: [item(1, "issue", "open"), item(2, "pull_request", "open")]
       }}
    )

    Process.put(:sync_calls, [])
    Process.put(:sync_http_calls, [])
    {:ok, connection: connection}
  end

  test "request only queues dispatcher signals and repository dispatch coalesces without network",
       %{connection: row} do
    assert :ok = PatSync.request()
    assert :ok = PatSync.request()

    dispatchers =
      Repo.all(from j in Styx.Job, where: j.worker == "Samgita.Workers.GitHubPatSyncWorker")

    assert length(dispatchers) == 2

    for dispatcher <- dispatchers do
      assert dispatcher.args == %{"mode" => "open"}
      assert :ok = GitHubPatSyncWorker.perform(dispatcher)
    end

    assert Enum.count(
             Repo.all(Styx.Job),
             &(&1.worker == "Samgita.Workers.GitHubPatRepositorySyncWorker")
           ) == 1

    assert sync(row).job_id
    assert Process.get(:sync_calls) == []
  end

  test "full repository publication includes both kinds and records its start watermark", %{
    connection: row
  } do
    job = dispatch(row, "full")
    before = DateTime.utc_now()
    assert :ok = GitHubPatRepositorySyncWorker.perform(job)
    after_read = DateTime.utc_now()
    assert Enum.map(items(row), &{&1.kind, &1.number}) == [{"issue", 1}, {"pull_request", 2}]
    assert DateTime.compare(sync(row).synced_at, before) in [:gt, :eq]
    assert DateTime.compare(sync(row).synced_at, after_read) in [:lt, :eq]
    assert sync(row).owner_id == 7
    assert [%{id: 41}] = Process.get(:sync_calls)
  end

  test "repository sync queues only this repository and persists the issue metadata and PR revision",
       %{connection: row} do
    Repo.insert!(%GitHubPatSelection{
      connection_id: row.id,
      github_id: 42,
      owner_id: 7,
      owner: "sample",
      name: "two"
    })

    sha = String.duplicate("a", 40)

    Process.put(:sync_http_reply, fn
      "/repositories/41", _ ->
        raw_repository()

      "/repos/sample/one/issues", %{"state" => "open"} ->
        [
          Map.merge(raw_item(1), %{
            "type" => %{"name" => "Bug"},
            "labels" => [
              %{"name" => "priority", "color" => "D73A4A"},
              %{"name" => "backend", "color" => "0075CA"},
              %{"name" => "neutral", "color" => "#123456"},
              %{"name" => "missing"},
              "legacy"
            ]
          })
        ]

      "/repos/sample/one/pulls", %{"state" => "open"} ->
        [
          raw_item(2)
          |> Map.put("head", %{"sha" => sha})
          |> Map.put("labels", [%{"name" => "ready", "color" => "00FF7F"}])
        ]
    end)

    Process.put(:sync_outcome, fn ->
      PatClient.sync_repository("synthetic", repository(), http_opts())
    end)

    assert :ok = PatSync.request_repository(row, 41)
    job = Repo.get!(Styx.Job, sync(row).job_id)
    assert :ok = PatSync.request_repository(row, 41)
    assert [^job] = Repo.all(Styx.Job)
    assert :ok = GitHubPatRepositorySyncWorker.perform(job)
    detail = PatDashboard.repository(Console.settings(), 41)

    assert [
             %{
               title: "Work 1",
               author: "author",
               issue_type: "Bug",
               labels: ["priority", "backend", "neutral", "missing", "legacy"],
               label_colors: %{"priority" => "d73a4a", "backend" => "0075ca"}
             }
           ] = detail.issues.rows

    assert [%{number: 2, head_sha: ^sha, labels: ["ready"], label_colors: %{"ready" => "00ff7f"}}] =
             detail.pulls.rows

    assert Repo.get_by(GitHubPatRepositorySync, connection_id: row.id, repository_id: 42) == nil
  end

  test "sync replaces and clears label colors together with names while legacy items stay neutral",
       %{connection: row} do
    colored =
      Map.merge(item(1, "issue", "open"), %{
        labels: ["priority", "backend"],
        label_colors: %{"priority" => "d73a4a", "backend" => "0075ca"}
      })

    Process.put(
      :sync_outcome,
      {:ok, %{repository: repository(), items: [colored, item(2, "pull_request", "open")]}}
    )

    complete(dispatch(row, "open"))

    assert [
             %{
               labels: ["priority", "backend"],
               label_colors: %{"priority" => "d73a4a", "backend" => "0075ca"}
             }
           ] =
             PatDashboard.repository(Console.settings(), 41).issues.rows

    assert [%{label_colors: %{}}] = PatDashboard.repository(Console.settings(), 41).pulls.rows

    updated = Map.merge(colored, %{labels: ["priority"], label_colors: %{"priority" => "000000"}})
    Process.put(:sync_outcome, {:ok, %{repository: repository(), items: [updated]}})
    complete(dispatch(row, "open"))

    assert [%{labels: ["priority"], label_colors: %{"priority" => "000000"}}] =
             PatDashboard.repository(Console.settings(), 41).issues.rows

    legacy = Map.put(item(1, "issue", "open"), :labels, [])
    Process.put(:sync_outcome, {:ok, %{repository: repository(), items: [legacy]}})
    complete(dispatch(row, "open"))

    assert [%{labels: [], label_colors: %{}}] =
             PatDashboard.repository(Console.settings(), 41).issues.rows

    assert Enum.find(items(row), &(&1.number == 1)).label_colors == %{}
  end

  test "workflow snapshots coalesce readers and poll only when an active run is due", %{
    connection: row
  } do
    assert %{status: :uninitialized, rows: []} = PatWorkflowRuns.read(row, 41)
    assert :ok = PatWorkflowRuns.request(row, 41, :poll)
    assert Repo.all(Styx.Job) == []
    assert :ok = PatWorkflowRuns.request(row, 41, :initial)
    job = workflow_job(row)
    assert :ok = PatWorkflowRuns.request(row, 41, :manual)
    assert :ok = PatWorkflowRuns.request(row, 41, :initial)
    assert [^job] = Repo.all(Styx.Job)
    assert %{status: :refreshing} = PatWorkflowRuns.read(row, 41)
    Console.subscribe_repository(41)
    workflow_reply("in_progress")
    assert :ok = GitHubPatWorkflowWorker.perform(job)
    assert_receive {:github_workflow_runs_changed, 41}

    assert %{
             status: :ready,
             active?: true,
             rows: [%{id: 8, url: "https://github.com/sample/one/actions/runs/8"}]
           } =
             PatWorkflowRuns.read(row, 41)

    assert :ok = PatWorkflowRuns.request(row, 41, :poll)
    assert [^job] = Repo.all(Styx.Job)

    snapshot = workflow_snapshot(row)
    Repo.update!(change(snapshot, synced_at: DateTime.add(snapshot.synced_at, -11, :second)))
    assert :ok = PatWorkflowRuns.request(row, 41, :poll)
    next = workflow_job(row)
    refute next.id == job.id
    workflow_reply("completed")
    assert :ok = GitHubPatWorkflowWorker.perform(next)

    assert %{status: :ready, active?: false, rows: [%{conclusion: "success"}]} =
             PatWorkflowRuns.read(row, 41)

    snapshot = workflow_snapshot(row)
    Repo.update!(change(snapshot, synced_at: DateTime.add(snapshot.synced_at, -30, :second)))
    assert :ok = PatWorkflowRuns.request(row, 41, :poll)
    assert workflow_snapshot(row).job_id == nil
    assert :ok = PatWorkflowRuns.request(row, 41, :manual)
    refute workflow_job(row).id == next.id
  end

  test "a failed workflow refresh keeps the last successful rows and manual refresh recovers", %{
    connection: row
  } do
    assert :ok = PatWorkflowRuns.request(row, 41, :initial)
    workflow_reply("completed")
    assert :ok = GitHubPatWorkflowWorker.perform(workflow_job(row))
    previous = PatWorkflowRuns.read(row, 41)
    assert :ok = PatWorkflowRuns.request(row, 41, :manual)
    Process.put(:workflow_reply, fn _ -> {:error, :unavailable} end)
    assert {:cancel, :unavailable} = GitHubPatWorkflowWorker.perform(workflow_job(row))

    assert %{status: :failed, error: :unavailable, rows: rows, synced_at: time} =
             PatWorkflowRuns.read(row, 41)

    assert {rows, time} == {previous.rows, previous.synced_at}
    assert :ok = PatWorkflowRuns.request(row, 41, :manual)
    Process.put(:workflow_reply, fn repo -> {:ok, %{repository: repo, runs: []}} end)
    assert :ok = GitHubPatWorkflowWorker.perform(workflow_job(row))
    assert %{status: :ready, error: nil, active?: false, rows: []} = PatWorkflowRuns.read(row, 41)
  end

  test "a late workflow result cannot restore an earlier in-progress run", %{connection: row} do
    assert :ok = PatWorkflowRuns.request(row, 41, :initial)
    job = workflow_job(row)
    workflow_reply("in_progress")
    earlier = Process.get(:workflow_reply)

    Process.put(:workflow_reply, fn repo ->
      workflow_reply("completed")
      assert :ok = GitHubPatWorkflowWorker.perform(job)
      earlier.(repo)
    end)

    assert :ok = GitHubPatWorkflowWorker.perform(job)

    assert %{status: :ready, active?: false, rows: [%{status: "completed"}]} =
             PatWorkflowRuns.read(row, 41)
  end

  test "scheduled and old-mode jobs close missing items, preserve history and reopen returned items",
       %{connection: row} do
    complete(dispatch(row, "full"))
    store_item(row, 9, "issue", "closed")
    store_item(row, 10, "pull_request", "merged")

    Process.put(
      :sync_outcome,
      {:ok, %{repository: repository(), items: [item(1, "issue", "open")]}}
    )

    queued = dispatch(row, "incremental")
    job = %{queued | args: Map.put(queued.args, "mode", "incremental")}
    assert :ok = GitHubPatRepositorySyncWorker.perform(job)

    assert Enum.map(items(row), &{&1.kind, &1.number, &1.state}) == [
             {"issue", 1, "open"},
             {"issue", 9, "closed"},
             {"pull_request", 2, "closed"},
             {"pull_request", 10, "merged"}
           ]

    Repo.update!(change(queued, state: "completed"))

    Process.put(
      :sync_outcome,
      {:ok, %{repository: repository(), items: [item(2, "pull_request", "open")]}}
    )

    assert :ok = GitHubPatRepositorySyncWorker.perform(dispatch(row, "open"))

    assert Enum.map(items(row), &{&1.number, &1.state}) == [
             {1, "closed"},
             {9, "closed"},
             {2, "open"},
             {10, "merged"}
           ]
  end

  test "manual complete open listings close absent rows without deleting them", %{connection: row} do
    complete(dispatch(row, "full"))

    Process.put(
      :sync_outcome,
      {:ok, %{repository: repository(), items: [item(2, "pull_request", "open")]}}
    )

    assert :ok = GitHubPatRepositorySyncWorker.perform(dispatch(row, "full"))

    assert [
             %{kind: "issue", state: "closed", number: 1},
             %{kind: "pull_request", state: "open", number: 2}
           ] = items(row)
  end

  test "a failed repository read preserves the previously published rows and watermark", %{
    connection: row
  } do
    complete(dispatch(row, "full"))
    old_items = items(row)
    old_watermark = sync(row).synced_at
    Process.put(:sync_outcome, {:error, :unavailable})
    job = dispatch(row, "full")
    assert {:error, :unavailable} = GitHubPatRepositorySyncWorker.perform(%{job | attempt: 1})
    assert items(row) == old_items
    assert sync(row).synced_at == old_watermark
    assert sync(row).error_code == "unavailable"
  end

  test "manual and old incremental modes coalesce the same complete open listing", %{
    connection: row
  } do
    complete(dispatch(row, "full"))
    scheduled = dispatch(row, "incremental")
    manual = dispatch(row, "full")
    assert manual.id == scheduled.id
    assert manual.args["mode"] == "open"
    assert :ok = GitHubPatRepositorySyncWorker.perform(manual)
    assert length(Process.get(:sync_calls)) == 2
  end

  test "a late duplicate cannot reopen items closed by a newer successful attempt", %{
    connection: row
  } do
    complete(dispatch(row, "open"))
    job = dispatch(row, "open")

    Process.put(:sync_outcome, fn ->
      Process.put(:sync_outcome, {:ok, %{repository: repository(), items: []}})
      assert :ok = GitHubPatRepositorySyncWorker.perform(job)
      {:ok, %{repository: repository(), items: [item(1, "issue", "open")]}}
    end)

    assert :ok = GitHubPatRepositorySyncWorker.perform(job)
    assert Enum.all?(items(row), &(&1.state == "closed"))
    assert length(items(row)) == 2
    assert length(Process.get(:sync_calls)) == 3
  end

  test "dispatching several repositories emits one queue notification", %{connection: row} do
    Repo.insert!(%GitHubPatSelection{
      connection_id: row.id,
      github_id: 42,
      owner_id: 7,
      owner: "sample",
      name: "two"
    })

    Phoenix.PubSub.subscribe(Samgita.PubSub, "github:console")
    dispatch(row, "full")
    assert_receive :github_feed_changed
    refute_receive :github_feed_changed
  end

  test "missing requests skip an already synchronized repository", %{connection: row} do
    complete(dispatch(row, "full"))
    id = sync(row).job_id
    assert :ok = PatSync.request_missing()
    assert :ok = GitHubPatSyncWorker.perform(%Styx.Job{args: %{"mode" => "missing"}})
    assert sync(row).job_id == id
  end

  test "a repository discovered under a newly selected owner gets a fresh import", %{
    connection: row
  } do
    previous = complete(dispatch(row, "full"))
    moved = %{repository() | owner_id: 9, owner: "new-owner"}

    Repo.insert!(%Samgita.Domain.GitHubPatCatalog{
      connection_id: row.id,
      credential_version: row.credential_version,
      generation: Ecto.UUID.generate(),
      status: "ready",
      data: %{
        owners: [%{id: 9, login: moved.owner}],
        repositories: [moved],
        memberships_available: true
      }
    })

    assert :ok = Samgita.GitHub.Console.save_selection(row.version, [], [9])
    new_job = dispatch(row, "missing")
    assert new_job.id != previous.id
    assert new_job.args["mode"] == "open"
  end

  test "selection removal during a read fences its late publication", %{connection: row} do
    job = dispatch(row, "full")

    Process.put(:sync_outcome, fn ->
      Repo.delete_all(from r in GitHubPatSelection, where: r.connection_id == ^row.id)
      {:ok, %{repository: repository(), items: [item(1, "issue", "open")]}}
    end)

    assert :ok = GitHubPatRepositorySyncWorker.perform(job)
    assert items(row) == []
    assert sync(row).synced_at == nil
  end

  test "a rate limit is shared with the next repository attempt", %{connection: row} do
    complete(dispatch(row, "open"))
    previous_items = items(row)
    previous_sync = sync(row).synced_at
    job = dispatch(row, "full")
    until = System.system_time(:second) + 120
    Process.put(:sync_outcome, {:error, {:rate_limited, until}})
    assert {:snooze, delay} = GitHubPatRepositorySyncWorker.perform(job)
    assert delay in 119..120
    assert Repo.get!(GitHubPatConnection, row.id).retry_at == until
    assert items(row) == previous_items
    assert sync(row).synced_at == previous_sync
    calls = Process.get(:sync_calls)
    assert {:snooze, _} = GitHubPatRepositorySyncWorker.perform(job)
    assert Process.get(:sync_calls) == calls
  end

  test "closing absent open rows is scoped to the current repository and credential", %{
    connection: row
  } do
    complete(dispatch(row, "open"))
    other_credential = Ecto.UUID.generate()
    store_item(row, 50, "issue", "open", other_credential)
    store_item(row, 60, "issue", "open", row.credential_version, 42)
    Process.put(:sync_outcome, {:ok, %{repository: repository(), items: []}})
    assert :ok = GitHubPatRepositorySyncWorker.perform(dispatch(row, "open"))

    assert Enum.map(Enum.filter(items(row), &(&1.number in [1, 2])), & &1.state) == [
             "closed",
             "closed"
           ]

    assert Enum.find(items(row), &(&1.number == 50)).state == "open"
    assert Enum.find(items(row), &(&1.repository_id == 42)).state == "open"
  end

  test "a queued legacy job for an old credential cannot close or reopen the current snapshot", %{
    connection: row
  } do
    complete(dispatch(row, "open"))
    old_job = dispatch(row, "incremental")

    current =
      Repo.update!(
        change(row, credential_version: Ecto.UUID.generate(), version: Ecto.UUID.generate())
      )

    new_job = dispatch(current, "open")

    Process.put(
      :sync_outcome,
      {:ok, %{repository: repository(), items: [item(1, "issue", "open")]}}
    )

    assert :ok = GitHubPatRepositorySyncWorker.perform(new_job)
    current_items = items(row)
    calls = Process.get(:sync_calls)

    assert :ok =
             GitHubPatRepositorySyncWorker.perform(%{
               old_job
               | args: Map.put(old_job.args, "mode", "full")
             })

    assert items(row) == current_items
    assert Process.get(:sync_calls) == calls

    assert Enum.find(items(row), &(&1.number == 1)).credential_version ==
             current.credential_version

    assert Enum.find(items(row), &(&1.number == 2)).credential_version == row.credential_version
  end

  test "reader completes every open page for both kinds and separates PRs from Issues" do
    Process.put(:sync_http_reply, fn
      "/repositories/41", _ ->
        raw_repository()

      "/repos/sample/one/issues", %{"page" => "1", "state" => "open"} = params ->
        refute Map.has_key?(params, "since")
        {[Map.put(raw_item(8), "pull_request", %{})], :next}

      "/repos/sample/one/issues", %{"page" => "2", "state" => "open"} ->
        [raw_item(1)]

      "/repos/sample/one/pulls", %{"page" => "1", "state" => "open"} ->
        {[raw_item(2)], :next}

      "/repos/sample/one/pulls", %{"page" => "2", "state" => "open"} ->
        [raw_item(3)]
    end)

    assert {:ok, %{items: items}} =
             PatClient.sync_repository("synthetic-fixture", repository(), http_opts())

    assert Enum.sort(Enum.map(items, &{&1.kind, &1.number, &1.state})) ==
             [{"issue", 1, "open"}, {"pull_request", 2, "open"}, {"pull_request", 3, "open"}]
  end

  test "longstanding open PRs on later pages are retained without a since cutoff" do
    Process.put(:sync_http_reply, fn
      "/repositories/41", _ ->
        raw_repository()

      "/repos/sample/one/issues", %{"state" => "open"} = params ->
        refute Map.has_key?(params, "since")
        []

      "/repos/sample/one/pulls", %{"page" => "1", "state" => "open"} ->
        {[Map.put(raw_item(2), "updated_at", "2026-11-19T00:00:00Z")], :next}

      "/repos/sample/one/pulls", %{"page" => "2", "state" => "open"} ->
        [Map.put(raw_item(3), "updated_at", "2025-01-01T00:00:00Z")]
    end)

    assert {:ok, %{items: items}} =
             PatClient.sync_repository("synthetic-fixture", repository(), http_opts())

    assert Enum.sort(Enum.map(items, & &1.number)) == [2, 3]
  end

  test "a later-category rate limit returns failure instead of a partial open snapshot" do
    Process.put(:sync_http_reply, fn
      "/repositories/41", _ -> raw_repository()
      "/repos/sample/one/issues", %{"state" => "open"} -> [raw_item(1)]
      "/repos/sample/one/pulls", %{"state" => "open"} -> {:rate_limit, 60}
    end)

    assert {:error, {:rate_limited, 1_800_000_060}} =
             PatClient.sync_repository("synthetic-fixture", repository(), http_opts())
  end

  defp workflow_snapshot(row),
    do: Repo.get_by!(GitHubPatWorkflowSnapshot, connection_id: row.id, repository_id: 41)

  defp workflow_job(row), do: Repo.get!(Styx.Job, workflow_snapshot(row).job_id)

  defp workflow_reply(status) do
    Process.put(:workflow_reply, fn repo ->
      run = %{
        "id" => 8,
        "status" => status,
        "conclusion" => if(status == "completed", do: "success")
      }

      {:ok, %{repository: repo, runs: [run]}}
    end)
  end

  defp store_item(row, number, kind, state, credential \\ nil, repository_id \\ 41) do
    Repo.insert!(%GitHubPatItem{
      connection_id: row.id,
      repository_id: repository_id,
      credential_version: credential || row.credential_version,
      kind: kind,
      number: number,
      title: "Saved #{number}",
      state: state,
      author: "author",
      github_updated_at: ~U[2026-11-20 00:00:00.000000Z],
      url: "https://github.com/sample/one/issues/#{number}"
    })
  end

  defp dispatch(row, mode) do
    assert :ok = GitHubPatSyncWorker.perform(%Styx.Job{args: %{"mode" => mode}})
    Repo.get!(Styx.Job, sync(row).job_id)
  end

  defp complete(job) do
    assert :ok = GitHubPatRepositorySyncWorker.perform(job)
    Repo.update!(change(job, state: "completed"))
  end

  defp sync(row),
    do: Repo.get_by!(GitHubPatRepositorySync, connection_id: row.id, repository_id: 41)

  defp items(row),
    do:
      Repo.all(
        from i in GitHubPatItem, where: i.connection_id == ^row.id, order_by: [i.kind, i.number]
      )

  defp repository, do: %{id: 41, owner_id: 7, owner: "sample", name: "one"}

  defp raw_repository,
    do: %{"id" => 41, "owner" => %{"id" => 7, "login" => "sample"}, "name" => "one"}

  defp raw_item(number),
    do: %{
      "number" => number,
      "title" => "Work #{number}",
      "state" => "open",
      "user" => %{"login" => "author"},
      "updated_at" => "2026-11-20T00:00:00Z"
    }

  defp item(number, kind, state),
    do: %{
      number: number,
      kind: kind,
      title: "Work #{number}",
      state: state,
      author: "author",
      updated_at: "2026-11-20T00:00:00Z",
      url:
        "https://github.com/sample/one/#{if kind == "issue", do: "issues", else: "pull"}/#{number}"
    }

  defp http_opts,
    do: [
      http: FixtureHTTP,
      destination: %{api_url: "https://api.github.com", uri: URI.parse("https://api.github.com")},
      now: 1_800_000_000
    ]
end
