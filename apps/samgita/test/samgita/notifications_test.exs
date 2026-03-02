defmodule Samgita.NotificationsTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.Notification
  alias Samgita.Notifications

  @valid_attrs %{
    title: "Test Alert",
    message: "Something important happened",
    type: "warning",
    priority: 4,
    recipient_email: "user@example.com"
  }

  defp create_notification(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Notification #{System.unique_integer([:positive])}",
          message: "A notification for testing",
          type: "info",
          recipient_email: "test@example.com"
        },
        attrs
      )

    {:ok, notification} = Notifications.create_notification(attrs)
    notification
  end

  describe "list_notifications/1" do
    test "returns empty list when no notifications" do
      assert Notifications.list_notifications() == []
    end

    test "returns all notifications" do
      notification = create_notification()
      results = Notifications.list_notifications()
      assert length(results) == 1
      assert hd(results).id == notification.id
    end

    test "filters by status" do
      _pending = create_notification()

      results = Notifications.list_notifications(status: "pending")
      Enum.each(results, fn n -> assert n.status == "pending" end)
    end

    test "filters by type" do
      create_notification(%{type: "error"})
      create_notification(%{type: "info"})

      results = Notifications.list_notifications(type: "error")
      assert length(results) == 1
      assert hd(results).type == "error"
    end

    test "limits results" do
      create_notification()
      create_notification()
      create_notification()

      results = Notifications.list_notifications(limit: 2)
      assert length(results) == 2
    end
  end

  describe "get_notification/1" do
    test "returns notification when found" do
      notification = create_notification()
      assert {:ok, found} = Notifications.get_notification(notification.id)
      assert found.id == notification.id
    end

    test "returns error when not found" do
      assert {:error, :not_found} = Notifications.get_notification(999_999)
    end
  end

  describe "create_notification/1" do
    test "creates notification with valid attrs" do
      assert {:ok, %Notification{} = notification} =
               Notifications.create_notification(@valid_attrs)

      assert notification.title == "Test Alert"
      assert notification.type == "warning"
      assert notification.priority == 4
      assert notification.status == "pending"
    end

    test "returns error for missing required fields" do
      assert {:error, changeset} = Notifications.create_notification(%{})
      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "returns error for invalid type" do
      attrs = Map.put(@valid_attrs, :type, "bogus")
      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert %{type: _} = errors_on(changeset)
    end

    test "returns error for invalid priority" do
      attrs = Map.put(@valid_attrs, :priority, 10)
      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert %{priority: _} = errors_on(changeset)
    end

    test "returns error for missing delivery method" do
      assert {:error, changeset} =
               Notifications.create_notification(%{
                 title: "No delivery",
                 message: "Missing email and webhook"
               })

      assert %{recipient_email: _} = errors_on(changeset)
    end
  end

  describe "update_notification/2" do
    test "updates with valid attrs" do
      notification = create_notification()

      assert {:ok, updated} =
               Notifications.update_notification(notification, %{title: "Updated Title"})

      assert updated.title == "Updated Title"
    end

    test "returns error for invalid attrs" do
      notification = create_notification()

      assert {:error, _changeset} =
               Notifications.update_notification(notification, %{type: "bad"})
    end
  end

  describe "delete_notification/1" do
    test "deletes the notification" do
      notification = create_notification()
      assert {:ok, _} = Notifications.delete_notification(notification)
      assert {:error, :not_found} = Notifications.get_notification(notification.id)
    end
  end

  describe "mark_as_sent/1" do
    test "marks notification as sent" do
      notification = create_notification()
      assert {:ok, sent} = Notifications.mark_as_sent(notification)
      assert sent.status == "sent"
      assert sent.sent_at != nil
    end
  end

  describe "mark_as_failed/1" do
    test "marks notification as failed" do
      notification = create_notification()
      assert {:ok, failed} = Notifications.mark_as_failed(notification)
      assert failed.status == "failed"
    end
  end

  describe "retry_notification/1" do
    test "retries a failed notification" do
      notification = create_notification()
      {:ok, failed} = Notifications.mark_as_failed(notification)

      assert {:ok, retried} = Notifications.retry_notification(failed)
      assert retried.status == "retrying"
      assert retried.retry_count == 1
    end

    test "returns error for non-retriable notification" do
      notification = create_notification()
      assert {:error, :not_retriable} = Notifications.retry_notification(notification)
    end

    test "returns error when max retries exceeded" do
      notification = create_notification(%{max_retries: 1})
      {:ok, failed} = Notifications.mark_as_failed(notification)
      {:ok, retried} = Notifications.retry_notification(failed)
      {:ok, failed_again} = Notifications.mark_as_failed(retried)

      assert {:error, :max_retries_exceeded} = Notifications.retry_notification(failed_again)
    end
  end

  describe "send_notification/1" do
    test "sends notification with email" do
      notification = create_notification()
      assert {:ok, sent} = Notifications.send_notification(notification)
      assert sent.status == "sent"
    end

    test "sends notification with webhook" do
      notification =
        create_notification(%{
          recipient_email: nil,
          webhook_url: "https://example.com/webhook"
        })

      assert {:ok, sent} = Notifications.send_notification(notification)
      assert sent.status == "sent"
    end
  end

  describe "get_pending_notifications/0" do
    test "returns pending notifications" do
      create_notification()
      results = Notifications.get_pending_notifications()
      assert results != []
      Enum.each(results, fn n -> assert n.status in ["pending", "retrying"] end)
    end

    test "does not include sent notifications" do
      notification = create_notification()
      {:ok, _sent} = Notifications.mark_as_sent(notification)
      results = Notifications.get_pending_notifications()
      refute Enum.any?(results, &(&1.id == notification.id))
    end
  end
end
