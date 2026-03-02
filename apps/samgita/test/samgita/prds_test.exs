defmodule Samgita.PrdsTest do
  use Samgita.DataCase, async: true

  alias Samgita.Prds
  alias Samgita.Projects
  alias Samgita.Domain.Prd
  alias Samgita.Domain.ChatMessage

  defp create_project do
    {:ok, project} =
      Projects.create_project(%{
        name: "PRD Test Project",
        git_url: "git@github.com:test/prds-#{System.unique_integer([:positive])}.git"
      })

    project
  end

  defp create_prd(project, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          project_id: project.id,
          title: "Test PRD #{System.unique_integer([:positive])}",
          content: "# PRD Content"
        },
        attrs
      )

    {:ok, prd} = Prds.create_prd(attrs)
    prd
  end

  describe "list_prds/1" do
    test "returns empty list when no prds" do
      project = create_project()
      assert Prds.list_prds(project.id) == []
    end

    test "returns prds for project" do
      project = create_project()
      prd = create_prd(project)
      results = Prds.list_prds(project.id)
      assert length(results) == 1
      assert hd(results).id == prd.id
    end

    test "does not return prds from other projects" do
      project1 = create_project()
      project2 = create_project()
      _prd = create_prd(project1)
      assert Prds.list_prds(project2.id) == []
    end
  end

  describe "get_prd/1" do
    test "returns prd when found" do
      project = create_project()
      prd = create_prd(project)
      assert {:ok, found} = Prds.get_prd(prd.id)
      assert found.id == prd.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Prds.get_prd(Ecto.UUID.generate())
    end
  end

  describe "get_prd!/1" do
    test "returns prd when found" do
      project = create_project()
      prd = create_prd(project)
      found = Prds.get_prd!(prd.id)
      assert found.id == prd.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Prds.get_prd!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_prd_with_messages/1" do
    test "returns prd with messages" do
      project = create_project()
      prd = create_prd(project)
      {:ok, _msg} = Prds.add_user_message(prd.id, "Hello")
      {:ok, _msg} = Prds.add_assistant_message(prd.id, "Hi there")

      assert {:ok, loaded} = Prds.get_prd_with_messages(prd.id)
      assert loaded.id == prd.id
      assert length(loaded.chat_messages) == 2
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Prds.get_prd_with_messages(Ecto.UUID.generate())
    end
  end

  describe "create_prd/1" do
    test "creates prd with valid attrs" do
      project = create_project()

      assert {:ok, %Prd{} = prd} =
               Prds.create_prd(%{
                 project_id: project.id,
                 title: "New PRD",
                 content: "Content"
               })

      assert prd.title == "New PRD"
      assert prd.status == :draft
      assert prd.version == 1
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Prds.create_prd(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "update_prd/2" do
    test "updates with valid attrs" do
      project = create_project()
      prd = create_prd(project)

      assert {:ok, updated} = Prds.update_prd(prd, %{title: "Updated PRD"})
      assert updated.title == "Updated PRD"
    end
  end

  describe "delete_prd/1" do
    test "deletes the prd" do
      project = create_project()
      prd = create_prd(project)
      assert {:ok, _} = Prds.delete_prd(prd)
      assert {:error, :not_found} = Prds.get_prd(prd.id)
    end
  end

  describe "list_messages/1" do
    test "returns messages for prd" do
      project = create_project()
      prd = create_prd(project)
      {:ok, _} = Prds.add_user_message(prd.id, "First message")
      {:ok, _} = Prds.add_assistant_message(prd.id, "Second message")

      messages = Prds.list_messages(prd.id)
      assert length(messages) == 2
    end

    test "returns empty list when no messages" do
      project = create_project()
      prd = create_prd(project)
      assert Prds.list_messages(prd.id) == []
    end
  end

  describe "create_message/1" do
    test "creates message with valid attrs" do
      project = create_project()
      prd = create_prd(project)

      assert {:ok, %ChatMessage{} = msg} =
               Prds.create_message(%{prd_id: prd.id, role: :user, content: "Hello"})

      assert msg.role == :user
      assert msg.content == "Hello"
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Prds.create_message(%{})
      assert %{role: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "add_user_message/2" do
    test "adds user message" do
      project = create_project()
      prd = create_prd(project)
      assert {:ok, msg} = Prds.add_user_message(prd.id, "User says hello")
      assert msg.role == :user
      assert msg.content == "User says hello"
    end
  end

  describe "add_assistant_message/2" do
    test "adds assistant message" do
      project = create_project()
      prd = create_prd(project)
      assert {:ok, msg} = Prds.add_assistant_message(prd.id, "Assistant responds")
      assert msg.role == :assistant
      assert msg.content == "Assistant responds"
    end
  end

  describe "add_system_message/2" do
    test "adds system message" do
      project = create_project()
      prd = create_prd(project)
      assert {:ok, msg} = Prds.add_system_message(prd.id, "System notification")
      assert msg.role == :system
      assert msg.content == "System notification"
    end
  end

  describe "generate_prd_content/1" do
    test "combines assistant messages into content" do
      project = create_project()
      prd = create_prd(project)
      {:ok, _} = Prds.add_user_message(prd.id, "User input")
      {:ok, _} = Prds.add_assistant_message(prd.id, "First response")
      {:ok, _} = Prds.add_assistant_message(prd.id, "Second response")

      assert {:ok, updated} = Prds.generate_prd_content(prd.id)
      assert updated.content =~ "First response"
      assert updated.content =~ "Second response"
      refute updated.content =~ "User input"
    end

    test "returns error when prd not found" do
      assert {:error, :not_found} = Prds.generate_prd_content(Ecto.UUID.generate())
    end
  end
end
