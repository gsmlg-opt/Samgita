defmodule Samgita.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Samgita.Repo,
      {Phoenix.PubSub, name: Samgita.PubSub},
      {Styx, Application.fetch_env!(:samgita, Styx)},
      Samgita.CodexHosts.Runtime
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Samgita.Supervisor)
  end
end
