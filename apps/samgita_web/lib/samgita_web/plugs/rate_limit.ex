defmodule SamgitaWeb.Plugs.RateLimit do
  @moduledoc "Node-local IP admission backed by the supervised sliding-window limiter."
  import Plug.Conn
  alias SamgitaWeb.RateLimiter

  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      server: Keyword.get(opts, :server, RateLimiter)
    }
  end

  def call(conn, opts) do
    case RateLimiter.admit(opts.server, conn.remote_ip, opts.limit, opts.window_ms) do
      {:ok, remaining} ->
        conn
        |> put_resp_header("x-ratelimit-limit", to_string(opts.limit))
        |> put_resp_header("x-ratelimit-remaining", to_string(remaining))

      {:limited, retry_ms} ->
        body =
          Jason.encode!(%{
            error: "Too Many Requests",
            message: "Rate limit exceeded. Try again later."
          })

        conn
        |> put_resp_header("retry-after", to_string(div(retry_ms + 999, 1000)))
        |> put_resp_content_type("application/json")
        |> resp(429, body)
        |> halt()
    end
  end
end
