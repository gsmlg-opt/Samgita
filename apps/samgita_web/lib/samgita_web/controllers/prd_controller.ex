defmodule SamgitaWeb.PrdController do
  use SamgitaWeb, :controller

  alias Samgita.Domain.Prd
  alias Samgita.Prds

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    prds = Prds.list_prds(project_id)
    render(conn, :index, prds: prds)
  end

  def show(conn, %{"id" => id}) do
    with {:ok, prd} <- Prds.get_prd(id) do
      render(conn, :show, prd: prd)
    end
  end

  def create(conn, %{"project_id" => project_id, "prd" => prd_params}) do
    attrs = Map.put(prd_params, "project_id", project_id)

    with {:ok, %Prd{} = prd} <- Prds.create_prd(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, prd: prd)
    end
  end

  def update(conn, %{"id" => id, "prd" => prd_params}) do
    with {:ok, prd} <- Prds.get_prd(id),
         {:ok, %Prd{} = updated} <- Prds.update_prd(prd, prd_params) do
      render(conn, :show, prd: updated)
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, prd} <- Prds.get_prd(id),
         {:ok, _} <- Prds.delete_prd(prd) do
      send_resp(conn, :no_content, "")
    end
  end
end
