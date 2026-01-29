defmodule Samgita.Project.MemoryTest do
  # Cannot be async due to shared sandbox mode needed for GenServer init
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Project.Memory
  alias Samgita.Projects

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})

    {:ok, project} =
      Projects.create_project(%{
        name: "Memory Test",
        git_url: "git@github.com:test/memory-#{System.unique_integer([:positive])}.git"
      })

    {:ok, pid} = GenServer.start_link(Memory, project_id: project.id)
    %{project: project, pid: pid}
  end

  test "adds episodic memory", %{pid: pid} do
    assert {:ok, memory} = GenServer.call(pid, {:add_memory, :episodic, "test event", 0.7})
    assert memory.type == :episodic
    assert memory.content == "test event"
    assert memory.importance == 0.7
  end

  test "adds semantic memory", %{pid: pid} do
    assert {:ok, _} = GenServer.call(pid, {:add_memory, :semantic, "pattern learned", 0.9})
    memories = GenServer.call(pid, {:get_memories, :semantic})
    assert length(memories) == 1
  end

  test "returns context with all memory types", %{pid: pid} do
    GenServer.call(pid, {:add_memory, :episodic, "event 1", 0.5})
    GenServer.call(pid, {:add_memory, :semantic, "pattern 1", 0.8})
    GenServer.call(pid, {:add_memory, :procedural, "skill 1", 0.6})

    context = GenServer.call(pid, :get_context)
    assert length(context.episodic) == 1
    assert length(context.semantic) == 1
    assert length(context.procedural) == 1
  end
end
