defmodule SamgitaMemory.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SamgitaMemory.Repo,
      SamgitaMemory.Cache.Supervisor,
      SamgitaMemory.Formation.Supervisor,
      {Oban, Application.fetch_env!(:samgita_memory, Oban)}
    ]

    opts = [strategy: :one_for_one, name: SamgitaMemory.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
