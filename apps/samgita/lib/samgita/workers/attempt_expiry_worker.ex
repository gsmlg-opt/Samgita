defmodule Samgita.Workers.AttemptExpiryWorker do
  @moduledoc "Expiry holds unresolved effects and capacity; it never creates another execution."
  use Oban.Worker, queue: :hub_maintenance, max_attempts: 5, unique: [period: 60]
  import Ecto.Query
  alias Samgita.{Attempts, Principal, Repo}
  alias Samgita.Domain.TaskAttempt

  @impl true
  def perform(%Oban.Job{}) do
    case expire_due() do
      {:ok, _} -> :ok
      {:error, %{code: code}} -> {:error, code}
    end
  end

  def expire_due do
    now = DateTime.utc_now()

    due =
      Repo.all(
        from a in TaskAttempt,
          where:
            a.state in ["leased", "running"] and
              (a.lease_expires_at <= ^now or a.execution_deadline <= ^now or
                 (a.state == "leased" and a.start_deadline <= ^now)),
          order_by: a.id,
          limit: 100
      )

    Enum.reduce_while(due, {:ok, 0}, fn attempt, {:ok, count} ->
      case Attempts.expire(Principal.operator(), %{
             "command_id" => Ecto.UUID.generate(),
             "project_id" => attempt.project_id,
             "attempt_id" => attempt.id,
             "expected_version" => attempt.version
           }) do
        {:ok, _} ->
          {:cont, {:ok, count + 1}}

        {:error, %{code: code}} when code in [:stale_version, :invalid_transition] ->
          {:cont, {:ok, count}}

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
  end
end
