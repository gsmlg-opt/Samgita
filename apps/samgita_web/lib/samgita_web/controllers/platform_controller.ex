defmodule SamgitaWeb.PlatformController do
  use SamgitaWeb, :controller

  alias Samgita.Platform
  alias SamgitaWeb.DomainAPI, as: API

  action_fallback SamgitaWeb.FallbackController

  def show(conn, _params), do: API.result(conn, Platform.status(API.principal(conn)))

  def activate(conn, _params),
    do: API.result(conn, Platform.activate(API.principal(conn), API.attrs(conn)))

  def close(conn, _params),
    do: API.result(conn, Platform.close(API.principal(conn), API.attrs(conn)))
end
