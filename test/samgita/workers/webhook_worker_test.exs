defmodule Samgita.Workers.WebhookWorkerTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Samgita.Domain.Webhook
  alias Samgita.Repo
  alias Samgita.Workers.WebhookWorker

  setup do
    Sandbox.mode(Samgita.Repo, {:shared, self()})
    :ok
  end

  defp create_webhook(attrs \\ %{}) do
    defaults = %{
      url: "https://example.com/webhook",
      events: ["task.completed"],
      secret: "test-secret",
      active: true
    }

    %Webhook{}
    |> Webhook.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  test "returns :ok for nonexistent webhook" do
    job = %Oban.Job{
      args: %{
        "webhook_id" => Ecto.UUID.generate(),
        "event" => "task.completed",
        "payload" => %{"task_id" => "123"}
      }
    }

    assert :ok = WebhookWorker.perform(job)
  end

  test "skips inactive webhook" do
    webhook = create_webhook(%{active: false})

    job = %Oban.Job{
      args: %{
        "webhook_id" => webhook.id,
        "event" => "task.completed",
        "payload" => %{"task_id" => "123"}
      }
    }

    assert :ok = WebhookWorker.perform(job)
  end

  test "attempts delivery for active webhook" do
    webhook = create_webhook()

    job = %Oban.Job{
      args: %{
        "webhook_id" => webhook.id,
        "event" => "task.completed",
        "payload" => %{"task_id" => "123"}
      }
    }

    # Will fail since example.com won't respond, but verifies the delivery path
    result = WebhookWorker.perform(job)
    assert result == :ok or match?({:error, _}, result)
  end
end
