defmodule Samgita.Notifications do
  @moduledoc """
  Context module for managing notifications.

  Provides CRUD operations and business logic for notifications,
  including retry logic and timeout handling.
  """

  import Ecto.Query, warn: false
  alias Samgita.Repo
  alias Samgita.Domain.Notification

  @doc """
  Returns the list of notifications.

  Orders by priority (descending) and inserted_at (descending).

  ## Options

    * `:status` - Filter by status (e.g., "pending", "sent", "failed")
    * `:type` - Filter by type (e.g., "error", "warning")
    * `:project_id` - Filter by project ID
    * `:limit` - Limit number of results

  ## Examples

      iex> list_notifications()
      [%Notification{}, ...]

      iex> list_notifications(status: "pending", limit: 10)
      [%Notification{}, ...]

  """
  def list_notifications(opts \\ []) do
    Notification
    |> apply_filters(opts)
    |> order_by([n], desc: n.priority, desc: n.inserted_at)
    |> maybe_limit(opts[:limit])
    |> Repo.all()
  end

  @doc """
  Gets a single notification.

  Returns `{:ok, notification}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_notification(123)
      {:ok, %Notification{}}

      iex> get_notification(456)
      {:error, :not_found}

  """
  def get_notification(id) do
    case Repo.get(Notification, id) do
      nil -> {:error, :not_found}
      notification -> {:ok, notification}
    end
  end

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%{title: "Alert", message: "Something happened"})
      {:ok, %Notification{}}

      iex> create_notification(%{title: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a notification.

  ## Examples

      iex> update_notification(notification, %{title: "Updated"})
      {:ok, %Notification{}}

      iex> update_notification(notification, %{type: "invalid"})
      {:error, %Ecto.Changeset{}}

  """
  def update_notification(%Notification{} = notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a notification.

  ## Examples

      iex> delete_notification(notification)
      {:ok, %Notification{}}

      iex> delete_notification(notification)
      {:error, %Ecto.Changeset{}}

  """
  def delete_notification(%Notification{} = notification) do
    Repo.delete(notification)
  end

  @doc """
  Marks a notification as sent.

  Updates the status to "sent" and sets sent_at timestamp.

  ## Examples

      iex> mark_as_sent(notification)
      {:ok, %Notification{status: "sent"}}

  """
  def mark_as_sent(%Notification{} = notification) do
    notification
    |> Notification.status_changeset(%{
      status: "sent",
      sent_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Marks a notification as failed.

  Updates the status to "failed".

  ## Examples

      iex> mark_as_failed(notification)
      {:ok, %Notification{status: "failed"}}

  """
  def mark_as_failed(%Notification{} = notification) do
    notification
    |> Notification.status_changeset(%{status: "failed"})
    |> Repo.update()
  end

  @doc """
  Retries a failed notification.

  Validates that:
  - Notification is in a retriable state (failed or retrying)
  - Has not exceeded max retries

  Returns `{:error, :not_retriable}` if conditions not met.

  ## Examples

      iex> retry_notification(notification)
      {:ok, %Notification{status: "retrying", retry_count: 1}}

      iex> retry_notification(sent_notification)
      {:error, :not_retriable}

  """
  def retry_notification(%Notification{} = notification) do
    cond do
      notification.status not in ["failed", "retrying"] ->
        {:error, :not_retriable}

      notification.retry_count >= notification.max_retries ->
        {:error, :max_retries_exceeded}

      true ->
        notification
        |> Notification.status_changeset(%{
          status: "retrying",
          retry_count: notification.retry_count + 1
        })
        |> Repo.update()
    end
  end

  @doc """
  Sends a notification with timeout and retry support.

  This is a demonstration of how to implement timeout/retry logic.
  In production, this would typically be handled by an Oban job.

  ## Examples

      iex> send_notification(notification)
      {:ok, %Notification{status: "sent"}}

      iex> send_notification(notification)
      {:error, :timeout}

  """
  def send_notification(%Notification{} = notification) do
    timeout = notification.timeout_seconds * 1000

    task =
      Task.async(fn ->
        deliver_notification(notification)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, _result}} ->
        mark_as_sent(notification)

      {:ok, {:error, reason}} ->
        mark_as_failed(notification)
        {:error, reason}

      nil ->
        mark_as_failed(notification)
        {:error, :timeout}
    end
  end

  @doc """
  Sends a notification with automatic retry on failure.

  Attempts to send up to `max_retries` times.

  ## Examples

      iex> send_with_retry(notification)
      {:ok, %Notification{}}

      iex> send_with_retry(failing_notification)
      {:error, :all_retries_failed}

  """
  def send_with_retry(%Notification{} = notification) do
    case send_notification(notification) do
      {:ok, sent_notification} ->
        {:ok, sent_notification}

      {:error, _reason} ->
        if notification.retry_count < notification.max_retries do
          {:ok, updated} = retry_notification(notification)
          # In production, you'd schedule this via Oban instead of recursion
          Process.sleep(1000 * (notification.retry_count + 1))
          send_with_retry(updated)
        else
          {:error, :all_retries_failed}
        end
    end
  end

  @doc """
  Gets pending notifications ready to be sent.

  Returns notifications with status "pending" or "retrying",
  ordered by priority.

  ## Examples

      iex> get_pending_notifications()
      [%Notification{status: "pending"}, ...]

  """
  def get_pending_notifications do
    Notification
    |> where([n], n.status in ["pending", "retrying"])
    |> order_by([n], desc: n.priority, asc: n.inserted_at)
    |> Repo.all()
  end

  # Private helper functions

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        where(query, [n], n.status == ^status)

      {:type, type}, query ->
        where(query, [n], n.type == ^type)

      {:project_id, project_id}, query ->
        where(query, [n], n.project_id == ^project_id)

      _other, query ->
        query
    end)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  # Simulated notification delivery
  # In production, this would call external services (email provider, webhooks, etc.)
  defp deliver_notification(%Notification{} = notification) do
    cond do
      notification.recipient_email ->
        deliver_email(notification)

      notification.webhook_url ->
        deliver_webhook(notification)

      true ->
        {:error, :no_delivery_method}
    end
  end

  defp deliver_email(%Notification{recipient_email: email} = notification) do
    # Simulate email delivery
    # In production: use a library like Swoosh or Bamboo
    IO.puts("Sending email to #{email}: #{notification.title}")
    {:ok, :email_sent}
  end

  defp deliver_webhook(%Notification{webhook_url: url} = notification) do
    # Simulate webhook delivery
    # In production: use HTTPoison or Req
    payload = %{
      title: notification.title,
      message: notification.message,
      type: notification.type,
      priority: notification.priority,
      metadata: notification.metadata
    }

    IO.puts("Sending webhook to #{url}: #{inspect(payload)}")
    {:ok, :webhook_sent}
  end
end
