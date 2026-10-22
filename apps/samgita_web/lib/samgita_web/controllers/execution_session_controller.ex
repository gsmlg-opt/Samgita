defmodule SamgitaWeb.ExecutionSessionController do
  use SamgitaWeb, :controller

  alias Samgita.Agents
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}),
    do: API.result(conn, Agents.list_sessions(API.principal(conn), project_id, conn.query_params))

  def create(conn, %{"project_id" => project_id}),
    do:
      API.result(
        conn,
        Agents.open_session(API.principal(conn), project_id, API.attrs(conn)),
        :created
      )
end
