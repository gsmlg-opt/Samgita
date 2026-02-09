defmodule SamgitaMemory.Workers.Compaction do
  @moduledoc """
  Oban cron worker that performs confidence decay and memory pruning.

  Decay formula: new_confidence = confidence * decay_rate
  Decay rates by memory type:
    - episodic:   0.98/day  (half-life ~34 days)
    - semantic:   0.995/day (half-life ~138 days)
    - procedural: 0.999/day (half-life ~693 days)

  Memories below 0.1 confidence are pruned.
  Access resets confidence to max(current, 0.8).
  """

  use Oban.Worker,
    queue: :compaction,
    max_attempts: 3,
    priority: 3

  alias SamgitaMemory.Repo
  alias SamgitaMemory.Memories.Memory
  alias SamgitaMemory.Cache.MemoryTable

  import Ecto.Query

  @decay_rates %{
    episodic: 0.98,
    semantic: 0.995,
    procedural: 0.999
  }

  @prune_threshold 0.1

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case args do
      %{"action" => "decay"} ->
        run_decay()

      %{"action" => "prune"} ->
        run_prune()
        :ok

      _ ->
        run_decay_and_prune()
    end
  end

  @doc "Run confidence decay for all memory types."
  def run_decay do
    for {type, rate} <- @decay_rates do
      decay_type(type, rate)
    end

    :ok
  end

  @doc "Prune memories below the confidence threshold."
  def run_prune do
    {count, _} =
      Memory
      |> where([m], m.confidence < ^@prune_threshold)
      |> Repo.delete_all()

    if count > 0 do
      MemoryTable.clear()
    end

    {:ok, count}
  end

  @doc "Run both decay and prune."
  def run_decay_and_prune do
    run_decay()
    run_prune()
    :ok
  end

  @doc "Get the decay rate for a memory type."
  def decay_rate(type), do: Map.get(@decay_rates, type, 0.995)

  @doc "Get the prune threshold."
  def prune_threshold, do: @prune_threshold

  defp decay_type(type, rate) do
    # Use raw SQL for the multiplicative update (Ecto doesn't support multiplication in update_all)
    Repo.query!(
      """
      UPDATE sm_memories
      SET confidence = confidence * $1,
          updated_at = NOW()
      WHERE memory_type = $2
        AND confidence > $3
      """,
      [rate, Atom.to_string(type), @prune_threshold]
    )
  end

  @doc "Enqueue a decay+prune job."
  def enqueue do
    %{action: "decay_and_prune"}
    |> new()
    |> Oban.insert(SamgitaMemory.Oban)
  end
end
