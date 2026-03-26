defmodule SamgitaWeb.PrdChatLiveTest do
  use SamgitaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Samgita.{Prds, Projects}

  setup do
    Mox.set_mox_global(self())

    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

    Mox.stub(Samgita.MockOban, :insert, fn _job -> {:ok, %Oban.Job{}} end)

    :ok
  end

  defp create_project(attrs \\ %{}) do
    defaults = %{
      name: "Chat Test Project",
      git_url: "git@github.com:test/chat-#{System.unique_integer([:positive])}.git",
      prd_content: "# Chat Test"
    }

    {:ok, project} = Projects.create_project(Map.merge(defaults, attrs))
    project
  end

  defp create_prd(project, attrs \\ %{}) do
    defaults = %{
      project_id: project.id,
      title: "Existing PRD",
      content: "# Existing Content",
      status: :approved
    }

    {:ok, prd} = Prds.create_prd(Map.merge(defaults, attrs))
    prd
  end

  describe "new PRD" do
    test "renders new PRD form", %{conn: conn} do
      project = create_project()
      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert html =~ "New PRD"
      assert html =~ project.name
      assert html =~ "Create PRD"
    end

    test "validates title on change", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      html =
        render_change(view, "validate", %{
          "prd" => %{"title" => "Updated Title", "content" => "Some content"}
        })

      assert html =~ "Updated Title"
    end

    test "creates PRD with title and content", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      {:ok, _view, html} =
        view
        |> form("form", prd: %{title: "New Feature PRD", content: "# Feature"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "PRD created"
    end

    test "shows error for empty title", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      html =
        view
        |> form("form", prd: %{title: "", content: "content"})
        |> render_submit()

      assert html =~ "Title is required"
    end

    test "creates draft PRD when content is empty", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      {:ok, _view, _html} =
        view
        |> form("form", prd: %{title: "Draft PRD", content: ""})
        |> render_submit()
        |> follow_redirect(conn)

      # Verify the PRD was created as draft
      prds = Prds.list_prds(project.id)
      prd = Enum.find(prds, &(&1.title == "Draft PRD"))
      assert prd.status == :draft
    end

    test "redirects to project page on project not found", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/projects/#{Ecto.UUID.generate()}/prds/new")
    end
  end

  describe "edit PRD" do
    test "renders edit form with existing data", %{conn: conn} do
      project = create_project()
      prd = create_prd(project, %{title: "Edit Me", content: "# Edit Content"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")
      assert html =~ "Edit PRD"
      assert html =~ "Edit Me"
      assert html =~ "Update PRD"
    end

    test "updates PRD", %{conn: conn} do
      project = create_project()
      prd = create_prd(project)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")

      {:ok, _view, html} =
        view
        |> form("form", prd: %{title: "Updated Title", content: "# Updated"})
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~ "PRD updated"
    end

    test "redirects on PRD not found", %{conn: conn} do
      project = create_project()

      assert {:error, {:live_redirect, %{to: _path}}} =
               live(conn, ~p"/projects/#{project.id}/prds/#{Ecto.UUID.generate()}")
    end
  end

  describe "preview toggle" do
    test "toggles between edit and preview mode", %{conn: conn} do
      project = create_project()
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      # Initially in edit mode - shows textarea
      assert html =~ "Preview"

      # Toggle to preview
      html = render_click(view, "toggle_preview")
      assert html =~ "Edit"

      # Toggle back to edit
      html = render_click(view, "toggle_preview")
      assert html =~ "Preview"
    end
  end

  describe "chat tab" do
    test "switches to chat tab and shows empty message prompt", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      html = render_click(view, "switch_tab", %{"tab" => "chat"})
      assert html =~ "Start a conversation to define your PRD requirements"
      assert html =~ "Send"
    end

    test "switches between editor and chat tabs", %{conn: conn} do
      project = create_project()
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      # Initially on editor tab
      assert html =~ "Content (Markdown)"

      # Switch to chat
      html = render_click(view, "switch_tab", %{"tab" => "chat"})
      assert html =~ "Start a conversation"
      refute html =~ "Content (Markdown)"

      # Switch back to editor
      html = render_click(view, "switch_tab", %{"tab" => "editor"})
      assert html =~ "Content (Markdown)"
      refute html =~ "Start a conversation"
    end

    test "chat tab renders messages for existing PRD with chat history", %{conn: conn} do
      project = create_project()
      prd = create_prd(project, %{title: "Chat PRD", content: "# Chat"})

      # Add some chat messages
      Prds.add_user_message(prd.id, "I want to build a task manager")
      Prds.add_assistant_message(prd.id, "Great idea! Let me help you define the requirements.")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")

      html = render_click(view, "switch_tab", %{"tab" => "chat"})
      assert html =~ "I want to build a task manager"
      assert html =~ "Great idea! Let me help you define the requirements."
    end

    test "send_message event triggers Claude query and appends messages", %{conn: conn} do
      Mox.set_mox_global(self())

      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
        {:ok, "Here are some suggestions for your app."}
      end)

      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      # Switch to chat tab
      render_click(view, "switch_tab", %{"tab" => "chat"})

      # Send a message
      render_submit(view, "send_message", %{"chat_input" => "Build a todo app"})

      # Wait for async task to send the response back
      # The LiveView will receive {:chat_response, {:ok, response}, message}
      assert_receive_and_render(view, 2000)

      html = render(view)
      assert html =~ "Build a todo app"
      assert html =~ "Here are some suggestions for your app."
    end

    test "send_message ignores empty messages", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      render_click(view, "switch_tab", %{"tab" => "chat"})
      html = render_submit(view, "send_message", %{"chat_input" => ""})

      # Should still show empty state
      assert html =~ "Start a conversation"
    end

    test "generate_prd event does nothing when no messages", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")

      render_click(view, "switch_tab", %{"tab" => "chat"})

      # generate_prd should be a no-op when there are no messages
      html = render_click(view, "generate_prd")
      # Should remain on chat tab with empty state
      assert html =~ "Start a conversation"
    end

    test "generate_prd produces content and switches to editor tab", %{conn: conn} do
      Mox.set_mox_global(self())

      # First call is for chat response, second for PRD generation
      Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts ->
        {:ok, "# Generated PRD\n\n## Overview\n\nA task management application."}
      end)

      project = create_project()
      prd = create_prd(project, %{title: "Gen PRD", content: ""})

      # Add a message so generate_prd has something to work with
      Prds.add_user_message(prd.id, "Build a task manager")
      Prds.add_assistant_message(prd.id, "Sure, let me help with that.")

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")
      render_click(view, "switch_tab", %{"tab" => "chat"})

      # Trigger generation
      render_click(view, "generate_prd")

      # Wait for async task to complete
      assert_receive_and_render(view, 2000)

      html = render(view)
      # Should switch back to editor tab with generated content
      assert html =~ "PRD generated from conversation"
    end

    test "chat shows badge with message count", %{conn: conn} do
      project = create_project()
      prd = create_prd(project, %{title: "Badge Test", content: "# Test"})

      Prds.add_user_message(prd.id, "Hello")
      Prds.add_assistant_message(prd.id, "Hi there")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/prds/#{prd.id}")
      # The Chat button should show badge count of 2
      assert html =~ "2"
    end
  end

  # Helper to wait for async messages and re-render
  defp assert_receive_and_render(view, timeout) do
    # Give the async Task time to complete and send messages back to the LiveView
    Process.sleep(min(timeout, 500))
    # Force a render to pick up any handle_info updates
    render(view)
  end

  describe "back navigation" do
    test "has back link to project", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert has_element?(view, "a", "Back to Project")
    end

    test "has cancel link to project", %{conn: conn} do
      project = create_project()
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/prds/new")
      assert has_element?(view, "a", "Cancel")
    end
  end
end
