defmodule SamgitaProtocol do
  @moduledoc """
  Transport-independent Agent messages. No supervisor, listener, Repo or platform configuration is loaded.

  See `SamgitaProtocol.Client` for pure connection state and `SamgitaProtocol.Handler` for host authority.
  """
  def version, do: "1.0"
  def capabilities, do: SamgitaProtocol.Capabilities.all()
end
