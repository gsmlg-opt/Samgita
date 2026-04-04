defmodule Samgita.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      Samgita.Repo,
      {DNSCluster, query: Application.get_env(:samgita, :dns_cluster_query) || :ignore},
      {Cluster.Supervisor, [topologies, [name: Samgita.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Samgita.PubSub},
      {Finch, name: Samgita.Finch},
      Samgita.Cache,
      {Horde.Registry, name: Samgita.AgentRegistry, keys: :unique, members: :auto},
      {Horde.DynamicSupervisor,
       name: Samgita.AgentSupervisor, strategy: :one_for_one, members: :auto},
      Samgita.Agent.CircuitBreaker,
      Samgita.Provider.SessionRegistry,
      {Oban, Application.fetch_env!(:samgita, Oban)},
      Samgita.Project.Recovery
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Samgita.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
