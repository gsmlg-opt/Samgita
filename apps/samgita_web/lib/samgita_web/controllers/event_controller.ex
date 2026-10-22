defmodule SamgitaWeb.EventController do
  use SamgitaWeb, :controller
  alias Samgita.{Events, EventDelivery}
  alias SamgitaWeb.DomainAPI, as: API
  action_fallback SamgitaWeb.FallbackController

  def index(conn, %{"project_id" => id}),
    do: API.result(conn, Events.read(API.principal(conn), id, conn.query_params))

  def trigger(conn, %{"project_id" => id}),
    do: API.result(conn, Events.trigger(API.principal(conn), id, API.attrs(conn)), :created)

  def external(conn, %{"project_id" => id}),
    do: API.result(conn, Events.external(API.principal(conn), id, API.attrs(conn)), :created)

  def redeliver(conn, %{"project_id" => id, "event_id" => event}),
    do:
      API.result(
        conn,
        Events.redeliver(API.principal(conn), id, event, API.attrs(conn)),
        :created
      )

  def routing(conn, %{"project_id" => id}),
    do: API.result(conn, Events.routing(API.principal(conn), id))

  def configure(conn, %{"project_id" => id}),
    do: API.result(conn, Events.configure(API.principal(conn), id, API.attrs(conn)))

  def ack_cursor(conn, %{"project_id" => id, "subscription_id" => subscription}),
    do:
      API.result(conn, Events.ack_cursor(API.principal(conn), id, subscription, API.attrs(conn)))

  def deliveries(conn, %{"project_id" => id}),
    do: API.result(conn, EventDelivery.list(API.principal(conn), id, conn.query_params))

  def delivery(conn, %{"project_id" => id, "id" => delivery}),
    do: API.result(conn, EventDelivery.get(API.principal(conn), id, delivery))

  def recover(conn, %{"project_id" => id, "id" => delivery}),
    do:
      API.result(conn, EventDelivery.recover(API.principal(conn), id, delivery, API.attrs(conn)))

  def report(conn, %{"project_id" => id, "id" => delivery}),
    do: API.result(conn, EventDelivery.report(API.principal(conn), id, delivery, API.attrs(conn)))
end
