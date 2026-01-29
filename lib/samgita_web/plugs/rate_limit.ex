defmodule SamgitaWeb.Plugs.RateLimit do
  @moduledoc """
  Simple ETS-based rate limiting plug for API endpoints.
  Limits requests per IP address within a sliding window.
  """

  import Plug.Conn

  @default_limit 100
  @default_window_ms 60_000

  def init(opts) do
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    }
  end

  def call(conn, opts) do
    ensure_table()
    key = rate_limit_key(conn)
    now = System.monotonic_time(:millisecond)
    window_start = now - opts.window_ms

    cleanup_expired(key, window_start)
    count = count_requests(key, window_start)

    if count >= opts.limit do
      body =
        Jason.encode!(%{
          error: "Too Many Requests",
          message: "Rate limit exceeded. Try again later."
        })

      conn
      |> put_resp_header("retry-after", to_string(div(opts.window_ms, 1000)))
      |> put_resp_content_type("application/json")
      |> resp(429, body)
      |> halt()
    else
      record_request(key, now)

      conn
      |> put_resp_header("x-ratelimit-limit", to_string(opts.limit))
      |> put_resp_header("x-ratelimit-remaining", to_string(opts.limit - count - 1))
    end
  end

  defp rate_limit_key(conn) do
    ip =
      conn.remote_ip
      |> :inet.ntoa()
      |> to_string()

    {:rate_limit, ip}
  end

  defp ensure_table do
    case :ets.whereis(:samgita_rate_limit) do
      :undefined ->
        :ets.new(:samgita_rate_limit, [:named_table, :public, :duplicate_bag])

      _ ->
        :ok
    end
  end

  defp count_requests(key, window_start) do
    :ets.select_count(:samgita_rate_limit, [
      {{key, :"$1"}, [{:>=, :"$1", window_start}], [true]}
    ])
  end

  defp record_request(key, now) do
    :ets.insert(:samgita_rate_limit, {key, now})
  end

  defp cleanup_expired(key, window_start) do
    :ets.select_delete(:samgita_rate_limit, [
      {{key, :"$1"}, [{:<, :"$1", window_start}], [true]}
    ])
  end
end
