defmodule Samgita.Error do
  @moduledoc "Stable management errors with safe, non-secret details."
  defexception [:code, :message, details: %{}]

  def new(code, details \\ %{}),
    do: %__MODULE__{
      code: code,
      message: code |> to_string() |> String.replace("_", " "),
      details: details
    }
end
