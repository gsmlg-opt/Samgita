defmodule Samgita.Domain.ArtifactTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Artifact

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          type: :code,
          path: "lib/app/main.ex",
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid without type" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          path: "lib/app/main.ex",
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without path" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          type: :code,
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{path: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without project_id" do
      changeset =
        Artifact.changeset(%Artifact{}, %{type: :code, path: "lib/app/main.ex"})

      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults metadata to empty map" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          type: :doc,
          path: "README.md",
          project_id: Ecto.UUID.generate()
        })

      artifact = Ecto.Changeset.apply_changes(changeset)
      assert artifact.metadata == %{}
    end

    test "accepts optional fields" do
      changeset =
        Artifact.changeset(%Artifact{}, %{
          type: :config,
          path: "config/prod.exs",
          content: "use Config",
          content_hash: "abc123",
          metadata: %{"version" => 1},
          project_id: Ecto.UUID.generate(),
          task_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end
  end
end
