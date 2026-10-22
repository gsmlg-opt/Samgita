defmodule Samgita.TaskTransitionsTest do
  use ExUnit.Case, async: true
  alias Samgita.TaskTransitions

  test "management transitions do not accept work or start execution" do
    assert :ok = TaskTransitions.validate("open", "blocked")
    assert :ok = TaskTransitions.validate("failed", "open")
    assert :ok = TaskTransitions.validate("accepted", "open")
    assert {:error, "invalid_transition"} = TaskTransitions.validate("open", "in_progress")

    assert {:error, "invalid_transition"} =
             TaskTransitions.validate("awaiting_review", "accepted")

    assert {:error, "invalid_transition"} = TaskTransitions.validate("in_progress", "open")
  end
end
