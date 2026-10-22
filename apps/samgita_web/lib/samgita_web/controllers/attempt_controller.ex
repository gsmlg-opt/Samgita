defmodule SamgitaWeb.AttemptController do
  use SamgitaWeb, :controller

  alias Samgita.Attempts
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def claim(conn, %{"project_id" => project_id, "task_id" => task_id}),
    do:
      API.result(
        conn,
        Attempts.claim(API.principal(conn), project_id, task_id, API.attrs(conn)),
        :created
      )

  def start(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Attempts.start(API.principal(conn), project_id, id, API.attrs(conn)))

  def renew(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Attempts.renew(API.principal(conn), project_id, id, API.attrs(conn)))

  def report(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Attempts.report(API.principal(conn), project_id, id, API.attrs(conn)))

  def rebind(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Attempts.rebind(API.principal(conn), project_id, id, API.attrs(conn)))

  def resolve(conn, %{"project_id" => project_id, "id" => id}),
    do: API.result(conn, Attempts.resolve(API.principal(conn), project_id, id, API.attrs(conn)))

  def proof(conn, %{"project_id" => project_id, "id" => id}) do
    conn
    |> API.no_store()
    |> API.result(Attempts.proof(API.principal(conn), project_id, id))
  end
end
