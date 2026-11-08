defmodule SamgitaWeb.CodexHostController do
  use SamgitaWeb, :controller
  alias Samgita.CodexHosts
  alias SamgitaWeb.DomainAPI, as: API
  action_fallback SamgitaWeb.FallbackController

  def index(conn, _params), do: API.result(conn, CodexHosts.list(API.principal(conn)))

  def show(conn, %{"id" => id}), do: API.result(conn, CodexHosts.get(API.principal(conn), id))

  def create(conn, _params),
    do: API.result(conn, CodexHosts.configure(API.principal(conn), API.attrs(conn)))

  def enable(conn, %{"codex_host_id" => id}),
    do: API.result(conn, CodexHosts.enable(API.principal(conn), id, API.attrs(conn)))

  def disable(conn, %{"codex_host_id" => id}),
    do: API.result(conn, CodexHosts.disable(API.principal(conn), id, API.attrs(conn)))

  def reconnect(conn, %{"codex_host_id" => id}) do
    case CodexHosts.reconnect(API.principal(conn), id) do
      :ok -> API.result(conn, CodexHosts.get(API.principal(conn), id), :accepted)
      error -> error
    end
  end
end
