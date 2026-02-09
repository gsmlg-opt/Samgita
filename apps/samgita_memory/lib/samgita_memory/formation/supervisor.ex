defmodule SamgitaMemory.Formation.Supervisor do
  @moduledoc "Supervises telemetry handler registration for memory formation."

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Attach telemetry handlers on supervisor init
    SamgitaMemory.Formation.TelemetryHandler.attach()

    # No children to supervise — handlers are registered with :telemetry
    Supervisor.init([], strategy: :one_for_one)
  end
end
