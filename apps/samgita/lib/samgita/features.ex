defmodule Samgita.Features do
  @moduledoc """
  Context module for managing Feature resources.
  Provides CRUD operations and business logic for features.
  """

  import Ecto.Query, warn: false
  alias Samgita.Repo
  alias Samgita.Domain.Feature

  @doc """
  Returns the list of features with optional filtering.

  ## Examples

      iex> list_features()
      [%Feature{}, ...]

      iex> list_features(%{"status" => "active"})
      [%Feature{status: :active}, ...]

  """
  def list_features(filters \\ %{}) do
    Feature
    |> apply_filters(filters)
    |> order_by([f], desc: f.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a single feature.

  Returns `{:ok, feature}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_feature("valid-id")
      {:ok, %Feature{}}

      iex> get_feature("invalid-id")
      {:error, :not_found}

  """
  def get_feature(id) do
    case Repo.get(Feature, id) do
      nil -> {:error, :not_found}
      feature -> {:ok, feature}
    end
  end

  @doc """
  Gets a single feature by name.

  Returns `{:ok, feature}` if found, `{:error, :not_found}` otherwise.
  """
  def get_feature_by_name(name) do
    case Repo.get_by(Feature, name: name) do
      nil -> {:error, :not_found}
      feature -> {:ok, feature}
    end
  end

  @doc """
  Creates a feature.

  ## Examples

      iex> create_feature(%{name: "API Gateway", description: "Central API gateway"})
      {:ok, %Feature{}}

      iex> create_feature(%{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def create_feature(attrs \\ %{}) do
    %Feature{}
    |> Feature.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a feature.

  ## Examples

      iex> update_feature(feature, %{name: "Updated name"})
      {:ok, %Feature{}}

      iex> update_feature(feature, %{name: ""})
      {:error, %Ecto.Changeset{}}

  """
  def update_feature(%Feature{} = feature, attrs) do
    feature
    |> Feature.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a feature.

  ## Examples

      iex> delete_feature(feature)
      {:ok, %Feature{}}

      iex> delete_feature(feature)
      {:error, %Ecto.Changeset{}}

  """
  def delete_feature(%Feature{} = feature) do
    Repo.delete(feature)
  end

  @doc """
  Enables a feature by setting enabled to true.

  ## Examples

      iex> enable_feature(feature)
      {:ok, %Feature{enabled: true}}

  """
  def enable_feature(%Feature{} = feature) do
    update_feature(feature, %{enabled: true})
  end

  @doc """
  Disables a feature by setting enabled to false.

  ## Examples

      iex> disable_feature(feature)
      {:ok, %Feature{enabled: false}}

  """
  def disable_feature(%Feature{} = feature) do
    update_feature(feature, %{enabled: false})
  end

  @doc """
  Archives a feature by setting status to archived.

  ## Examples

      iex> archive_feature(feature)
      {:ok, %Feature{status: :archived}}

  """
  def archive_feature(%Feature{} = feature) do
    update_feature(feature, %{status: :archived, enabled: false})
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking feature changes.

  ## Examples

      iex> change_feature(feature)
      %Ecto.Changeset{data: %Feature{}}

  """
  def change_feature(%Feature{} = feature, attrs \\ %{}) do
    Feature.update_changeset(feature, attrs)
  end

  # Private functions

  defp apply_filters(query, filters) when filters == %{}, do: query

  defp apply_filters(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, acc ->
      apply_filter(acc, key, value)
    end)
  end

  defp apply_filter(query, "status", value)
       when value in ["draft", "active", "deprecated", "archived"] do
    where(query, [f], f.status == ^String.to_existing_atom(value))
  end

  defp apply_filter(query, "priority", value)
       when value in ["low", "medium", "high", "critical"] do
    where(query, [f], f.priority == ^String.to_existing_atom(value))
  end

  defp apply_filter(query, "enabled", value) when value in ["true", "false"] do
    enabled = value == "true"
    where(query, [f], f.enabled == ^enabled)
  end

  defp apply_filter(query, "tag", value) do
    where(query, [f], ^value in f.tags)
  end

  defp apply_filter(query, _key, _value), do: query
end
