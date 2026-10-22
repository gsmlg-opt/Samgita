defmodule Samgita.Principal do
  @moduledoc "Authenticated caller, constructed by trusted transport adapters; contains no secret."
  defstruct [:kind, :agent_id, :credential_id, :connection_id, :generation]
  def operator, do: %__MODULE__{kind: :operator}
end
