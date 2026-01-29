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

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SamgitaWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end
end
