defmodule Samgita.Project.Memory do
  @moduledoc """
  Per-project memory server managing episodic, semantic, and procedural
  memory for agent context and learning persistence.
  """

  use GenServer

  alias Samgita.Domain.Memory, as: MemorySchema
  alias Samgita.Repo

  defstruct [:project_id, episodic: [], semantic: [], procedural: []]

  ## Public API

  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    GenServer.start_link(__MODULE__, opts, name: via(project_id))
  end

  def child_spec(opts) do
    project_id = Keyword.fetch!(opts, :project_id)

    %{
      id: {:memory, project_id},
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def add_memory(project_id, type, content, importance \\ 0.5) do
    GenServer.call(via(project_id), {:add_memory, type, content, importance})
  end

  def get_memories(project_id, type) do
    GenServer.call(via(project_id), {:get_memories, type})
  end

  def get_context(project_id) do
    GenServer.call(via(project_id), :get_context)
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    state = load_from_db(project_id)
    {:ok, state}
  end

  @impl true
  def handle_call({:add_memory, type, content, importance}, _from, state) do
    attrs = %{
      type: type,
      content: content,
      importance: importance,
      project_id: state.project_id,
      accessed_at: DateTime.utc_now()
    }

    case %MemorySchema{} |> MemorySchema.changeset(attrs) |> Repo.insert() do
      {:ok, memory} ->
        state = add_to_state(state, type, memory)
        {:reply, {:ok, memory}, state}

      {:error, changeset} ->
        {:reply, {:error, changeset}, state}
    end
  end

  @impl true
  def handle_call({:get_memories, type}, _from, state) do
    memories = Map.get(state, type, [])
    {:reply, memories, state}
  end

  @impl true
  def handle_call(:get_context, _from, state) do
    context = %{
      episodic: Enum.take(state.episodic, 10),
      semantic: state.semantic,
      procedural: state.procedural
    }

    {:reply, context, state}
  end

  ## Internal

  defp via(project_id) do
    {:via, Horde.Registry, {Samgita.AgentRegistry, {:memory, project_id}}}
  end

  defp load_from_db(project_id) do
    import Ecto.Query

    memories =
      MemorySchema
      |> where(project_id: ^project_id)
      |> order_by(asc: :inserted_at)
      |> Repo.all()

    %__MODULE__{
      project_id: project_id,
      episodic: Enum.filter(memories, &(&1.type == :episodic)),
      semantic: Enum.filter(memories, &(&1.type == :semantic)),
      procedural: Enum.filter(memories, &(&1.type == :procedural))
    }
  end

  defp add_to_state(state, :episodic, memory),
    do: %{state | episodic: [memory | state.episodic]}

  defp add_to_state(state, :semantic, memory),
    do: %{state | semantic: [memory | state.semantic]}

  defp add_to_state(state, :procedural, memory),
    do: %{state | procedural: [memory | state.procedural]}
end
