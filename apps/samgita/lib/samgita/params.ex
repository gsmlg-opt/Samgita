defmodule Samgita.Params do
  @moduledoc false
  def strings(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  def strings(_), do: %{}

  def page(params) do
    params = strings(params)
    {number(params["limit"], 50, 1, 100), number(params["offset"], 0, 0, 100_000)}
  end

  defp number(value, default, low, high) do
    parsed = if is_binary(value), do: Integer.parse(value), else: {value, ""}

    case parsed do
      {n, ""} when is_integer(n) -> max(low, min(high, n))
      _ -> default
    end
  end

  def uuid?(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
end
