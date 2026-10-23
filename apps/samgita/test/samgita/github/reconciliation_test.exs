defmodule Samgita.GitHub.ReconciliationTest do
  use Samgita.DataCase, async: false
  import Ecto.Query
  import Samgita.DomainFixtures
  import Samgita.GitHubFixtures
  alias Samgita.{Error, GitHub, Principal, Projects, Repo}
  alias Samgita.GitHub.{Failure, Reconciliation}

  alias Samgita.Domain.{
    DomainEvent,
    GitHubConnection,
    GitHubDelivery,
    GitHubObject,
    GitHubObservation,
    GitHubSync,
    Repository
  }

  alias Samgita.GitHubFixtures.FakeClient

  setup do
    previous = Application.get_env(:samgita, :github_secrets)
    Application.put_env(:samgita, :github_secrets, %{"test-hook-v1" => secret()})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:samgita, :github_secrets, previous),
        else: Application.delete_env(:samgita, :github_secrets)
    end)

    {project, connection, mapping} = mapping_fixture()

    sync =
      Repo.get_by!(GitHubSync,
        github_repository_id: mapping["repository"]["id"],
        kind: "issues",
        resource_id: ""
      )

    %{
      project: project,
      connection: connection,
      mapping: mapping,
      sync: sync,
      now: DateTime.add(DateTime.utc_now(), 1)
    }
  end

  test "bounded pages checkpoint, then a missed update is read after the recurring deadline", c do
    assert {:ok, %{"state" => "pending", "page" => 2}} = run(c, [issue_fixture()], next_page: 2)
    assert_receive {:github_fetch, %{kind: :issues, page: 1}}

    assert {:ok, %{"state" => "idle", "page" => 1}} =
             run(c, [issue_fixture(%{"number" => 4, "id" => 301})])

    assert_receive {:github_fetch, %{page: 2}}
    assert Repo.aggregate(objects(c), :count) == 2
    assert Repo.aggregate(observations(c), :count) == 2
    later = DateTime.add(c.now, 901)
    maintain_until_enqueued(c.sync.id, later)
    refreshed = Repo.get!(GitHubSync, c.sync.id)
    assert refreshed.state == "pending"
    assert DateTime.compare(refreshed.since, DateTime.add(c.now, -300)) == :eq

    assert {:ok, %{"state" => "idle"}} =
             run(%{c | now: later}, [
               issue_fixture(%{"state" => "closed", "updated_at" => "2026-10-23T00:00:00Z"})
             ])

    assert Repo.one!(from o in objects(c), where: o.resource_id == "3").facts["state"] == "closed"
  end

  test "events refer to immutable versions; snapshots and duplicate reads do not rewrite prior evidence",
       c do
    assert {:ok, _} = run(c, [issue_fixture()])
    first = Repo.one!(observations(c))

    assert {:ok, snapshot} =
             GitHub.observation(Principal.operator(), c.project["id"], c.mapping["id"], first.id)

    assert snapshot["untrusted_input"]["body"] == "Untrusted source text"
    reset!(c)
    assert {:ok, _} = run(%{c | now: DateTime.add(c.now, 1)}, [issue_fixture()])
    assert Repo.aggregate(observations(c), :count) == 1
    reset!(c)

    assert {:ok, _} =
             run(%{c | now: DateTime.add(c.now, 2)}, [
               issue_fixture(%{"body" => "Changed untrusted text"})
             ])

    assert Repo.aggregate(observations(c), :count) == 2

    assert Repo.get!(GitHubObservation, first.id).untrusted_input["body"] ==
             "Untrusted source text"

    events =
      Repo.all(
        from e in DomainEvent,
          where: e.type == "github.reconciled" and e.project_id == ^c.project["id"],
          order_by: e.inserted_at
      )

    assert Enum.map(events, & &1.data["observation_id"]) |> Enum.uniq() |> length() == 2
    assert Enum.any?(events, &(&1.data["untrusted_input_ref"] == first.id))
    refute Enum.any?(events, &(inspect(&1.data) =~ "untrusted text"))
  end

  test "webhook order cannot replace a current snapshot, and older API queries cannot overwrite newer evidence",
       c do
    assert {:ok, older} = Reconciliation.claim(c.sync.id, now: c.now)
    assert {:ok, receipt} = ingest(c.connection)

    targeted =
      Repo.get_by!(GitHubSync,
        github_repository_id: c.mapping["repository"]["id"],
        kind: "issue",
        resource_id: "3"
      )

    later = DateTime.add(c.now, 2)

    assert {:ok, _} =
             Reconciliation.run(targeted.id,
               now: later,
               client: FakeClient,
               fetch_result:
                 {:ok,
                  %{
                    items: [
                      issue_fixture(%{
                        "state" => "closed",
                        "updated_at" => "2026-10-23T00:00:00Z"
                      })
                    ],
                    next_page: nil
                  }}
             )

    assert {:ok, _} =
             Reconciliation.settle(
               c.sync.id,
               older.token,
               {:ok, metadata(), %{items: [issue_fixture()], next_page: nil}},
               now: DateTime.add(later, 1)
             )

    assert Repo.one!(objects(c)).facts["state"] == "closed"
    assert {:ok, _} = ingest(c.connection, body_fixture(%{"action" => "reopened"}))
    assert Repo.one!(objects(c)).facts["state"] == "closed"
    assert Repo.get!(GitHubDelivery, receipt["id"]).payload["facts"]["state"] == "open"
    assert Repo.aggregate(observations(c), :count) == 1
  end

  test "expired or superseded read handlers cannot commit, and maintenance repairs a lost wakeup",
       c do
    assert {:ok, stale} = Reconciliation.claim(c.sync.id, now: c.now)
    later = DateTime.add(c.now, 121)
    assert {:ok, _} = Reconciliation.maintain(now: later)
    assert {:ok, current} = Reconciliation.claim(c.sync.id, now: later)
    assert current.token.fence > stale.token.fence

    assert {:error, %Error{code: :ownership_lost}} =
             Reconciliation.settle(
               c.sync.id,
               stale.token,
               {:ok, metadata(), %{items: [], next_page: nil}},
               now: later
             )

    assert {:ok, _} =
             Reconciliation.settle(
               c.sync.id,
               current.token,
               {:ok, metadata(), %{items: [], next_page: nil}},
               now: later
             )
  end

  test "two-hour rate deadline gates all repository feeds and never becomes an early network retry",
       c do
    assert {:ok, %{"state" => "retry_wait"} = sync} =
             run(c, [], failure: Failure.new(:rate_limited, :primary_rate_limit, 7200))

    {:ok, deadline, _} = DateTime.from_iso8601(sync["next_attempt_at"])
    assert DateTime.diff(deadline, c.now) == 7200
    connection = Repo.get!(GitHubConnection, c.connection.id)
    assert connection.rate_limited_until == deadline

    another =
      Repo.get_by!(GitHubSync,
        github_repository_id: c.mapping["repository"]["id"],
        kind: "pulls",
        resource_id: ""
      )

    assert {:ok, %{result: %{"state" => "retry_wait"}}} =
             Reconciliation.claim(another.id, now: DateTime.add(c.now, 3601))

    assert Repo.get!(GitHubSync, another.id).attempt_count == 0
    assert {:ok, %{token: _}} = Reconciliation.claim(another.id, now: DateTime.add(c.now, 7201))
  end

  test "excessive cooldown is paused for operator recovery", c do
    assert {:ok, %{"state" => "dead_letter", "last_error_code" => "rate_limit_recovery_required"}} =
             run(c, [], failure: Failure.new(:rate_limited, :rate_limited, 604_801))

    assert Repo.get!(GitHubConnection, c.connection.id).state == "verification_required"
    assert {:error, %Error{code: :forbidden}} = ingest(c.connection)
  end

  test "authentication and permission loss fence new ingress while retaining the accepted inbox",
       c do
    assert {:ok, receipt} = ingest(c.connection)

    assert {:ok, %{"state" => "permission_failed"}} =
             run(c, [], failure: Failure.new(:permission, :installation_suspended))

    assert Repo.get!(GitHubConnection, c.connection.id).version > c.connection.version
    assert {:error, %Error{code: :forbidden}} = ingest(c.connection)
    assert Repo.get!(GitHubDelivery, receipt["id"]).state == "accepted"
  end

  test "transient errors exhaust bounded retries and explicit recovery keeps source history", c do
    Enum.reduce(1..8, c.now, fn attempt, now ->
      assert {:ok, result} =
               run(%{c | now: now}, [], failure: Failure.new(:retryable, :unavailable))

      assert result["attempt_count"] == attempt
      assert result["state"] == if(attempt == 8, do: "dead_letter", else: "retry_wait")
      {:ok, deadline, _} = DateTime.from_iso8601(result["next_attempt_at"])
      DateTime.add(deadline, 1)
    end)

    reset!(c)
    assert Repo.get!(GitHubSync, c.sync.id).state == "pending"
    assert Repo.get!(GitHubSync, c.sync.id).attempt_count == 0
  end

  test "page budget stops explicitly instead of silently dropping remaining results", c do
    Repo.get!(GitHubSync, c.sync.id) |> Ecto.Changeset.change(page: 100) |> Repo.update!()

    assert {:ok, %{"state" => "dead_letter", "last_error_code" => "page_limit"}} =
             run(c, [issue_fixture()], next_page: 101)

    assert Repo.aggregate(objects(c), :count) == 1
  end

  test "rename and default branch changes preserve repository and Project identities", c do
    assert {:ok, _} =
             Reconciliation.run(c.sync.id,
               now: c.now,
               client: FakeClient,
               verify_result:
                 {:ok, %{metadata() | full_name: "moved/new-name", default_branch: "trunk"}}
             )

    repo = Repo.get!(Repository, c.mapping["repository"]["repository_id"])
    assert repo.display_name == "moved/new-name"
    assert {:ok, %{"data" => [mapping]}} = GitHub.mappings(Principal.operator(), c.project["id"])
    assert mapping["repository"]["repository_id"] == repo.id
    assert mapping["project_id"] == c.project["id"]
    assert mapping["repository"]["default_branch"] == "trunk"
    assert {:ok, _} = Projects.get(Principal.operator(), c.project["id"])
  end

  test "an older remote read cannot undo a later repository rename", c do
    assert {:ok, older} = Reconciliation.claim(c.sync.id, now: c.now)

    other =
      Repo.get_by!(GitHubSync,
        github_repository_id: c.mapping["repository"]["id"],
        kind: "pulls",
        resource_id: ""
      )

    later = DateTime.add(c.now, 2)
    assert {:ok, current} = Reconciliation.claim(other.id, now: later)

    assert {:ok, _} =
             Reconciliation.settle(
               other.id,
               current.token,
               {:ok, %{metadata() | full_name: "moved/new-name"}, %{items: [], next_page: nil}},
               now: later
             )

    assert {:ok, _} =
             Reconciliation.settle(
               c.sync.id,
               older.token,
               {:ok, metadata(), %{items: [], next_page: nil}},
               now: DateTime.add(later, 1)
             )

    assert Repo.get!(Repository, c.mapping["repository"]["repository_id"]).display_name ==
             "moved/new-name"
  end

  test "invalid snapshot rolls back observations and no false completion is recorded", c do
    assert {:error, %Error{code: :invalid}} = run(c, [%{"id" => "invalid"}])
    assert Repo.aggregate(objects(c), :count) == 0
    assert Repo.get!(GitHubSync, c.sync.id).state == "running"
    assert is_nil(Repo.get!(GitHubSync, c.sync.id).last_completed_at)
  end

  test "a long scan keeps its initial lower bound across pages and retries", c do
    assert {:ok, _} = run(c, [], next_page: 2)
    later = DateTime.add(c.now, 7200)
    assert {:ok, _} = run(%{c | now: later}, [], failure: Failure.new(:retryable, :unavailable))
    finished = DateTime.add(later, 61)
    assert {:ok, %{"state" => "idle"}} = run(%{c | now: finished}, [])
    sync = Repo.get!(GitHubSync, c.sync.id)
    assert sync.last_scan_started_at == c.now
    assert sync.last_completed_at == finished
    maintain_until_enqueued(c.sync.id, DateTime.add(finished, 901))
    assert Repo.get!(GitHubSync, c.sync.id).since == DateTime.add(c.now, -300)
  end

  test "historical observations require a Project event and disabled mappings cannot read future facts",
       c do
    assert {:ok, _} = run(c, [issue_fixture()])
    observation = Repo.one!(observations(c))
    {other, _, mapping} = mapping_fixture(nil, c.connection)

    assert {:error, %Error{code: :not_found}} =
             GitHub.observation(Principal.operator(), other["id"], mapping["id"], observation.id)

    assert {:ok, _} =
             GitHub.set_mapping(
               Principal.operator(),
               c.project["id"],
               c.mapping["id"],
               command(%{"expected_version" => c.mapping["version"], "enabled" => false})
             )

    assert {:error, %Error{code: :forbidden}} =
             GitHub.facts(Principal.operator(), c.project["id"], c.mapping["id"])

    assert {:error, %Error{code: :forbidden}} =
             GitHub.observation(
               Principal.operator(),
               c.project["id"],
               c.mapping["id"],
               observation.id
             )
  end

  test "ineligible maintenance rows become terminal so they cannot starve later lost wakeups",
       c do
    {:ok, configured} =
      GitHub.configure(
        Principal.operator(),
        command(%{
          "host" => "unavailable.test",
          "app_id" => "10",
          "installation_id" => "20",
          "private_key_ref" => "test-key-v1",
          "webhook_secret_ref" => "test-hook-v1"
        })
      )

    {project, _, mapping} = mapping_fixture(nil, Repo.get!(GitHubConnection, configured["id"]))

    assert {:ok, _} =
             GitHub.set_mapping(
               Principal.operator(),
               project["id"],
               mapping["id"],
               command(%{"expected_version" => mapping["version"], "enabled" => false})
             )

    now = ~U[2020-01-01 00:00:00.000000Z]
    past = DateTime.add(now, -3600)

    Repo.get!(GitHubSync, c.sync.id)
    |> Ecto.Changeset.change(next_attempt_at: now, updated_at: now)
    |> Repo.update!()

    Repo.insert_all(
      GitHubSync,
      for n <- 1..100 do
        %{
          id: Ecto.UUID.generate(),
          github_repository_id: mapping["repository"]["id"],
          kind: "issue",
          resource_id: Integer.to_string(n),
          next_attempt_at: past,
          inserted_at: past,
          updated_at: past
        }
      end
    )

    enqueue = fn changeset ->
      send(self(), {:maintenance_enqueue, Ecto.Changeset.get_field(changeset, :args)})
      {:ok, %{}}
    end

    assert {:ok, %{"checked" => 100}} = Reconciliation.maintain(now: now, enqueue: enqueue)
    refute_receive {:maintenance_enqueue, _}
    assert {:ok, _} = Reconciliation.maintain(now: now, enqueue: enqueue)
    id = c.sync.id
    assert_receive {:maintenance_enqueue, %{"sync_id" => ^id}}
  end

  test "bounded maintenance rotates enqueued rows to reach later work without running workers",
       c do
    now = ~U[2020-01-01 00:00:00.000000Z]
    past = DateTime.add(now, -3600)

    Repo.get!(GitHubSync, c.sync.id)
    |> Ecto.Changeset.change(next_attempt_at: now, updated_at: now)
    |> Repo.update!()

    Repo.insert_all(
      GitHubSync,
      for n <- 1001..1120 do
        %{
          id: Ecto.UUID.generate(),
          github_repository_id: c.mapping["repository"]["id"],
          kind: "issue",
          resource_id: Integer.to_string(n),
          next_attempt_at: past,
          inserted_at: past,
          updated_at: past
        }
      end
    )

    enqueue = fn changeset ->
      send(self(), {:rotating_enqueue, Ecto.Changeset.get_field(changeset, :args)})
      {:ok, %{}}
    end

    id = c.sync.id
    assert {:ok, %{"checked" => 100}} = Reconciliation.maintain(now: now, enqueue: enqueue)
    refute_receive {:rotating_enqueue, %{"sync_id" => ^id}}
    assert {:ok, %{"checked" => 100}} = Reconciliation.maintain(now: now, enqueue: enqueue)
    assert_receive {:rotating_enqueue, %{"sync_id" => ^id}}
    assert Repo.get!(GitHubSync, id).state == "pending"
    assert Repo.get!(GitHubSync, id).next_attempt_at == now
  end

  defp maintain_until_enqueued(id, now) do
    # Independent-transaction fixtures are intentionally retained. The global
    # scanner promises bounded progress, not selection in the very first batch.
    attempts = div(Repo.aggregate(GitHubSync, :count), 100) + 2

    enqueue = fn changeset ->
      send(self(), {:bounded_enqueue, Ecto.Changeset.get_field(changeset, :args)})
      {:ok, %{}}
    end

    found =
      Enum.any?(1..attempts, fn _ ->
        assert {:ok, _} = Reconciliation.maintain(now: now, enqueue: enqueue)

        receive do
          {:bounded_enqueue, %{"sync_id" => ^id}} -> true
        after
          0 -> false
        end
      end)

    assert found, "maintenance did not reach the checkpoint within its bounded fair scan"
  end

  defp run(c, items, opts \\ []) do
    result =
      if failure = opts[:failure],
        do: {:error, failure},
        else: {:ok, %{items: items, next_page: opts[:next_page]}}

    Reconciliation.run(c.sync.id, now: c.now, client: FakeClient, fetch_result: result)
  end

  defp reset!(c) do
    assert {:ok, _} =
             GitHub.reconcile(
               Principal.operator(),
               c.project["id"],
               c.mapping["id"],
               command(%{"expected_version" => c.mapping["version"]})
             )
  end

  defp metadata do
    %{
      external_id: "30",
      full_name: "owner/repo",
      default_branch: "main",
      permissions: Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})
    }
  end

  defp objects(c),
    do: from(o in GitHubObject, where: o.github_repository_id == ^c.mapping["repository"]["id"])

  defp observations(c),
    do:
      from(v in GitHubObservation,
        join: o in GitHubObject,
        on: o.id == v.object_id,
        where: o.github_repository_id == ^c.mapping["repository"]["id"],
        select: v
      )
end
