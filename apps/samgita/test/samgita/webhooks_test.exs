defmodule Samgita.WebhooksTest do
  use Samgita.DataCase, async: false
  alias Samgita.{Error, Repo, Webhooks}

  test "old hook enqueue errors propagate and roll back the entire batch" do
    ids = for _ <- 1..2, do: Ecto.UUID.generate()

    for id <- ids do
      Repo.query!(
        "INSERT INTO webhooks (id,url,events,active,secret,inserted_at,updated_at) VALUES ($1,'https://legacy.invalid/hook',ARRAY['task.completed'],true,'historical-secret',now(),now())",
        [Ecto.UUID.dump!(id)]
      )
    end

    Process.put(:hook_enqueue_calls, 0)

    enqueue = fn changeset ->
      count = Process.get(:hook_enqueue_calls)
      Process.put(:hook_enqueue_calls, count + 1)
      if count == 0, do: Oban.insert(changeset), else: {:error, :database_down}
    end

    before_jobs = Repo.aggregate(Oban.Job, :count)

    assert {:error, %Error{code: :enqueue_failed}} =
             Webhooks.dispatch("task.completed", %{"task_id" => "historical"}, enqueue: enqueue)

    assert Repo.aggregate(Oban.Job, :count) == before_jobs

    assert {:ok, %{"state" => "quarantined", "job_ids" => job_ids}} =
             Webhooks.dispatch("task.completed", %{"task_id" => "historical"})

    assert length(job_ids) == 2
    jobs = Repo.all(from j in Oban.Job, where: j.id in ^job_ids)

    assert Enum.all?(
             jobs,
             &(&1.queue == "legacy_webhooks" && &1.worker == "Samgita.Workers.WebhookWorker")
           )

    refute Keyword.has_key?(Application.fetch_env!(:samgita, Oban)[:queues], :legacy_webhooks)
    assert Enum.all?(jobs, &(Map.keys(&1.args) |> Enum.sort() == ~w(event payload webhook_id)))
    refute inspect(jobs) =~ "historical-secret"
    refute Code.ensure_loaded?(Samgita.Workers.WebhookWorker)
  end
end
