defmodule Samgita.GitHub.IngestionTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  import Samgita.GitHubFixtures
  import Ecto.Query
  alias Samgita.{Error, GitHub, Principal, Projects, Repo, Repositories, Tasks}

  alias Samgita.Domain.{
    DomainEvent,
    EventDelivery,
    GitHubDelivery,
    GitHubProjectMapping,
    GitHubSync,
    Repository
  }

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

  test "verified association preserves Project and existing repository UUIDs and rejects identity collisions" do
    project = project_fixture()

    {:ok, unverified} =
      Repositories.associate(
        Principal.operator(),
        project["id"],
        command(%{
          "expected_version" => project["version"],
          "provider" => "github",
          "url" => "https://github.test/old/name"
        })
      )

    id = unverified["repository"]["id"]
    {_, connection, mapping} = mapping_fixture(project, nil, %{"repository_id" => id})
    assert mapping["project_id"] == project["id"]
    assert mapping["repository"]["repository_id"] == id
    assert Repo.get!(Repository, id).verification == "verified"
    assert Repo.aggregate(from(r in Repository, where: r.host == "github.test"), :count) == 1
    assert {:ok, current} = Projects.get(Principal.operator(), project["id"])

    assert {:error, %Error{code: :conflict}} =
             GitHub.associate(
               Principal.operator(),
               project["id"],
               command(%{
                 "expected_version" => current["version"],
                 "connection_id" => connection.id,
                 "external_id" => "31",
                 "repository_id" => id
               }),
               client: Samgita.GitHubFixtures.FakeClient
             )
  end

  test "signed replay produces one immutable source event and one generic delivery" do
    {project, _, _} = Samgita.CoordinationFixtures.routing_fixture()
    {_, connection, _} = mapping_fixture(project)
    delivery_id = Ecto.UUID.generate()

    payload =
      body_fixture(%{"project_id" => Ecto.UUID.generate(), "agent_id" => Ecto.UUID.generate()})

    assert {:ok, receipt} = ingest(connection, payload, delivery_id: delivery_id)
    assert receipt["event_count"] == 1
    assert {:ok, duplicate} = ingest(connection, payload, delivery_id: delivery_id)
    assert duplicate["id"] == receipt["id"]
    assert duplicate["duplicate"]
    event = Repo.one!(from e in DomainEvent, where: e.source_id == ^delivery_id)
    assert event.project_id == project["id"]
    assert event.source == "github"
    assert event.actor == "github:" <> connection.id
    refute inspect(event.data) =~ "Untrusted source text"
    assert Repo.aggregate(from(d in EventDelivery, where: d.event_id == ^event.id), :count) == 1

    assert Repo.get!(GitHubDelivery, receipt["id"]).payload["untrusted_input"]["trust"] ==
             "untrusted"

    assert {:error, %Error{code: :conflict}} =
             ingest(connection, body_fixture(%{"action" => "closed"}), delivery_id: delivery_id)

    assert receipt_count(connection) == 1
  end

  test "signature, installation and explicit Project mapping fail closed" do
    {project, connection, mapping} = mapping_fixture()
    {raw, _} = signed(body_fixture())

    assert {:error, %Error{code: :unauthorized}} =
             GitHub.ingest(
               connection.id,
               "issues",
               Ecto.UUID.generate(),
               raw,
               "sha256=" <> String.duplicate("0", 64)
             )

    for body <- [
          body_fixture(%{"installation" => %{"id" => 21}}),
          body_fixture(%{"repository" => %{"id" => 31}})
        ] do
      assert {:error, %Error{code: :forbidden}} = ingest(connection, body)
    end

    assert {:ok, _} =
             GitHub.set_mapping(
               Principal.operator(),
               project["id"],
               mapping["id"],
               command(%{"expected_version" => mapping["version"], "enabled" => false})
             )

    assert {:error, %Error{code: :forbidden}} = ingest(connection)
    assert receipt_count(connection) == 0
  end

  test "unsupported signed events are durably explicit and enqueue failures roll back all facts" do
    {project, _, _} = Samgita.CoordinationFixtures.routing_fixture()
    {_, connection, _} = mapping_fixture(project)

    assert {:ok, %{"state" => "unsupported", "reason" => "unsupported_event", "event_count" => 0}} =
             ingest(connection, body_fixture(), event: "deployment")

    counts =
      {Repo.aggregate(DomainEvent, :count), Repo.aggregate(EventDelivery, :count),
       Repo.aggregate(Oban.Job, :count)}

    assert {:error, %Error{code: :enqueue_failed}} =
             ingest(connection, body_fixture(), enqueue: fn _ -> {:error, :db_unavailable} end)

    assert {Repo.aggregate(DomainEvent, :count), Repo.aggregate(EventDelivery, :count),
            Repo.aggregate(Oban.Job, :count)} == counts

    assert receipt_count(connection) == 1
    assert {:ok, _} = ingest(connection)
    assert receipt_count(connection) == 2
  end

  test "source close is evidence and neither accepts a Task nor starts an execution" do
    {project, connection, _} = mapping_fixture()

    {:ok, task} =
      Tasks.create(Principal.operator(), project["id"], command(%{"title" => "Independent task"}))

    assert {:ok, _} =
             ingest(
               connection,
               body_fixture(%{
                 "action" => "closed",
                 "issue" => issue_fixture(%{"state" => "closed"})
               })
             )

    assert {:ok, current} = Tasks.get(Principal.operator(), project["id"], task["id"])
    assert current["state"] == task["state"]

    assert Repo.aggregate(
             from(a in Samgita.Domain.TaskAttempt, where: a.project_id == ^project["id"]),
             :count
           ) == 0

    assert Enum.all?(
             Repo.all(Oban.Job),
             &(&1.worker in [
                 "Samgita.Workers.GitHubReconcileWorker",
                 "Samgita.Workers.EventDeliveryWorker"
               ])
           )
  end

  test "repository removal and installation suspension stop new facts without deleting history" do
    {_, connection, _} = mapping_fixture()
    assert {:ok, first} = ingest(connection)

    assert {:ok, _} =
             ingest(
               connection,
               %{
                 "installation" => %{"id" => 20},
                 "action" => "removed",
                 "repositories_removed" => [%{"id" => 30}]
               },
               event: "installation_repositories"
             )

    assert {:error, %Error{code: :forbidden}} = ingest(connection)
    assert Repo.get!(GitHubDelivery, first["id"])

    assert {:ok, _} =
             ingest(connection, %{"installation" => %{"id" => 20}, "action" => "suspend"},
               event: "installation"
             )

    assert {:error, %Error{code: :forbidden}} = ingest(connection)

    assert Repo.aggregate(
             from(m in GitHubProjectMapping,
               join: r in Samgita.Domain.GitHubRepository,
               on: r.id == m.github_repository_id,
               where: r.connection_id == ^connection.id
             ),
             :count
           ) == 1

    assert Repo.aggregate(
             from(s in GitHubSync,
               join: r in Samgita.Domain.GitHubRepository,
               on: r.id == s.github_repository_id,
               where: r.connection_id == ^connection.id
             ),
             :count
           ) >= 4
  end

  test "only the operator can configure and verify GitHub access; rotated refs require re-verification" do
    {project, connection, mapping} = mapping_fixture()
    agent = agent_fixture()
    member_fixture(project, agent)
    {principal, _, _} = connection_fixture(agent)

    assert {:error, %Error{code: :forbidden}} =
             GitHub.associate(principal, project["id"], command(%{}),
               client: Samgita.GitHubFixtures.FakeClient
             )

    assert {:error, %Error{code: :forbidden}} = GitHub.configure(principal, command(%{}))

    assert {:ok, configured} =
             GitHub.configure(
               Principal.operator(),
               command(%{
                 "id" => connection.id,
                 "expected_version" => connection.version,
                 "private_key_ref" => "test-key-v2"
               })
             )

    refute inspect(configured) =~ secret()
    assert {:error, %Error{code: :forbidden}} = ingest(connection)
    assert {:ok, %{"data" => [_]}} = GitHub.mappings(principal, project["id"])
    other = project_fixture()

    assert {:error, %Error{code: :not_found}} =
             GitHub.facts(Principal.operator(), other["id"], mapping["id"])
  end

  test "association receipt replays before remote verification and admission honors durable cooldown" do
    project = project_fixture()
    connection = Samgita.GitHubFixtures.connection_fixture()

    attrs =
      command(%{
        "connection_id" => connection.id,
        "external_id" => "30",
        "expected_version" => project["version"]
      })

    now = DateTime.utc_now()
    failure = Samgita.GitHub.Failure.new(:rate_limited, :rate_limited, 7200)

    assert {:error, ^failure} =
             GitHub.associate(Principal.operator(), project["id"], attrs,
               client: Samgita.GitHubFixtures.FakeClient,
               verify_result: {:error, failure},
               now: now
             )

    assert_receive {:github_verify, _, "30"}

    assert {:error, %Samgita.GitHub.Failure{class: :rate_limited}} =
             GitHub.associate(Principal.operator(), project["id"], attrs,
               client: Samgita.GitHubFixtures.FakeClient,
               now: DateTime.add(now, 3601)
             )

    refute_receive {:github_verify, _, _}

    assert {:ok, first} =
             GitHub.associate(Principal.operator(), project["id"], attrs,
               client: Samgita.GitHubFixtures.FakeClient,
               now: DateTime.add(now, 7201)
             )

    assert_receive {:github_verify, _, "30"}

    assert {:ok, ^first} =
             GitHub.associate(Principal.operator(), project["id"], attrs,
               client: Samgita.GitHubFixtures.FakeClient,
               verify_result: {:error, failure},
               now: now
             )

    refute_receive {:github_verify, _, _}

    assert {:error, %Error{code: :conflict}} =
             GitHub.associate(
               Principal.operator(),
               project["id"],
               Map.put(attrs, "external_id", "31"),
               client: Samgita.GitHubFixtures.FakeClient
             )

    refute_receive {:github_verify, _, _}
  end

  defp receipt_count(connection),
    do:
      Repo.aggregate(from(d in GitHubDelivery, where: d.connection_id == ^connection.id), :count)
end
