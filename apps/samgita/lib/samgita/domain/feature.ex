defmodule Samgita.Domain.Feature do
  @moduledoc """
  Feature schema representing a system feature or capability.
  Demonstrates comprehensive validation patterns including:
  - Required field validation
  - Format validation (email, URL)
  - Enum validation
  - Number range validation
  - Length constraints
  - Custom business logic validation
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          status: :draft | :active | :deprecated | :archived,
          priority: :low | :medium | :high | :critical,
          owner_email: String.t() | nil,
          documentation_url: String.t() | nil,
          max_retries: integer(),
          timeout_seconds: integer(),
          tags: [String.t()],
          metadata: map(),
          enabled: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "features" do
    field :name, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:draft, :active, :deprecated, :archived], default: :draft
    field :priority, Ecto.Enum, values: [:low, :medium, :high, :critical], default: :medium
    field :owner_email, :string
    field :documentation_url, :string
    field :max_retries, :integer, default: 3
    field :timeout_seconds, :integer, default: 30
    field :tags, {:array, :string}, default: []
    field :metadata, :map, default: %{}
    field :enabled, :boolean, default: false

    timestamps(type: :naive_datetime_usec)
  end

  @doc """
  Changeset for creating a new feature.
  """
  def create_changeset(feature, attrs) do
    feature
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :priority,
      :owner_email,
      :documentation_url,
      :max_retries,
      :timeout_seconds,
      :tags,
      :metadata,
      :enabled
    ])
    |> validate_required([:name, :description])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_length(:description, min: 10, max: 1000)
    |> validate_inclusion(:status, [:draft, :active, :deprecated, :archived])
    |> validate_inclusion(:priority, [:low, :medium, :high, :critical])
    |> validate_email_format()
    |> validate_url_format()
    |> validate_number(:max_retries, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:timeout_seconds, greater_than_or_equal_to: 1, less_than_or_equal_to: 600)
    |> validate_tags()
    |> validate_enabled_status()
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for updating an existing feature.
  """
  def update_changeset(feature, attrs) do
    feature
    |> cast(attrs, [
      :name,
      :description,
      :status,
      :priority,
      :owner_email,
      :documentation_url,
      :max_retries,
      :timeout_seconds,
      :tags,
      :metadata,
      :enabled
    ])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_length(:description, min: 10, max: 1000)
    |> validate_inclusion(:status, [:draft, :active, :deprecated, :archived])
    |> validate_inclusion(:priority, [:low, :medium, :high, :critical])
    |> validate_email_format()
    |> validate_url_format()
    |> validate_number(:max_retries, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:timeout_seconds, greater_than_or_equal_to: 1, less_than_or_equal_to: 600)
    |> validate_tags()
    |> validate_status_transition(feature)
    |> validate_enabled_status()
    |> unique_constraint(:name)
  end

  # Private validation functions

  defp validate_email_format(changeset) do
    case get_field(changeset, :owner_email) do
      nil ->
        changeset

      email ->
        if String.match?(email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
          changeset
        else
          add_error(changeset, :owner_email, "must be a valid email address")
        end
    end
  end

  defp validate_url_format(changeset) do
    case get_field(changeset, :documentation_url) do
      nil ->
        changeset

      url ->
        case URI.parse(url) do
          %URI{scheme: scheme, host: host}
          when scheme in ["http", "https"] and not is_nil(host) ->
            changeset

          _ ->
            add_error(changeset, :documentation_url, "must be a valid HTTP(S) URL")
        end
    end
  end

  defp validate_tags(changeset) do
    case get_field(changeset, :tags) do
      nil ->
        changeset

      tags when is_list(tags) ->
        if Enum.all?(tags, &(is_binary(&1) && String.length(&1) > 0 && String.length(&1) <= 50)) do
          changeset
        else
          add_error(changeset, :tags, "must be a list of non-empty strings (max 50 chars each)")
        end

      _ ->
        add_error(changeset, :tags, "must be a list of strings")
    end
  end

  defp validate_status_transition(changeset, original_feature) do
    old_status = original_feature.status
    new_status = get_field(changeset, :status)

    # Validation rule: Cannot transition from archived to any other status
    if old_status == :archived && new_status != :archived do
      add_error(changeset, :status, "cannot transition from archived status")
    else
      changeset
    end
  end

  defp validate_enabled_status(changeset) do
    status = get_field(changeset, :status)
    enabled = get_field(changeset, :enabled)

    # Business rule: Active features must be enabled
    if status == :active && enabled == false do
      add_error(changeset, :enabled, "must be true for active features")
    else
      changeset
    end
  end
end
