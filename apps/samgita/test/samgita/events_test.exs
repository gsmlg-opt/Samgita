defmodule Samgita.EventsTest do
  use Samgita.DataCase, async: true

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

  test "subscribe and receive task_failed events", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    task = %{project_id: project_id, id: "task-2"}
    Events.task_failed(task)
    assert_receive {:task_failed, ^task}
  end

  test "subscribe and receive agent_state_changed events", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    Events.agent_state_changed(project_id, "agent-1", :act)
    assert_receive {:agent_state_changed, "agent-1", :act}
  end

  test "subscribe_agents receives agent spawned events", %{project_id: project_id} do
    Events.subscribe_agents()

    Events.agent_spawned(project_id, "agent-2", "eng-frontend")
    assert_receive {:agent_spawned, "agent-2", "eng-frontend"}
  end

  test "subscribe_all_projects receives project updates" do
    Events.subscribe_all_projects()

    project = %{id: Ecto.UUID.generate(), name: "test"}
    Events.project_updated(project)
    assert_receive {:project_updated, ^project}
  end

  test "phase_changed broadcasts to both project and all_projects channels", %{
    project_id: project_id
  } do
    Events.subscribe_project(project_id)
    Events.subscribe_all_projects()

    Events.phase_changed(project_id, :qa)
    assert_receive {:phase_changed, ^project_id, :qa}
    assert_receive {:project_updated, ^project_id, :qa}
  end

  test "activity_log broadcasts to project topic", %{project_id: project_id} do
    Events.subscribe_project(project_id)

    entry = Events.build_log_entry(:agent, "agent-1", :act, "Executing task")
    Events.activity_log(project_id, entry)

    assert_receive {:activity_log, ^entry}
  end

  test "build_log_entry creates well-formed map without output", %{project_id: _project_id} do
    entry =
      Events.build_log_entry(:orchestrator, "orchestrator", :phase_change, "Entering bootstrap")

    assert is_integer(entry.id)
    assert %DateTime{} = entry.timestamp
    assert entry.source == :orchestrator
    assert entry.source_id == "orchestrator"
    assert entry.stage == :phase_change
    assert entry.message == "Entering bootstrap"
    assert entry.output == nil
  end

  test "build_log_entry creates well-formed map with output", %{project_id: _project_id} do
    entry =
      Events.build_log_entry(:agent, "agent-1", :act, "Claude returned result",
        output: "some output text"
      )

    assert entry.source == :agent
    assert entry.output == "some output text"
  end
end
