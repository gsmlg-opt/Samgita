defmodule SamgitaWeb.NotificationJSON do
  alias Samgita.Domain.Notification

  def index(%{notifications: notifications}) do
    %{data: for(notification <- notifications, do: data(notification))}
  end

  def show(%{notification: notification}) do
    %{data: data(notification)}
  end

  defp data(%Notification{} = notification) do
    %{
      id: notification.id,
      title: notification.title,
      message: notification.message,
      type: notification.type,
      priority: notification.priority,
      recipient_email: notification.recipient_email,
      webhook_url: notification.webhook_url,
      status: notification.status,
      retry_count: notification.retry_count,
      max_retries: notification.max_retries,
      timeout_seconds: notification.timeout_seconds,
      metadata: notification.metadata,
      project_id: notification.project_id,
      sent_at: notification.sent_at,
      inserted_at: notification.inserted_at,
      updated_at: notification.updated_at
    }
  end
end
