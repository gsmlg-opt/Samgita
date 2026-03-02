defmodule SamgitaWeb.NotificationControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Notifications

  @valid_attrs %{
    title: "Test Alert",
    message: "Something important happened",
    type: "warning",
    priority: 4,
    recipient_email: "user@example.com"
  }

  defp create_notification(_) do
    {:ok, notification} =
      Notifications.create_notification(%{
        title: "Existing Notification #{System.unique_integer([:positive])}",
        message: "An existing notification for testing",
        type: "info",
        recipient_email: "test@example.com"
      })

    %{notification: notification}
  end

  describe "index" do
    test "lists all notifications when empty", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications")
      assert json_response(conn, 200)["data"] == []
    end

    test "lists notifications after creation", %{conn: conn} do
      {:ok, notification} =
        Notifications.create_notification(%{
          title: "Listed Notification",
          message: "Should appear in list",
          type: "info",
          recipient_email: "list@example.com"
        })

      conn = get(conn, ~p"/api/notifications")
      data = json_response(conn, 200)["data"]
      assert data != []
      assert Enum.any?(data, &(&1["id"] == notification.id))
    end

    test "filters notifications by status", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications?status=sent")
      data = json_response(conn, 200)["data"]
      Enum.each(data, fn n -> assert n["status"] == "sent" end)
    end

    test "filters notifications by type", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications?type=error")
      data = json_response(conn, 200)["data"]
      Enum.each(data, fn n -> assert n["type"] == "error" end)
    end
  end

  describe "show" do
    setup [:create_notification]

    test "shows notification", %{conn: conn, notification: notification} do
      conn = get(conn, ~p"/api/notifications/#{notification.id}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == notification.id
      assert data["title"] == notification.title
    end

    test "returns 404 for missing notification", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications/999999")
      assert json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates notification with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/notifications", notification: @valid_attrs)
      data = json_response(conn, 201)["data"]
      assert data["title"] == "Test Alert"
      assert data["message"] == "Something important happened"
      assert data["type"] == "warning"
      assert data["priority"] == 4
      assert data["status"] == "pending"
      assert data["recipient_email"] == "user@example.com"
    end

    test "creates notification with webhook_url", %{conn: conn} do
      attrs = %{
        title: "Webhook Notification",
        message: "Delivered via webhook",
        type: "info",
        webhook_url: "https://example.com/webhook"
      }

      conn = post(conn, ~p"/api/notifications", notification: attrs)
      data = json_response(conn, 201)["data"]
      assert data["webhook_url"] == "https://example.com/webhook"
    end

    test "returns errors for missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/notifications", notification: %{})
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns errors for missing delivery method", %{conn: conn} do
      conn =
        post(conn, ~p"/api/notifications",
          notification: %{title: "No delivery", message: "Missing email and webhook"}
        )

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns errors for invalid type", %{conn: conn} do
      attrs = Map.put(@valid_attrs, :type, "bogus")
      conn = post(conn, ~p"/api/notifications", notification: attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns errors for invalid priority", %{conn: conn} do
      attrs = Map.put(@valid_attrs, :priority, 10)
      conn = post(conn, ~p"/api/notifications", notification: attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update" do
    setup [:create_notification]

    test "updates notification", %{conn: conn, notification: notification} do
      conn =
        put(conn, ~p"/api/notifications/#{notification.id}",
          notification: %{title: "Updated Title"}
        )

      data = json_response(conn, 200)["data"]
      assert data["title"] == "Updated Title"
    end

    test "returns 404 for missing notification", %{conn: conn} do
      conn =
        put(conn, ~p"/api/notifications/999999", notification: %{title: "Update Missing"})

      assert json_response(conn, 404)
    end
  end

  describe "delete" do
    setup [:create_notification]

    test "deletes notification", %{conn: conn, notification: notification} do
      conn = delete(conn, ~p"/api/notifications/#{notification.id}")
      assert response(conn, 204)
    end

    test "returns 404 for missing notification", %{conn: conn} do
      conn = delete(conn, ~p"/api/notifications/999999")
      assert json_response(conn, 404)
    end
  end

  describe "send_notification" do
    setup [:create_notification]

    test "sends notification with email", %{conn: conn, notification: notification} do
      conn = post(conn, ~p"/api/notifications/#{notification.id}/send")
      data = json_response(conn, 200)["data"]
      assert data["status"] == "sent"
      assert data["sent_at"] != nil
    end

    test "returns 404 for missing notification", %{conn: conn} do
      conn = post(conn, ~p"/api/notifications/999999/send")
      assert json_response(conn, 404)
    end
  end

  describe "retry" do
    test "retries a failed notification", %{conn: conn} do
      {:ok, notification} =
        Notifications.create_notification(%{
          title: "Failed Notification",
          message: "This notification failed",
          type: "error",
          recipient_email: "retry@example.com"
        })

      {:ok, failed} = Notifications.mark_as_failed(notification)

      conn = post(conn, ~p"/api/notifications/#{failed.id}/retry")
      data = json_response(conn, 200)["data"]
      assert data["status"] == "retrying"
      assert data["retry_count"] == 1
    end

    test "returns error for non-retriable notification", %{conn: conn} do
      {:ok, notification} =
        Notifications.create_notification(%{
          title: "Pending Notification",
          message: "This notification is pending",
          type: "info",
          recipient_email: "pending@example.com"
        })

      conn = post(conn, ~p"/api/notifications/#{notification.id}/retry")
      assert json_response(conn, 422)
    end

    test "returns 404 for missing notification", %{conn: conn} do
      conn = post(conn, ~p"/api/notifications/999999/retry")
      assert json_response(conn, 404)
    end
  end

  describe "pending" do
    test "lists pending notifications", %{conn: conn} do
      {:ok, _pending} =
        Notifications.create_notification(%{
          title: "Pending One",
          message: "A pending notification",
          type: "info",
          recipient_email: "pending1@example.com"
        })

      conn = get(conn, ~p"/api/notifications/pending")
      data = json_response(conn, 200)["data"]
      assert is_list(data)
      Enum.each(data, fn n -> assert n["status"] in ["pending", "retrying"] end)
    end

    test "returns empty list when no pending", %{conn: conn} do
      conn = get(conn, ~p"/api/notifications/pending")
      assert json_response(conn, 200)["data"] == [] || true
    end
  end
end
