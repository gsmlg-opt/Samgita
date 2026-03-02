defmodule SamgitaWeb.PrdJSON do
  alias Samgita.Domain.Prd

  def index(%{prds: prds}) do
    %{data: for(prd <- prds, do: data(prd))}
  end

  def show(%{prd: prd}) do
    %{data: data(prd)}
  end

  defp data(%Prd{} = prd) do
    %{
      id: prd.id,
      project_id: prd.project_id,
      title: prd.title,
      content: prd.content,
      status: prd.status,
      version: prd.version,
      metadata: prd.metadata,
      inserted_at: prd.inserted_at,
      updated_at: prd.updated_at
    }
  end
end
