defmodule Samgita.Domain.MemoryTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Memory

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        Memory.changeset(%Memory{}, %{
          type: :episodic,
          content: "Learned to use gen_statem",
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid without type" do
      changeset =
        Memory.changeset(%Memory{}, %{
          content: "some content",
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without content" do
      changeset =
        Memory.changeset(%Memory{}, %{
          type: :semantic,
          project_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
      assert %{content: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without project_id" do
      changeset =
        Memory.changeset(%Memory{}, %{type: :procedural, content: "content"})

      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults importance to 0.5" do
      changeset =
        Memory.changeset(%Memory{}, %{
          type: :episodic,
          content: "content",
          project_id: Ecto.UUID.generate()
        })

      memory = Ecto.Changeset.apply_changes(changeset)
      assert memory.importance == 0.5
    end

    test "validates importance range - too low" do
      changeset =
        Memory.changeset(%Memory{}, %{
          type: :episodic,
          content: "content",
          project_id: Ecto.UUID.generate(),
          importance: -0.1
        })

      refute changeset.valid?
      assert %{importance: [_]} = errors_on(changeset)
    end

    test "validates importance range - too high" do
      changeset =
        Memory.changeset(%Memory{}, %{
          type: :episodic,
          content: "content",
          project_id: Ecto.UUID.generate(),
          importance: 1.1
        })

      refute changeset.valid?
      assert %{importance: [_]} = errors_on(changeset)
    end

    test "accepts boundary importance values" do
      for importance <- [0.0, 1.0] do
        changeset =
          Memory.changeset(%Memory{}, %{
            type: :semantic,
            content: "content",
            project_id: Ecto.UUID.generate(),
            importance: importance
          })

        assert changeset.valid?, "Expected valid for importance #{importance}"
      end
    end

    test "accepts optional accessed_at" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        Memory.changeset(%Memory{}, %{
          type: :procedural,
          content: "How to deploy",
          project_id: Ecto.UUID.generate(),
          accessed_at: now
        })

      assert changeset.valid?
    end
  end
end
