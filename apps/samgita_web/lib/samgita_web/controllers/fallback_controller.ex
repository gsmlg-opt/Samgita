defmodule SamgitaWeb.FallbackController do
  use SamgitaWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :not_running}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Project is not running")
  end

  def call(conn, {:error, :not_paused}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Project is not paused")
  end

  def call(conn, {:error, :not_retriable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Task is not in a retriable state")
  end

  def call(conn, {:error, :already_active}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Project is already active")
  end

  def call(conn, {:error, :not_active}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Project is not active")
  end

  def call(conn, {:error, :prd_not_in_project}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "PRD does not belong to this project")
  end

  def call(conn, {:error, :no_active_prd}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ErrorJSON)
    |> render(:"422", message: "Project has no active PRD")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end
end
