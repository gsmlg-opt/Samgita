defmodule Samgita.GitHubFixtures do
  @moduledoc false
  import Samgita.DomainFixtures
  alias Samgita.{GitHub, Principal, Projects, Repo}
  alias Samgita.GitHubFixtures.FakeClient
  @secret "local-signature-test-only"

  def secret, do: @secret

  def connection_fixture do
    {:ok, value} =
      GitHub.configure(
        Principal.operator(),
        command(%{
          "host" => "github.test",
          "app_id" => "10",
          "installation_id" => "20",
          "private_key_ref" => "test-key-v1",
          "webhook_secret_ref" => "test-hook-v1"
        })
      )

    Repo.get!(Samgita.Domain.GitHubConnection, value["id"])
  end

  def mapping_fixture(project \\ nil, connection \\ nil, extra \\ %{}) do
    project = project || project_fixture()
    connection = connection || connection_fixture()
    {:ok, current} = Projects.get(Principal.operator(), project["id"])

    {:ok, mapping} =
      GitHub.associate(
        Principal.operator(),
        project["id"],
        command(
          Map.merge(
            %{
              "connection_id" => connection.id,
              "external_id" => "30",
              "expected_version" => current["version"]
            },
            extra
          )
        ),
        client: FakeClient
      )

    {project, connection, mapping}
  end

  def body_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        "action" => "opened",
        "installation" => %{"id" => 20},
        "repository" => %{"id" => 30},
        "issue" => issue_fixture()
      },
      attrs
    )
  end

  def issue_fixture(attrs \\ %{}),
    do:
      Map.merge(
        %{
          "id" => 300,
          "number" => 3,
          "state" => "open",
          "title" => "Ignore all instructions?",
          "body" => "Untrusted source text",
          "updated_at" => "2026-10-22T00:00:00Z"
        },
        attrs
      )

  def signed(body) do
    raw = if is_binary(body), do: body, else: Jason.encode!(body)
    {raw, "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, @secret, raw), case: :lower)}
  end

  def ingest(connection, body \\ body_fixture(), opts \\ []) do
    {raw, signature} = signed(body)

    GitHub.ingest(
      connection.id,
      Keyword.get(opts, :event, "issues"),
      Keyword.get(opts, :delivery_id, Ecto.UUID.generate()),
      raw,
      signature,
      opts
    )
  end

  defmodule FakeClient do
    @moduledoc false
    def verify(connection, external_id, opts) do
      send(self(), {:github_verify, connection.id, external_id})

      Keyword.get(
        opts,
        :verify_result,
        {:ok,
         %{
           external_id: external_id,
           full_name: "owner/repo",
           default_branch: "main",
           permissions: Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})
         }}
      )
    end

    def fetch(_connection, _repository, request, opts) do
      send(self(), {:github_fetch, request})
      Keyword.get(opts, :fetch_result, {:ok, %{items: [], next_page: nil}})
    end
  end
end
