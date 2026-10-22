defmodule SamgitaWeb.ScheduleController do
  use SamgitaWeb, :controller
  alias Samgita.Schedules
  alias SamgitaWeb.DomainAPI, as: API
  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => id}),
    do: API.result(conn, Schedules.list(API.principal(conn), id, conn.query_params))

  def create(conn, %{"project_id" => id}),
    do: API.result(conn, Schedules.create(API.principal(conn), id, API.attrs(conn)), :created)

  def update(conn, %{"project_id" => id, "id" => schedule}),
    do: API.result(conn, Schedules.update(API.principal(conn), id, schedule, API.attrs(conn)))
end
