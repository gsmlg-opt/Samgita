defmodule SamgitaWeb.CodexRuntimeController do
  use SamgitaWeb, :controller

  alias Samgita.CodexRuntime
  alias SamgitaWeb.DomainAPI, as: API
  action_fallback SamgitaWeb.FallbackController
  plug :no_store

  def index(conn, %{"project_id" => project}),
    do: result(conn, CodexRuntime.list(API.principal(conn), project, conn.params))

  def create(conn, %{"project_id" => project}),
    do: result(conn, CodexRuntime.bind(API.principal(conn), project, API.attrs(conn)), :created)

  def show(conn, %{"project_id" => project, "id" => id}),
    do: result(conn, CodexRuntime.get(API.principal(conn), project, id))

  def operations(conn, %{"project_id" => project, "id" => id}),
    do: result(conn, CodexRuntime.operations(API.principal(conn), project, id, conn.params))

  def events(conn, %{"project_id" => project, "id" => id}),
    do: result(conn, CodexRuntime.events(API.principal(conn), project, id, conn.params))

  def prepare(conn, %{"project_id" => project, "id" => id}),
    do:
      result(
        conn,
        CodexRuntime.prepare(API.principal(conn), project, id, API.attrs(conn)),
        :created
      )

  def reply(conn, %{"project_id" => project, "id" => id, "event_id" => event}),
    do:
      result(
        conn,
        CodexRuntime.reply(API.principal(conn), project, id, event, API.attrs(conn)),
        :created
      )

  def dispatch(conn, %{"project_id" => project, "id" => id, "operation_id" => operation}),
    do:
      result(
        conn,
        CodexRuntime.dispatch(API.principal(conn), project, id, operation, API.attrs(conn))
      )

  def settle(conn, %{"project_id" => project, "id" => id, "operation_id" => operation}),
    do:
      result(
        conn,
        CodexRuntime.settle(API.principal(conn), project, id, operation, API.attrs(conn))
      )

  def record_event(conn, %{"project_id" => project, "id" => id}),
    do:
      result(
        conn,
        CodexRuntime.record_event(API.principal(conn), project, id, API.attrs(conn)),
        :created
      )

  def reconnect(conn, %{"project_id" => project, "id" => id}),
    do: result(conn, CodexRuntime.reconnect(API.principal(conn), project, id, API.attrs(conn)))

  def cancel(conn, %{"project_id" => project, "id" => id, "operation_id" => operation}),
    do:
      result(
        conn,
        CodexRuntime.cancel(API.principal(conn), project, id, operation, API.attrs(conn))
      )

  def reconcile(conn, %{"project_id" => project, "id" => id, "operation_id" => operation}),
    do:
      result(
        conn,
        CodexRuntime.reconcile(API.principal(conn), project, id, operation, API.attrs(conn))
      )

  def attest_cessation(conn, %{"project_id" => project, "id" => id}),
    do:
      result(
        conn,
        CodexRuntime.attest_cessation(API.principal(conn), project, id, API.attrs(conn))
      )

  def native_operation(conn, %{"project_id" => project, "id" => id, "operation_id" => operation}),
    do: result(conn, CodexRuntime.native_operation(API.principal(conn), project, id, operation))

  def native_event(conn, %{"project_id" => project, "id" => id, "event_id" => event}),
    do: result(conn, CodexRuntime.native_event(API.principal(conn), project, id, event))

  defp result(conn, value, status \\ :ok), do: conn |> API.no_store() |> API.result(value, status)
  defp no_store(conn, _opts), do: API.no_store(conn)
end
