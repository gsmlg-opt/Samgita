defmodule SamgitaMemory.Cache.Supervisor do
  @moduledoc "Supervisor for ETS cache tables."

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      SamgitaMemory.Cache.MemoryTable,
      SamgitaMemory.Cache.PRDTable
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
