defmodule SamgitaWeb.TaskController do
  use SamgitaWeb, :controller

  alias Samgita.Tasks
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => project_id}),
    do: API.result(conn, Tasks.list(API.principal(conn), project_id, conn.query_params))

  def show(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Tasks.get(API.principal(conn), project_id, id))

  def create(conn, %{"project_id" => project_id}),
    do:
      API.result(
        conn,
        Tasks.create(API.principal(conn), project_id, API.attrs(conn)),
        :created
      )

  def update(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Tasks.update(API.principal(conn), project_id, id, API.attrs(conn)))

  def transition(conn, %{"project_id" => project_id, "task_id" => id}),
    do: API.result(conn, Tasks.transition(API.principal(conn), project_id, id, API.attrs(conn)))

  def adopt(conn, %{"project_id" => project_id, "task_id" => id}),
    do: API.result(conn, Tasks.adopt(API.principal(conn), project_id, id, API.attrs(conn)))

  def decide(conn, %{"project_id" => project_id, "task_id" => id}),
    do: API.result(conn, Tasks.decide(API.principal(conn), project_id, id, API.attrs(conn)))

  def add_artifact(conn, %{"project_id" => project_id, "task_id" => id}),
    do:
      API.result(
        conn,
        Tasks.add_artifact(API.principal(conn), project_id, id, API.attrs(conn)),
        :created
      )
end
