defmodule SamgitaWeb.FeatureJSON do
  @moduledoc """
  JSON view for rendering Feature resources.
  Follows the project's standard response format with data wrapper.
  """

  alias Samgita.Domain.Feature

  @doc """
  Renders a list of features.
  """
  def index(%{features: features}) do
    %{data: for(feature <- features, do: data(feature))}
  end

  @doc """
  Renders a single feature.
  """
  def show(%{feature: feature}) do
    %{data: data(feature)}
  end

  defp data(%Feature{} = feature) do
    %{
      id: feature.id,
      name: feature.name,
      description: feature.description,
      status: feature.status,
      priority: feature.priority,
      owner_email: feature.owner_email,
      documentation_url: feature.documentation_url,
      max_retries: feature.max_retries,
      timeout_seconds: feature.timeout_seconds,
      tags: feature.tags,
      metadata: feature.metadata,
      enabled: feature.enabled,
      inserted_at: feature.inserted_at,
      updated_at: feature.updated_at
    }
  end
end
