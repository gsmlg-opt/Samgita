defmodule SamgitaWeb.FeatureController do
  @moduledoc """
  Controller for managing Feature resources via REST API.

  Demonstrates comprehensive REST endpoint implementation with:
  - Standard CRUD operations (index, show, create, update, delete)
  - Custom actions (enable, disable, archive)
  - Proper error handling via FallbackController
  - Input validation through domain changesets
  - Filtering support for list operations
  - HTTP status codes and headers following REST conventions
  """
  use SamgitaWeb, :controller

  alias Samgita.Features
  alias Samgita.Domain.Feature

  action_fallback SamgitaWeb.FallbackController

  @doc """
  Lists all features with optional filtering.

  Query parameters:
  - status: Filter by status (draft, active, deprecated, archived)
  - priority: Filter by priority (low, medium, high, critical)
  - enabled: Filter by enabled flag (true, false)
  - tag: Filter by tag (returns features containing this tag)

  ## Examples

      GET /api/features
      GET /api/features?status=active
      GET /api/features?priority=high&enabled=true
      GET /api/features?tag=experimental

  """
  def index(conn, params) do
    features = Features.list_features(params)
    render(conn, :index, features: features)
  end

  @doc """
  Shows a single feature by ID.

  Returns 404 if feature not found.
  """
  def show(conn, %{"id" => id}) do
    with {:ok, feature} <- Features.get_feature(id) do
      render(conn, :show, feature: feature)
    end
  end

  @doc """
  Creates a new feature.

  Returns 201 with Location header on success.
  Returns 422 with validation errors on failure.

  ## Request body example

      {
        "feature": {
          "name": "API Rate Limiting",
          "description": "Implement rate limiting for API endpoints",
          "status": "draft",
          "priority": "high",
          "owner_email": "dev@example.com",
          "documentation_url": "https://docs.example.com/rate-limiting",
          "max_retries": 3,
          "timeout_seconds": 30,
          "tags": ["api", "security"],
          "metadata": {"category": "infrastructure"},
          "enabled": false
        }
      }

  """
  def create(conn, %{"feature" => feature_params}) do
    with {:ok, %Feature{} = feature} <- Features.create_feature(feature_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/features/#{feature.id}")
      |> render(:show, feature: feature)
    end
  end

  @doc """
  Updates an existing feature.

  Returns 200 with updated feature on success.
  Returns 404 if feature not found.
  Returns 422 with validation errors on failure.
  """
  def update(conn, %{"id" => id, "feature" => feature_params}) do
    with {:ok, feature} <- Features.get_feature(id),
         {:ok, %Feature{} = updated_feature} <- Features.update_feature(feature, feature_params) do
      render(conn, :show, feature: updated_feature)
    end
  end

  @doc """
  Deletes a feature.

  Returns 204 No Content on success.
  Returns 404 if feature not found.
  """
  def delete(conn, %{"id" => id}) do
    with {:ok, feature} <- Features.get_feature(id),
         {:ok, %Feature{}} <- Features.delete_feature(feature) do
      send_resp(conn, :no_content, "")
    end
  end

  @doc """
  Enables a feature (sets enabled = true).

  Custom action endpoint: POST /api/features/:id/enable

  Returns 200 with updated feature on success.
  Returns 404 if feature not found.
  Returns 422 if validation fails (e.g., enabling a non-active feature).
  """
  def enable(conn, %{"id" => id}) do
    with {:ok, feature} <- Features.get_feature(id),
         {:ok, %Feature{} = enabled_feature} <- Features.enable_feature(feature) do
      render(conn, :show, feature: enabled_feature)
    end
  end

  @doc """
  Disables a feature (sets enabled = false).

  Custom action endpoint: POST /api/features/:id/disable

  Returns 200 with updated feature on success.
  Returns 404 if feature not found.
  """
  def disable(conn, %{"id" => id}) do
    with {:ok, feature} <- Features.get_feature(id),
         {:ok, %Feature{} = disabled_feature} <- Features.disable_feature(feature) do
      render(conn, :show, feature: disabled_feature)
    end
  end

  @doc """
  Archives a feature (sets status = archived, enabled = false).

  Custom action endpoint: POST /api/features/:id/archive

  Returns 200 with updated feature on success.
  Returns 404 if feature not found.

  Note: Once archived, a feature cannot transition to other statuses.
  """
  def archive(conn, %{"id" => id}) do
    with {:ok, feature} <- Features.get_feature(id),
         {:ok, %Feature{} = archived_feature} <- Features.archive_feature(feature) do
      render(conn, :show, feature: archived_feature)
    end
  end
end
