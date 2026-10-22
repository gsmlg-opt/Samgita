defmodule Samgita.RepositoriesTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Principal, Projects, Repositories}

  test "URL aliases do not merge Projects and association changes use Project versions" do
    a = project_fixture()
    b = project_fixture()

    {:ok, association} =
      Repositories.associate(
        Principal.operator(),
        a["id"],
        command(%{
          "expected_version" => 1,
          "url" => "git@github.com:Org/Repo.git",
          "primary" => true
        })
      )

    repository_id = association["repository_id"]

    {:ok, other} =
      Repositories.associate(
        Principal.operator(),
        b["id"],
        command(%{
          "expected_version" => 1,
          "repository_id" => repository_id,
          "url" => "https://github.com/Org/Repo.git"
        })
      )

    assert other["repository_id"] == repository_id
    assert a["id"] != b["id"]
    assert {:ok, %{"data" => [_]}} = Repositories.list(Principal.operator(), a["id"])
    assert {:ok, updated} = Projects.get(Principal.operator(), a["id"])
    assert updated["version"] == 2

    assert Repositories.normalize("git@github.com:Org/Repo.git") ==
             Repositories.normalize("https://github.com/Org/Repo.git")

    assert Repositories.normalize("/unreachable/local") == "local:/unreachable/local"
    assert Repositories.normalize("https://secret@github.com/Org/Repo") == :invalid
  end

  test "unmapped historical Projects cannot gain a competing primary repository" do
    project = Repo.insert!(%Samgita.Domain.Project{name: "legacy", git_url: "/legacy/source"})

    assert {:error, %{code: :invalid_transition}} =
             Repositories.associate(
               Principal.operator(),
               project.id,
               command(%{
                 "expected_version" => 1,
                 "url" => "/different/source",
                 "primary" => true
               })
             )

    assert {:ok, %{"data" => []}} = Repositories.list(Principal.operator(), project.id)
    assert Repo.get!(Samgita.Domain.Project, project.id).version == 1
  end
end
