defmodule Samgita.GitHub.DeletionReconciliationTest do
  use Samgita.DataCase, async: false
  import Ecto.Query
  import Samgita.GitHubFixtures

  alias Samgita.Domain.{
    DomainEvent,
    GitHubConnection,
    GitHubObject,
    GitHubObservation,
    GitHubSync
  }

  alias Samgita.GitHub.Reconciliation
  alias Samgita.Repo
  @permissions Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})

  defmodule FakeHTTP do
    @moduledoc false
    def request(method, url, _headers, _body, _opts) do
      send(self(), {:http_request, method, URI.parse(url).path})
      [response | rest] = Process.get(:deletion_responses)
      Process.put(:deletion_responses, rest)
      response
    end
  end

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:ok, pem: :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])}
  end

  setup %{pem: pem} do
    previous =
      Map.new([:github_hosts, :github_secrets], &{&1, Application.fetch_env(:samgita, &1)})

    Application.put_env(:samgita, :github_hosts, %{
      "github.test" => %{
        api_url: "http://127.0.0.1:43219",
        addresses: [{127, 0, 0, 1}],
        allow_insecure: true
      }
    })

    Application.put_env(:samgita, :github_secrets, %{
      "test-key-v1" => pem,
      "test-hook-v1" => secret()
    })

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:samgita, key, value)
          :error -> Application.delete_env(:samgita, key)
        end
      end
    end)

    {project, connection, mapping} = mapping_fixture()
    {other_project, _, other_mapping} = mapping_fixture(nil, connection, %{"external_id" => "31"})

    %{
      project: project,
      connection: connection,
      mapping: mapping,
      other_project: other_project,
      other_mapping: other_mapping,
      now: DateTime.add(DateTime.utc_now(), 1)
    }
  end

  test "deleted comment 404 records one tombstone and leaves another mapped repository usable",
       c do
    sync = comment_sync(c, "created")
    assert {:ok, %{"state" => "idle"}} = read(c, sync, [json(200, comment())])

    object =
      Repo.get_by!(GitHubObject, github_repository_id: sync.github_repository_id, kind: "comment")

    original = Repo.get_by!(GitHubObservation, object_id: object.id)

    sync = comment_sync(c, "deleted")
    responses = [json(404, %{})] ++ authorization(c.now, 30)
    assert {:ok, %{"state" => "idle"}} = read(c, sync, responses)
    tombstone = Repo.get!(GitHubObject, object.id)
    assert tombstone.facts["deleted"] == true
    assert tombstone.facts["resource_id"] == "400"
    refute Map.has_key?(tombstone.untrusted_input, "comment")
    assert Repo.get!(GitHubObservation, original.id).untrusted_input["comment"] == "old comment"

    assert Repo.aggregate(from(o in GitHubObservation, where: o.object_id == ^object.id), :count) ==
             2

    sync = comment_sync(c, "deleted")
    assert {:ok, %{"state" => "idle"}} = read(c, sync, responses)
    assert Repo.get!(GitHubObject, object.id).version == tombstone.version

    assert Repo.aggregate(from(o in GitHubObservation, where: o.object_id == ^object.id), :count) ==
             2

    assert Repo.get!(GitHubConnection, c.connection.id).version == c.connection.version
    assert {:ok, _} = ingest(c.connection, body_fixture(%{"repository" => %{"id" => 31}}))

    other_sync =
      Repo.get_by!(GitHubSync,
        github_repository_id: c.other_mapping["repository"]["id"],
        kind: "issue",
        resource_id: "3"
      )

    assert {:ok, %{"state" => "idle"}} = read(c, other_sync, [json(200, issue_fixture())], 31)

    assert Repo.aggregate(
             from(e in DomainEvent,
               where: e.project_id == ^c.project["id"] and e.type == "github.reconciled"
             ),
             :count
           ) == 2
  end

  test "an absent object is rechecked against installation and repository access before tombstoning",
       c do
    for denied_stage <- [:installation, :repository] do
      sync = comment_sync(c, "deleted")

      recheck =
        case denied_stage do
          :installation -> [json(404, %{})]
          :repository -> Enum.take(authorization(c.now, 30), 2) ++ [json(404, %{})]
        end

      assert {:ok, %{"state" => "permission_failed"}} = read(c, sync, [json(404, %{})] ++ recheck)
      connection = Repo.get!(GitHubConnection, c.connection.id)
      assert connection.state == "verification_required"
      assert connection.version > c.connection.version

      assert Repo.aggregate(
               from(o in GitHubObject,
                 where: o.github_repository_id == ^sync.github_repository_id
               ),
               :count
             ) == 0

      # Each revocation is an independent local scenario under the same transaction.
      connection
      |> Ecto.Changeset.change(state: c.connection.state, version: c.connection.version)
      |> Repo.update!()
    end
  end

  test "resource permission denial and feed 404 retain connection fencing", c do
    for {kind, response} <- [{"comment", json(403, %{})}, {"issues", json(404, %{})}] do
      sync =
        if kind == "comment",
          do: comment_sync(c, "deleted"),
          else:
            Repo.get_by!(GitHubSync,
              github_repository_id: c.mapping["repository"]["id"],
              kind: "issues",
              resource_id: ""
            )

      assert {:ok, %{"state" => "permission_failed"}} = read(c, sync, [response])
      assert Repo.get!(GitHubConnection, c.connection.id).state == "verification_required"

      Repo.get!(GitHubConnection, c.connection.id)
      |> Ecto.Changeset.change(state: c.connection.state, version: c.connection.version)
      |> Repo.update!()
    end
  end

  test "rate limits and transient failures during absence revalidation retry without a false tombstone",
       c do
    for {response, class} <- [
          {json(429, %{}, [{"retry-after", "120"}]), "rate_limited"},
          {json(503, %{}), "retryable"}
        ] do
      sync = comment_sync(c, "deleted")

      assert {:ok, %{"state" => "retry_wait", "last_error_class" => ^class}} =
               read(c, sync, [json(404, %{}), response])

      assert Repo.get!(GitHubConnection, c.connection.id).version == c.connection.version

      assert Repo.aggregate(
               from(o in GitHubObject,
                 where: o.github_repository_id == ^sync.github_repository_id
               ),
               :count
             ) == 0

      Repo.get!(GitHubConnection, c.connection.id)
      |> Ecto.Changeset.change(rate_limited_until: nil)
      |> Repo.update!()
    end
  end

  test "a later verified absence fences an older object snapshot and a later reappearance replaces it",
       c do
    sync = comment_sync(c, "deleted")
    assert {:ok, older} = Reconciliation.claim(sync.id, now: c.now)
    newer = comment_sync(c, "deleted")
    later = %{c | now: DateTime.add(c.now, 1)}

    assert {:ok, %{"state" => "idle"}} =
             read(later, newer, [json(404, %{})] ++ authorization(later.now, 30))

    assert {:error, %Samgita.Error{code: :ownership_lost}} =
             Reconciliation.settle(
               sync.id,
               older.token,
               {:ok, %{}, %{items: [comment()], next_page: nil}},
               now: later.now
             )

    object =
      Repo.get_by!(GitHubObject, github_repository_id: sync.github_repository_id, kind: "comment")

    assert object.facts["deleted"] == true
    newer = comment_sync(c, "created")

    assert {:ok, %{"state" => "idle"}} =
             read(%{c | now: DateTime.add(c.now, 2)}, newer, [json(200, comment())])

    refute Repo.get!(GitHubObject, object.id).facts["deleted"]
    assert Repo.get!(GitHubObject, object.id).version == 2
  end

  defp comment_sync(c, action) do
    assert {:ok, _} =
             ingest(c.connection, body_fixture(%{"action" => action, "comment" => comment()}),
               event: "issue_comment"
             )

    Repo.get_by!(GitHubSync,
      github_repository_id: c.mapping["repository"]["id"],
      kind: "comment",
      resource_id: "400"
    )
  end

  defp comment,
    do: %{"id" => 400, "body" => "old comment", "updated_at" => "2026-10-22T00:00:00Z"}

  defp read(c, sync, responses, repository_id \\ 30) do
    Process.put(
      :deletion_responses,
      authorization(c.now, repository_id) ++ authorization(c.now, repository_id) ++ responses
    )

    result = Reconciliation.run(sync.id, now: c.now, http: FakeHTTP)
    assert Process.get(:deletion_responses) == []
    result
  end

  defp authorization(now, repository_id) do
    [
      json(200, %{
        "id" => 20,
        "app_id" => 10,
        "suspended_at" => nil,
        "permissions" => @permissions
      }),
      json(200, %{
        "token" => "synthetic-token",
        "permissions" => @permissions,
        "expires_at" => now |> DateTime.add(3600) |> DateTime.to_iso8601(),
        "repositories" => [%{"id" => repository_id}]
      }),
      json(200, %{"id" => repository_id, "full_name" => "owner/repo", "default_branch" => "main"})
    ]
  end

  defp json(status, body, headers \\ []),
    do: {:ok, %{status: status, headers: headers, body: Jason.encode!(body)}}
end
