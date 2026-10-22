defmodule SamgitaWeb.ProjectController do
  use SamgitaWeb, :controller

  alias Samgita.Projects
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def index(conn, params), do: API.result(conn, Projects.list(API.principal(conn), params))
  def show(conn, %{"id" => id}), do: API.result(conn, Projects.get(API.principal(conn), id))

  def create(conn, _params),
    do: API.result(conn, Projects.create(API.principal(conn), API.attrs(conn)), :created)

  def update(conn, %{"id" => id}),
    do: API.result(conn, Projects.update(API.principal(conn), id, API.attrs(conn)))

  def transition(conn, %{"project_id" => id}),
    do: API.result(conn, Projects.transition(API.principal(conn), id, API.attrs(conn)))

  def context(conn, %{"project_id" => id}),
    do: API.result(conn, Projects.context(API.principal(conn), id, conn.query_params))

  def put_member(conn, %{"project_id" => id}),
    do: API.result(conn, Projects.put_member(API.principal(conn), id, API.attrs(conn)))
end
