defmodule SamgitaWeb.Plugs.AgentIngress do
  @moduledoc "First-contact device pairing and previously trusted inbound Agent connections."
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(%{request_path: "/app-server", method: "GET", query_string: ""} = conn, _opts) do
    opts = SamgitaWeb.Plugs.RateLimit.init(limit: 30, window_ms: 60_000)
    conn = SamgitaWeb.Plugs.RateLimit.call(conn, opts)

    if conn.halted do
      conn
    else
      conn
      |> put_resp_header("cache-control", "no-store")
      |> WebSockAdapter.upgrade(SamgitaWeb.AgentSocket, [],
        timeout: 60_000,
        max_frame_size: 262_144,
        max_message_size: 262_144,
        compress: false
      )
      |> halt()
    end
  end

  def call(%{request_path: "/app-server"} = conn, _opts),
    do: conn |> send_resp(400, "Invalid connection request") |> halt()

  def call(conn, _opts), do: conn
end
