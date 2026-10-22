defmodule Samgita.Webhooks do
  @moduledoc """
  Legacy hook compatibility boundary. Original job IDs/args/signature semantics are retained,
  but jobs enter a disabled quarantine queue. Translation and network redelivery require review.
  Enqueue failures roll back the batch and are returned to the caller, never reported as delivery.
  """
  import Ecto.Query
  alias Samgita.{Commands, Repo}

  def dispatch(event, payload, opts \\ []) do
    enqueue = Keyword.get(opts, :enqueue, &Oban.insert/1)

    Commands.transaction(fn ->
      ids =
        Repo.all(
          from w in "webhooks",
            where: w.active and ^event in w.events,
            order_by: w.id,
            select: type(w.id, :binary_id)
        )

      jobs =
        Enum.map(ids, fn id ->
          changeset =
            Oban.Job.new(%{"webhook_id" => id, "event" => event, "payload" => payload},
              worker: "Samgita.Workers.WebhookWorker",
              queue: "legacy_webhooks",
              max_attempts: 5
            )

          case enqueue.(changeset) do
            {:ok, job} -> job.id
            {:error, _} -> Commands.fail!(:enqueue_failed, %{webhook_id: id})
          end
        end)

      %{"state" => "quarantined", "job_ids" => jobs}
    end)
  end
end
