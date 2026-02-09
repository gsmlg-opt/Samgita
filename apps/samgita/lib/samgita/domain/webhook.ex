defmodule Samgita.Domain.Webhook do
  @moduledoc "Ecto schema for webhook subscriptions with URL and event validation."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @events [
    "project.phase_changed",
    "task.completed",
    "task.failed",
    "agent.spawned",
    "agent.crashed",
    "project.completed"
  ]

  schema "webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :events, :secret, :active])
    |> validate_required([:url, :events])
    |> validate_url(:url)
    |> validate_events(:events)
  end

  def valid_events, do: @events

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: scheme} when scheme in ["http", "https"] -> []
        _ -> [{field, "must be a valid HTTP/HTTPS URL"}]
      end
    end)
  end

  defp validate_events(changeset, field) do
    validate_change(changeset, field, fn _, events ->
      invalid = Enum.reject(events, &(&1 in @events))

      if invalid == [] do
        []
      else
        [{field, "contains invalid events: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end
end
