defmodule SamgitaProtocolWebSocket.Plug do
  @moduledoc "Reusable Plug for an existing endpoint or the optional standalone listener."
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: "GET", request_path: "/app-server", query_string: ""} = conn, opts) do
    with ["Bearer " <> token] when byte_size(token) > 0 <- get_req_header(conn, "authorization"),
         {:ok, principal} <- Keyword.fetch!(opts, :authenticate).(token) do
      opts = Keyword.put(opts, :principal, principal)

      conn
      |> put_resp_header("cache-control", "no-store")
      |> WebSockAdapter.upgrade(SamgitaProtocolWebSocket.Socket, opts,
        timeout: Keyword.get(opts, :idle_timeout_ms, 60_000),
        max_frame_size: Keyword.get(opts, :max_frame_bytes, 1_048_576),
        compress: false
      )
      |> halt()
    else
      _ ->
        conn
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  def call(conn, _opts), do: conn |> send_resp(404, "Not found") |> halt()
end
