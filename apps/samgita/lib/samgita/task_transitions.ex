defmodule Samgita.TaskTransitions do
  @moduledoc "Pure management transitions; execution and acceptance use separate commands."
  @transitions %{
    "open" => ~w(blocked cancelled),
    "in_progress" => ~w(blocked),
    "blocked" => ~w(open cancelled),
    "failed" => ~w(open cancelled),
    "cancelled" => ~w(open),
    "awaiting_review" => ~w(open blocked cancelled),
    "accepted" => ~w(open)
  }

  def validate(from, to) do
    if to in Map.get(@transitions, from, []), do: :ok, else: {:error, "invalid_transition"}
  end
end
