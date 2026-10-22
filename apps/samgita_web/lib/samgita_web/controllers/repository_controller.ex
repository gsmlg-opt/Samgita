defmodule SamgitaWeb.RepositoryController do
  use SamgitaWeb, :controller

  alias Samgita.Repositories
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}),
    do: API.result(conn, Repositories.list(API.principal(conn), project_id, conn.query_params))

  def create(conn, %{"project_id" => project_id}),
    do:
      API.result(
        conn,
        Repositories.associate(API.principal(conn), project_id, API.attrs(conn)),
        :created
      )
end
