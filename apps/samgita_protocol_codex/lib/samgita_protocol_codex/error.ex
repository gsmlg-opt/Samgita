defmodule SamgitaProtocolCodex.Error do
  @moduledoc """
  Native driver failure. `wire` preserves an upstream error without logging it.

  Upstream messages and data can contain secrets. Inspect and Exception.message
  deliberately expose only the local code; authorized callers can read `wire`.
  An uncertain outcome never grants permission to retry a mutation.
  """
  defexception [:code, :wire, details: %{}, uncertain: false, message: "Codex request failed"]

  @type t :: %__MODULE__{
          code: atom() | nil,
          wire: map() | nil,
          details: map(),
          uncertain: boolean(),
          message: String.t()
        }

  def new(code, details \\ %{}, attrs \\ []) when is_atom(code) and is_map(details) do
    struct!(__MODULE__, Keyword.merge([code: code, details: details], attrs))
  end

  def upstream(%{"error" => %{"code" => code}} = wire) do
    new(:upstream_error, %{"upstream_code" => code}, wire: wire)
  end

  @impl true
  def message(failure), do: "Codex request failed: #{failure.code}"
end

defimpl Inspect, for: SamgitaProtocolCodex.Error do
  import Inspect.Algebra

  def inspect(failure, opts) do
    concat([
      "#SamgitaProtocolCodex.Error<",
      to_doc(failure.code, opts),
      ", uncertain: ",
      to_doc(failure.uncertain, opts),
      ">"
    ])
  end
end
