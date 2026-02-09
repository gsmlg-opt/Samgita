defmodule Samgita.WebhooksTest do
  use Samgita.DataCase, async: true

  alias Samgita.Webhooks

  @valid_attrs %{
    url: "https://example.com/webhook",
    events: ["task.completed", "task.failed"]
  }

  test "creates webhook with valid attrs" do
    assert {:ok, webhook} = Webhooks.create_webhook(@valid_attrs)
    assert webhook.url == "https://example.com/webhook"
    assert webhook.events == ["task.completed", "task.failed"]
    assert webhook.active == true
  end

  test "fails with invalid URL" do
    assert {:error, changeset} =
             Webhooks.create_webhook(%{url: "not-a-url", events: ["task.completed"]})

    assert %{url: ["must be a valid HTTP/HTTPS URL"]} = errors_on(changeset)
  end

  test "fails with invalid events" do
    assert {:error, changeset} =
             Webhooks.create_webhook(%{url: "https://example.com", events: ["invalid.event"]})

    assert %{events: [msg]} = errors_on(changeset)
    assert msg =~ "invalid events"
  end

  test "lists webhooks" do
    Webhooks.create_webhook(@valid_attrs)
    assert [_] = Webhooks.list_webhooks()
  end

  test "deletes webhook" do
    {:ok, webhook} = Webhooks.create_webhook(@valid_attrs)
    assert {:ok, _} = Webhooks.delete_webhook(webhook.id)
    assert {:error, :not_found} = Webhooks.get_webhook(webhook.id)
  end

  test "delete returns error for nonexistent webhook" do
    assert {:error, :not_found} = Webhooks.delete_webhook(Ecto.UUID.generate())
  end

  test "get_webhook returns webhook by id" do
    {:ok, webhook} = Webhooks.create_webhook(@valid_attrs)
    assert {:ok, found} = Webhooks.get_webhook(webhook.id)
    assert found.id == webhook.id
  end

  test "dispatch enqueues jobs for matching webhooks" do
    {:ok, _webhook} = Webhooks.create_webhook(@valid_attrs)
    assert :ok == Webhooks.dispatch("task.completed", %{task_id: "123"})
  end

  test "dispatch skips webhooks that don't match event" do
    {:ok, _webhook} =
      Webhooks.create_webhook(%{
        url: "https://example.com/hook",
        events: ["agent.spawned"]
      })

    assert :ok == Webhooks.dispatch("task.completed", %{task_id: "123"})
  end
end
