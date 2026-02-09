defmodule SamgitaWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SamgitaWeb.Telemetry,
      SamgitaWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SamgitaWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SamgitaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
