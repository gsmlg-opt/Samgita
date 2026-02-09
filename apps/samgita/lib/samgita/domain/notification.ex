defmodule Samgita.Domain.Notification do
  @moduledoc """
  Schema for system notifications.

  Demonstrates comprehensive validation patterns:
  - Required field validation
  - Format validation (email, URLs)
  - Enum validation
  - Range/length constraints
  - Custom business logic validation
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          message: String.t(),
          type: String.t(),
          priority: integer(),
          recipient_email: String.t() | nil,
          webhook_url: String.t() | nil,
          status: String.t(),
          retry_count: integer(),
          max_retries: integer(),
          timeout_seconds: integer(),
          metadata: map(),
          project_id: integer() | nil,
          sent_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @allowed_types ~w(info warning error success)
  @allowed_statuses ~w(pending sent failed retrying)
  @priority_range 1..5

  schema "notifications" do
    field :title, :string
    field :message, :string
    field :type, :string, default: "info"
    field :priority, :integer, default: 3
    field :recipient_email, :string
    field :webhook_url, :string
    field :status, :string, default: "pending"
    field :retry_count, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :timeout_seconds, :integer, default: 30
    field :metadata, :map, default: %{}
    field :sent_at, :utc_datetime

    belongs_to :project, Samgita.Domain.Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a notification.

  Required fields: title, message
  Optional fields: type, priority, recipient_email, webhook_url, project_id, metadata, max_retries, timeout_seconds

  Validations:
  - title: required, max 255 chars
  - message: required, max 5000 chars
  - type: must be one of: info, warning, error, success
  - priority: must be between 1-5
  - recipient_email: valid email format (if provided)
  - webhook_url: valid HTTP/HTTPS URL (if provided)
  - At least one delivery method (email or webhook) required
  - max_retries: between 0-10
  - timeout_seconds: between 1-300
  """
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :title,
      :message,
      :type,
      :priority,
      :recipient_email,
      :webhook_url,
      :project_id,
      :metadata,
      :max_retries,
      :timeout_seconds
    ])
    |> validate_required([:title, :message])
    |> validate_length(:title, max: 255)
    |> validate_length(:message, max: 5000)
    |> validate_inclusion(:type, @allowed_types,
      message: "must be one of: #{Enum.join(@allowed_types, ", ")}"
    )
    |> validate_number(:priority,
      greater_than_or_equal_to: Enum.min(@priority_range),
      less_than_or_equal_to: Enum.max(@priority_range),
      message: "must be between #{Enum.min(@priority_range)} and #{Enum.max(@priority_range)}"
    )
    |> validate_number(:max_retries,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 10
    )
    |> validate_number(:timeout_seconds,
      greater_than_or_equal_to: 1,
      less_than_or_equal_to: 300
    )
    |> validate_email()
    |> validate_webhook_url()
    |> validate_delivery_method()
    |> foreign_key_constraint(:project_id)
  end

  @doc """
  Changeset for updating notification status.

  Used internally when sending notifications or handling retries.
  """
  def status_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:status, :retry_count, :sent_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @allowed_statuses)
    |> validate_status_transition(notification)
  end

  # Private validation functions

  defp validate_email(changeset) do
    case get_field(changeset, :recipient_email) do
      nil ->
        changeset

      _email ->
        changeset
        |> validate_format(:recipient_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
          message: "must be a valid email address"
        )
    end
  end

  defp validate_webhook_url(changeset) do
    case get_field(changeset, :webhook_url) do
      nil ->
        changeset

      _url ->
        changeset
        |> validate_format(:webhook_url, ~r/^https?:\/\/.+/,
          message: "must be a valid HTTP or HTTPS URL"
        )
        |> validate_change(:webhook_url, fn :webhook_url, url ->
          case URI.parse(url) do
            %URI{scheme: scheme, host: host}
            when scheme in ["http", "https"] and not is_nil(host) ->
              []

            _ ->
              [webhook_url: "must be a valid HTTP or HTTPS URL with a valid host"]
          end
        end)
    end
  end

  defp validate_delivery_method(changeset) do
    email = get_field(changeset, :recipient_email)
    webhook = get_field(changeset, :webhook_url)

    if is_nil(email) and is_nil(webhook) do
      changeset
      |> add_error(
        :recipient_email,
        "at least one delivery method (email or webhook) is required"
      )
      |> add_error(:webhook_url, "at least one delivery method (email or webhook) is required")
    else
      changeset
    end
  end

  defp validate_status_transition(changeset, original_notification) do
    old_status = original_notification.status
    new_status = get_field(changeset, :status)

    valid_transitions = %{
      "pending" => ["sent", "failed", "retrying"],
      "retrying" => ["sent", "failed"],
      "failed" => ["retrying", "pending"],
      "sent" => []
    }

    allowed = Map.get(valid_transitions, old_status, [])

    if new_status in allowed or new_status == old_status do
      changeset
    else
      add_error(
        changeset,
        :status,
        "cannot transition from #{old_status} to #{new_status}. Allowed: #{Enum.join(allowed, ", ")}"
      )
    end
  end

  @doc """
  Returns list of allowed notification types.
  """
  def allowed_types, do: @allowed_types

  @doc """
  Returns list of allowed notification statuses.
  """
  def allowed_statuses, do: @allowed_statuses
end
