defmodule SamgitaProtocol.Capabilities do
  @moduledoc "Versioned groups are opt-in. An unsupported operation never falls back to another Agent."
  alias SamgitaProtocol.{Error, Schema}
  @groups ~w(project_events.v1 sessions.v1 streaming.v1 approvals.v1 cancellation.v1)
  def all, do: @groups

  def validate(groups) do
    if Schema.valid?(groups, :strings) and Enum.all?(groups, &(&1 in @groups)),
      do: :ok,
      else: {:error, Error.new("unsupported_capability")}
  end

  def negotiate(local, offered, required \\ []) do
    with :ok <- validate(local),
         true <- Schema.valid?(offered, :strings) and Schema.valid?(required, :strings),
         true <- Enum.all?(required, &(&1 in local and &1 in offered)) do
      {:ok, Enum.filter(local, &(&1 in offered)) |> Enum.sort()}
    else
      _ -> {:error, Error.new("unsupported_capability")}
    end
  end

  def methods(groups),
    do: Enum.filter(Schema.methods(), &(Schema.capability(&1) in groups)) |> Enum.sort()

  def supports?(groups, method),
    do: Schema.capability(method) == nil or Schema.capability(method) in groups
end
