defmodule SamgitaWeb.ArtifactJSON do
  alias Samgita.Domain.Artifact

  def index(%{artifacts: artifacts}) do
    %{data: for(artifact <- artifacts, do: data(artifact))}
  end

  def show(%{artifact: artifact}) do
    %{data: data(artifact)}
  end

  defp data(%Artifact{} = artifact) do
    %{
      id: artifact.id,
      type: artifact.type,
      path: artifact.path,
      content: artifact.content,
      content_hash: artifact.content_hash,
      metadata: artifact.metadata,
      project_id: artifact.project_id,
      task_id: artifact.task_id,
      inserted_at: artifact.inserted_at,
      updated_at: artifact.updated_at
    }
  end
end
