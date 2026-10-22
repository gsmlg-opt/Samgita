defmodule SamgitaWeb.AgentController do
  use SamgitaWeb, :controller

  alias Samgita.Agents
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def index(conn, params), do: API.result(conn, Agents.list(API.principal(conn), params))
  def show(conn, %{"id" => id}), do: API.result(conn, Agents.get(API.principal(conn), id))

  def create(conn, _params),
    do: API.result(conn, Agents.register(API.principal(conn), API.attrs(conn)), :created)

  def update(conn, %{"id" => id}),
    do: API.result(conn, Agents.update(API.principal(conn), id, API.attrs(conn)))

  def put_credential(conn, %{"agent_id" => id}) do
    conn
    |> API.no_store()
    |> API.result(Agents.put_credential(API.principal(conn), id, API.attrs(conn)), :created)
  end

  def revoke_credential(conn, %{"agent_id" => id, "credential_id" => credential_id}) do
    attrs = Map.put(API.attrs(conn), "credential_id", credential_id)

    conn
    |> API.no_store()
    |> API.result(Agents.revoke_credential(API.principal(conn), id, attrs))
  end

  def connect(conn, _params) do
    conn
    |> API.no_store()
    |> API.result(Agents.connect(API.principal(conn), API.attrs(conn)), :created)
  end
end
