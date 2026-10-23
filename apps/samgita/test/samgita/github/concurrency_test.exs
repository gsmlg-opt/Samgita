defmodule Samgita.GitHub.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Samgita.DomainFixtures, only: [command: 1]

  import Samgita.GitHubFixtures,
    only: [mapping_fixture: 3, ingest: 3, body_fixture: 0, issue_fixture: 0, secret: 0]

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.{Error, GitHub, Principal, Repo}

  alias Samgita.Domain.{
    DomainEvent,
    GitHubConnection,
    GitHubDelivery,
    GitHubObject,
    GitHubObservation,
    GitHubSync
  }

  alias Samgita.GitHub.Reconciliation
  alias Samgita.GitHubFixtures.FakeClient

  defmodule BlockingClient do
    def verify(connection, external_id, opts),
      do: FakeClient.verify(connection, external_id, opts)

    def fetch(connection, repository, request, opts) do
      %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
      send(Keyword.fetch!(opts, :read_observer), {:github_read_blocked, self(), backend})

      receive do
        :finish_github_read -> FakeClient.fetch(connection, repository, request, opts)
      after
        5000 -> raise "GitHub read barrier timed out"
      end
    end
  end

  setup do
    previous = Application.get_env(:samgita, :github_secrets)
    Application.put_env(:samgita, :github_secrets, %{"test-hook-v1" => secret()})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:samgita, :github_secrets, previous),
        else: Application.delete_env(:samgita, :github_secrets)
    end)

    :ok
  end

  test "independent duplicate webhook transactions commit one source event" do
    {project, connection, _mapping} = Sandbox.unboxed_run(Repo, &fixture/0)
    delivery_id = Ecto.UUID.generate()
    body = body_fixture()

    results =
      race([
        fn -> ingest(connection, body, delivery_id: delivery_id) end,
        fn -> ingest(connection, body, delivery_id: delivery_id) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({:ok, %{"duplicate" => true}}, &1)) == 1

    assert results |> Enum.map(fn {:ok, receipt} -> receipt["id"] end) |> Enum.uniq() |> length() ==
             1

    Sandbox.unboxed_run(Repo, fn ->
      assert Repo.aggregate(
               from(d in GitHubDelivery,
                 where: d.connection_id == ^connection.id and d.delivery_id == ^delivery_id
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(e in DomainEvent,
                 where:
                   e.project_id == ^project["id"] and e.source == "github" and
                     e.source_id == ^delivery_id
               ),
               :count
             ) == 1
    end)
  end

  test "competing independent settlements commit one immutable observation" do
    {connection, sync, claim, now} =
      Sandbox.unboxed_run(Repo, fn ->
        {_project, connection, mapping} = fixture()
        sync = issue_sync(mapping)
        now = DateTime.utc_now()
        assert {:ok, %{token: _} = claim} = Reconciliation.claim(sync.id, now: now)
        {connection, sync, claim, now}
      end)

    assert {:ok, metadata} = FakeClient.verify(connection, "30", [])
    outcome = {:ok, metadata, %{items: [issue_fixture()], next_page: nil}}

    results =
      race([
        fn -> Reconciliation.settle(sync.id, claim.token, outcome, now: now) end,
        fn -> Reconciliation.settle(sync.id, claim.token, outcome, now: now) end
      ])

    assert Enum.count(results, &match?({:ok, %{"state" => "idle"}}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Error{code: :ownership_lost}}, &1)) == 1

    Sandbox.unboxed_run(Repo, fn ->
      object =
        Repo.get_by!(GitHubObject,
          github_repository_id: sync.github_repository_id,
          kind: "issue",
          resource_id: "3"
        )

      assert Repo.aggregate(
               from(o in GitHubObject,
                 where: o.github_repository_id == ^sync.github_repository_id
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(o in GitHubObservation, where: o.object_id == ^object.id),
               :count
             ) == 1

      observation = Repo.get_by!(GitHubObservation, object_id: object.id)
      event = Repo.one!(from(e in DomainEvent, where: e.source_id == ^observation.source_id))
      assert event.data["observation_id"] == observation.id
      assert event.data["object_version"] == 1
      assert Repo.get!(GitHubSync, sync.id).state == "idle"
    end)
  end

  for mutation <- [:disable_mapping, :rotate_connection] do
    @mutation mutation
    test "#{mutation} in an independent transaction fences a running remote read" do
      {project, connection, mapping, sync} =
        Sandbox.unboxed_run(Repo, fn ->
          {project, connection, mapping} = fixture()
          {project, connection, mapping, issue_sync(mapping)}
        end)

      caller = self()

      worker =
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            Reconciliation.run(sync.id,
              client: BlockingClient,
              read_observer: caller,
              fetch_result: {:ok, %{items: [issue_fixture()], next_page: nil}}
            )
          end)
        end)

      assert_receive {:github_read_blocked, reader, read_backend}, 5000

      try do
        {write_backend, result} =
          Sandbox.unboxed_run(Repo, fn ->
            %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")

            result =
              case @mutation do
                :disable_mapping ->
                  GitHub.set_mapping(
                    Principal.operator(),
                    project["id"],
                    mapping["id"],
                    command(%{"expected_version" => mapping["version"], "enabled" => false})
                  )

                :rotate_connection ->
                  GitHub.configure(
                    Principal.operator(),
                    command(%{
                      "id" => connection.id,
                      "expected_version" => connection.version,
                      "private_key_ref" => "rotated-key-v2"
                    })
                  )
              end

            {backend, result}
          end)

        refute read_backend == write_backend
        assert {:ok, _} = result
      after
        send(reader, :finish_github_read)
      end

      assert {:error, %Error{code: :ownership_lost}} = Task.await(worker, 10_000)

      Sandbox.unboxed_run(Repo, fn ->
        assert Repo.aggregate(
                 from(o in GitHubObject,
                   where: o.github_repository_id == ^sync.github_repository_id
                 ),
                 :count
               ) == 0

        assert Repo.aggregate(
                 from(e in DomainEvent,
                   where: e.project_id == ^project["id"] and e.type == "github.reconciled"
                 ),
                 :count
               ) == 0
      end)
    end
  end

  defp fixture do
    host = "concurrency-" <> Ecto.UUID.generate() <> ".test"

    assert {:ok, configured} =
             GitHub.configure(
               Principal.operator(),
               command(%{
                 "host" => host,
                 "app_id" => "10",
                 "installation_id" => "20",
                 "private_key_ref" => "test-key-v1",
                 "webhook_secret_ref" => "test-hook-v1"
               })
             )

    mapping_fixture(nil, Repo.get!(GitHubConnection, configured["id"]), %{})
  end

  defp issue_sync(mapping) do
    Repo.get_by!(GitHubSync,
      github_repository_id: mapping["repository"]["id"],
      kind: "issues",
      resource_id: ""
    )
  end

  defp race(functions) do
    caller = self()

    workers = Enum.map(functions, &start_barrier_worker(caller, &1))

    backends =
      for _ <- workers do
        assert_receive {:github_transaction_ready, worker, backend}, 5000
        {worker, backend}
      end

    assert length(Enum.uniq_by(backends, &elem(&1, 1))) == length(functions)
    Enum.each(backends, fn {worker, _} -> send(worker, :go) end)
    Enum.map(workers, &Task.await(&1, 10_000))
  end

  defp start_barrier_worker(caller, function) do
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> run_after_barrier(caller, function) end) end)
  end

  defp run_after_barrier(caller, function) do
    %{rows: [[backend]]} = Repo.query!("SELECT pg_backend_pid()")
    send(caller, {:github_transaction_ready, self(), backend})

    receive do
      :go -> function.()
    after
      5000 -> flunk("GitHub concurrency barrier timed out")
    end
  end
end
