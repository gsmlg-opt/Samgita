defmodule Samgita.EventsTest do
  use ExUnit.Case, async: true

  alias Samgita.Events

  setup do
    project_id = Ecto.UUID.generate()
    %{project_id: project_id}
  end

  test "subscribe and receive project events", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    Events.phase_changed(project_id, :development)
    assert_receive {:phase_changed, ^project_id, :development}
  end

  test "subscribe and receive agent events", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    Events.agent_spawned(project_id, "agent-1", "eng-backend")
    assert_receive {:agent_spawned, "agent-1", "eng-backend"}
  end

  test "subscribe and receive task events", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    task = %{project_id: project_id, id: "task-1"}
    Events.task_completed(task)
    assert_receive {:task_completed, ^task}
  end
end
