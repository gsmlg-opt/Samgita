defmodule Samgita.Agent.MessageRouterTest do
  use Samgita.DataCase, async: false

  alias Samgita.Agent.MessageRouter

  setup do
    project = insert_project()
    {:ok, pid} = MessageRouter.start_link(project_id: project.id)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{project_id: project.id, pid: pid}
  end

  defp insert_project do
    {:ok, project} =
      Samgita.Projects.create_project(%{
        name: "Test Project",
        git_url: "https://github.com/test/msg-router-#{System.unique_integer([:positive])}"
      })

    project
  end

  describe "send_message/2" do
    test "delivers message via PubSub", %{project_id: project_id} do
      Phoenix.PubSub.subscribe(Samgita.PubSub, "samgita:agents:#{project_id}")

      message = %{
        sender_agent_id: "eng-backend-1",
        recipient_agent_id: "eng-frontend-1",
        message_type: :notify,
        content: "API endpoint /users is ready"
      }

      assert :ok = MessageRouter.send_message(project_id, message)
      assert_receive {:agent_message, received}
      assert received.content == "API endpoint /users is ready"
    end

    test "enforces budget limit", %{project_id: project_id} do
      message = %{
        sender_agent_id: "eng-backend-1",
        content: "msg",
        task_id: "task-1"
      }

      for _ <- 1..10 do
        assert :ok = MessageRouter.send_message(project_id, message)
      end

      assert {:error, :budget_exceeded} = MessageRouter.send_message(project_id, message)
    end

    test "enforces depth limit", %{project_id: project_id} do
      message = %{
        sender_agent_id: "eng-backend-1",
        content: "deep msg",
        depth: 3
      }

      assert {:error, :depth_exceeded} = MessageRouter.send_message(project_id, message)
    end

    test "allows messages under depth limit", %{project_id: project_id} do
      message = %{
        sender_agent_id: "eng-backend-1",
        content: "shallow msg",
        depth: 2
      }

      assert :ok = MessageRouter.send_message(project_id, message)
    end
  end

  describe "reset_budget/2" do
    test "allows sending after budget reset", %{project_id: project_id} do
      message = %{sender_agent_id: "agent-1", content: "msg", task_id: "t1"}

      for _ <- 1..10, do: MessageRouter.send_message(project_id, message)
      assert {:error, :budget_exceeded} = MessageRouter.send_message(project_id, message)

      MessageRouter.reset_budget(project_id, "agent-1")
      # Cast is async; give it a moment to process
      Process.sleep(10)
      assert :ok = MessageRouter.send_message(project_id, message)
    end
  end
end
