defmodule SamgitaWeb.Plugs.RateLimitTest do
  use ExUnit.Case, async: false

  alias SamgitaWeb.Plugs.RateLimit

  import Plug.Conn

  setup do
    limiter = start_supervised!({SamgitaWeb.RateLimiter, name: nil})
    Process.put(:limiter, limiter)
    :ok
  end

  defp options(opts), do: RateLimit.init(Keyword.put(opts, :server, Process.get(:limiter)))

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
    opts = options(limit: 5, window_ms: 60_000)
    conn = build_conn()

    result = RateLimit.call(conn, opts)
    refute result.halted
    assert get_resp_header(result, "x-ratelimit-limit") == ["5"]
    assert get_resp_header(result, "x-ratelimit-remaining") == ["4"]
  end

  test "blocks requests over the limit" do
    opts = options(limit: 3, window_ms: 60_000)

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
    opts = options(limit: 2, window_ms: 60_000)

    # Exhaust limit for IP 1
    for _ <- 1..2 do
      RateLimit.call(build_conn({10, 0, 0, 1}), opts)
    end

    # IP 2 should still be allowed
    result = RateLimit.call(build_conn({10, 0, 0, 2}), opts)
    refute result.halted
  end

  test "decrements remaining count with each request" do
    opts = options(limit: 5, window_ms: 60_000)

    conn1 = RateLimit.call(build_conn(), opts)
    assert get_resp_header(conn1, "x-ratelimit-remaining") == ["4"]

    conn2 = RateLimit.call(build_conn(), opts)
    assert get_resp_header(conn2, "x-ratelimit-remaining") == ["3"]
  end

  test "quota survives termination of the request that first uses the limiter" do
    opts = options(limit: 1)
    task = Task.async(fn -> RateLimit.call(build_conn({10, 8, 0, 1}), opts) end)
    refute Task.await(task).halted
    assert RateLimit.call(build_conn({10, 8, 0, 1}), opts).status == 429
  end

  test "simultaneous independent requests cannot over-admit at the quota boundary" do
    opts = options(limit: 1)
    owner = self()

    workers =
      for _ <- 1..64 do
        Task.async(fn ->
          send(owner, {:ready, self()})

          receive do
            :go -> RateLimit.call(build_conn({10, 8, 0, 2}), opts)
          end
        end)
      end

    ready =
      for _ <- workers do
        assert_receive {:ready, pid}
        pid
      end

    Enum.each(ready, &send(&1, :go))

    results = Enum.map(workers, &Task.await/1)
    assert Enum.count(results, &(!&1.halted)) == 1
    assert Enum.count(results, &(&1.status == 429)) == 63
  end

  test "window expiry and bounded cleanup use a monotonic clock" do
    clock = start_supervised!({Agent, fn -> 0 end})

    limiter =
      start_supervised!(
        {SamgitaWeb.RateLimiter, name: nil, clock: fn -> Agent.get(clock, & &1) end},
        id: :clock_limiter
      )

    opts = RateLimit.init(limit: 1, window_ms: 1000, server: limiter)
    refute RateLimit.call(build_conn(), opts).halted
    assert RateLimit.call(build_conn(), opts).status == 429
    Agent.update(clock, fn _ -> 1000 end)
    refute RateLimit.call(build_conn(), opts).halted
    Agent.update(clock, fn _ -> 2000 end)
    send(limiter, :cleanup)
    refute RateLimit.call(build_conn(), opts).halted
  end

  test "application supervisor restarts the owner with an explicitly empty quota" do
    owner = Process.whereis(SamgitaWeb.RateLimiter)
    opts = RateLimit.init(limit: 1)
    refute RateLimit.call(build_conn({10, 8, 0, 3}), opts).halted
    monitor = Process.monitor(owner)
    assert :ok = Supervisor.terminate_child(SamgitaWeb.Supervisor, SamgitaWeb.RateLimiter)
    assert_receive {:DOWN, ^monitor, :process, ^owner, _}

    assert {:ok, replacement} =
             Supervisor.restart_child(SamgitaWeb.Supervisor, SamgitaWeb.RateLimiter)

    refute replacement == owner
    refute RateLimit.call(build_conn({10, 8, 0, 3}), opts).halted
  end

  test "cleanup visits bounded batches and resumes its cursor" do
    clock = start_supervised!({Agent, fn -> 0 end})

    limiter =
      start_supervised!(
        {SamgitaWeb.RateLimiter, name: nil, clock: fn -> Agent.get(clock, & &1) end},
        id: :batch_limiter
      )

    for key <- 1..1_100 do
      assert {:ok, 0} = SamgitaWeb.RateLimiter.admit(limiter, key, 1, 1_000)
    end

    Agent.update(clock, fn _ -> 1_000 end)

    for remaining <- [600, 100, 0] do
      send(limiter, :cleanup)
      state = :sys.get_state(limiter)
      assert :ets.info(state.table, :size) == remaining
      assert state.cursor == :start == (remaining == 0)
    end
  end
end
