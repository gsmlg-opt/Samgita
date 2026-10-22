defmodule Samgita.GitHub.Failure do
  @moduledoc "Safe GitHub failure metadata. Provider bodies and credentials are never included."
  @enforce_keys [:class, :code]
  defstruct [:class, :code, :retry_after]

  def new(class, code, retry_after \\ nil),
    do: %__MODULE__{class: class, code: code, retry_after: retry_after}
end
