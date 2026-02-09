defmodule SamgitaWeb.NotificationController do
  @moduledoc """
  REST API controller for notifications.

  Demonstrates comprehensive error handling patterns:
  - Validation errors (422) via changeset
  - Not found errors (404)
  - State validation errors (422) for retries
  - Fallback controller for consistent error responses
  """
  use SamgitaWeb, :controller

  alias Samgita.Domain.Notification
  alias Samgita.Notifications

  action_fallback SamgitaWeb.FallbackController

  @doc """
  GET /api/notifications

  Lists all notifications with optional filters.

  ## Query Parameters

    * `status` - Filter by status (pending, sent, failed, retrying)
    * `type` - Filter by type (info, warning, error, success)
    * `project_id` - Filter by project ID
    * `limit` - Limit number of results

  ## Examples

      GET /api/notifications
      GET /api/notifications?status=pending&limit=10
      GET /api/notifications?type=error&project_id=1

  ## Response

      200 OK
      {
        "data": [
          {
            "id": 1,
            "title": "Notification title",
            "message": "Notification message",
            ...
          }
        ]
      }
  """
  def index(conn, params) do
    opts = build_filter_opts(params)
    notifications = Notifications.list_notifications(opts)
    render(conn, :index, notifications: notifications)
  end

  @doc """
  GET /api/notifications/:id

  Gets a single notification by ID.

  ## Response

      200 OK
      {
        "data": {
          "id": 1,
          "title": "Notification title",
          ...
        }
      }

      404 Not Found
      {
        "errors": {
          "detail": "Not Found"
        }
      }
  """
  def show(conn, %{"id" => id}) do
    with {:ok, notification} <- Notifications.get_notification(id) do
      render(conn, :show, notification: notification)
    end
  end

  @doc """
  POST /api/notifications

  Creates a new notification.

  ## Request Body

      {
        "notification": {
          "title": "Alert",
          "message": "Something happened",
          "type": "warning",
          "priority": 4,
          "recipient_email": "user@example.com",
          "webhook_url": "https://example.com/webhook",
          "project_id": 1,
          "metadata": {"key": "value"},
          "max_retries": 3,
          "timeout_seconds": 30
        }
      }

  ## Response

      201 Created
      {
        "data": {
          "id": 1,
          "title": "Alert",
          ...
        }
      }

      422 Unprocessable Entity
      {
        "errors": {
          "title": ["can't be blank"],
          "type": ["must be one of: info, warning, error, success"]
        }
      }
  """
  def create(conn, %{"notification" => notification_params}) do
    with {:ok, %Notification{} = notification} <-
           Notifications.create_notification(notification_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/notifications/#{notification.id}")
      |> render(:show, notification: notification)
    end
  end

  @doc """
  PUT /api/notifications/:id

  Updates a notification.

  ## Request Body

      {
        "notification": {
          "title": "Updated title",
          "priority": 5
        }
      }

  ## Response

      200 OK
      {
        "data": {
          "id": 1,
          "title": "Updated title",
          ...
        }
      }

      404 Not Found
      422 Unprocessable Entity (validation errors)
  """
  def update(conn, %{"id" => id, "notification" => notification_params}) do
    with {:ok, notification} <- Notifications.get_notification(id),
         {:ok, %Notification{} = updated} <-
           Notifications.update_notification(notification, notification_params) do
      render(conn, :show, notification: updated)
    end
  end

  @doc """
  DELETE /api/notifications/:id

  Deletes a notification.

  ## Response

      204 No Content

      404 Not Found
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, notification} <- Notifications.get_notification(id),
         {:ok, _notification} <- Notifications.delete_notification(notification) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  POST /api/notifications/:id/send

  Sends a notification immediately with timeout support.

  ## Response

      200 OK
      {
        "data": {
          "id": 1,
          "status": "sent",
          ...
        }
      }

      404 Not Found
      422 Unprocessable Entity
      {
        "errors": {
          "detail": "Failed to send notification: timeout"
        }
      }
  """
  def send_notification(conn, %{"id" => id}) do
    with {:ok, notification} <- Notifications.get_notification(id),
         {:ok, sent_notification} <- Notifications.send_notification(notification) do
      render(conn, :show, notification: sent_notification)
    else
      {:error, :timeout} ->
        {:error, :send_timeout}

      {:error, reason} when is_atom(reason) ->
        {:error, reason}

      error ->
        error
    end
  end

  @doc """
  POST /api/notifications/:id/retry

  Retries a failed notification.

  Validates that:
  - Notification exists
  - Notification is in a retriable state (failed or retrying)
  - Has not exceeded max retries

  ## Response

      200 OK
      {
        "data": {
          "id": 1,
          "status": "retrying",
          "retry_count": 1,
          ...
        }
      }

      404 Not Found
      422 Unprocessable Entity
      {
        "errors": {
          "detail": "Notification is not in a retriable state"
        }
      }
  """
  def retry(conn, %{"id" => id}) do
    with {:ok, notification} <- Notifications.get_notification(id),
         {:ok, %Notification{} = retried} <- Notifications.retry_notification(notification) do
      render(conn, :show, notification: retried)
    end
  end

  @doc """
  GET /api/notifications/pending

  Gets all pending notifications ready to be sent.

  ## Response

      200 OK
      {
        "data": [...]
      }
  """
  def pending(conn, _params) do
    notifications = Notifications.get_pending_notifications()
    render(conn, :index, notifications: notifications)
  end

  # Private helper functions

  defp build_filter_opts(params) do
    []
    |> maybe_add_opt(:status, params["status"])
    |> maybe_add_opt(:type, params["type"])
    |> maybe_add_opt(:project_id, parse_integer(params["project_id"]))
    |> maybe_add_opt(:limit, parse_integer(params["limit"]))
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_integer(nil), do: nil

  defp parse_integer(string) when is_binary(string) do
    case Integer.parse(string) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_integer(int) when is_integer(int), do: int
end
