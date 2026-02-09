defmodule SamgitaWeb.Plugs.RateLimitTest do
  use ExUnit.Case, async: false

  alias SamgitaWeb.Plugs.RateLimit

  import Plug.Conn

  setup do
    # Clean up ETS table between tests
    case :ets.whereis(:samgita_rate_limit) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:samgita_rate_limit)
    end

    :ok
  end

  defp build_conn(ip \\ {127, 0, 0, 1}) do
    %Plug.Conn{remote_ip: ip}
    |> put_private(:phoenix_endpoint, SamgitaWeb.Endpoint)
    |> put_private(:phoenix_router, SamgitaWeb.Router)
    |> put_private(:phoenix_format, "json")
    |> Map.put(:state, :unset)
  end

  test "init/1 returns default options" do
    opts = RateLimit.init([])
    assert opts.limit == 100
    assert opts.window_ms == 60_000
  end

  test "init/1 accepts custom options" do
    opts = RateLimit.init(limit: 10, window_ms: 5_000)
    assert opts.limit == 10
    assert opts.window_ms == 5_000
  end

  test "allows requests under the limit" do
    opts = RateLimit.init(limit: 5, window_ms: 60_000)
    conn = build_conn()

    result = RateLimit.call(conn, opts)
    refute result.halted
    assert get_resp_header(result, "x-ratelimit-limit") == ["5"]
    assert get_resp_header(result, "x-ratelimit-remaining") == ["4"]
  end

  test "blocks requests over the limit" do
    opts = RateLimit.init(limit: 3, window_ms: 60_000)

    # Make 3 requests (at limit)
    for _ <- 1..3 do
      conn = build_conn()
      RateLimit.call(conn, opts)
    end

    # 4th request should be blocked
    conn = build_conn()
    result = RateLimit.call(conn, opts)
    assert result.halted
    assert result.status == 429
    assert get_resp_header(result, "retry-after") == ["60"]
  end

  test "different IPs have separate rate limits" do
    opts = RateLimit.init(limit: 2, window_ms: 60_000)

    # Exhaust limit for IP 1
    for _ <- 1..2 do
      RateLimit.call(build_conn({10, 0, 0, 1}), opts)
    end

    # IP 2 should still be allowed
    result = RateLimit.call(build_conn({10, 0, 0, 2}), opts)
    refute result.halted
  end

  test "decrements remaining count with each request" do
    opts = RateLimit.init(limit: 5, window_ms: 60_000)

    conn1 = RateLimit.call(build_conn(), opts)
    assert get_resp_header(conn1, "x-ratelimit-remaining") == ["4"]

    conn2 = RateLimit.call(build_conn(), opts)
    assert get_resp_header(conn2, "x-ratelimit-remaining") == ["3"]
  end
end
