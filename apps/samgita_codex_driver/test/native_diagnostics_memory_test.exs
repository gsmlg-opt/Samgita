defmodule SamgitaCodexDriver.NativeDiagnosticsMemoryTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup tags do
    context = TurnFixture.setup(tags)
    TurnFixture.configure_model(context, %{})

    if tags[:in_memory] do
      path = Path.join(context.fixture.codex_home, "config.toml")
      id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      File.write!(
        path,
        ~s(experimental_thread_store = { type = "in_memory", id = "#{id}" }\n) <>
          File.read!(path)
      )
    end

    context
  end

  test "diagnostics identify the owned binary and reflect registered threads across restart",
       ctx do
    pid = TurnFixture.start(ctx)
    empty = diagnostics(pid, ctx)
    assert_unregistered_threads(empty)
    first = thread(ctx, pid)
    second = thread(ctx, pid)

    assert call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort() ==
             Enum.sort([first, second])

    loaded = diagnostics(pid, ctx)
    assert loaded["process"]["id"] == empty["process"]["id"]
    assert gauge(loaded, "core.threads.live") == 2

    for id <- [first, second] do
      assert call(pid, "thread/archive", %{"threadId" => id}) == %{}
    end

    assert :ok = Session.close(pid)

    cold = TurnFixture.start(ctx)
    restarted = diagnostics(cold, ctx)
    refute restarted["process"]["id"] == loaded["process"]["id"]
    assert_unregistered_threads(restarted)
    assert call(cold, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}

    for id <- [first, second] do
      assert call(cold, "thread/read", %{"threadId" => id})["thread"]["id"] == id
    end

    assert_unregistered_threads(diagnostics(cold, ctx))
    assert_idle(ctx, cold)
  end

  test "disabled experimental negotiation reaches native diagnostics and memory rejection", ctx do
    pid = TurnFixture.start(ctx, experimental: false)

    for {method, params} <- [
          {"server/diagnostics", %{}},
          {"memory/status", %{}},
          {"memory/reset", nil}
        ] do
      assert upstream_error(pid, method, params, validation: :wire) == %{
               "code" => -32_600,
               "message" => "#{method} requires experimentalApi capability"
             }
    end

    assert_idle(ctx, pid)
  end

  test "memory status remains unready for native empty history, reset and cold restart", ctx do
    pid = TurnFixture.start(ctx)
    assert_empty_memory(pid)
    id = thread(ctx, pid)
    assert_empty_memory(pid)

    # This resets only the explicitly owned synthetic CODEX_HOME. No consolidation
    # records or summary files are fabricated to manufacture ready=true evidence.
    assert call(pid, "memory/reset", nil) == %{}
    assert_empty_memory(pid)
    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["id"] == id
    assert call(pid, "thread/archive", %{"threadId" => id}) == %{}
    assert :ok = Session.close(pid)
    cold = TurnFixture.start(ctx)
    assert_empty_memory(cold)
    assert call(cold, "thread/read", %{"threadId" => id})["thread"]["id"] == id
    assert_idle(ctx, cold)
  end

  test "invalid memory thresholds reject without changing subsequent native status", ctx do
    pid = TurnFixture.start(ctx)

    for minimum <- [0, 4_097, 4_294_967_295] do
      assert upstream_error(pid, "memory/status", %{"minConsolidatedThreads" => minimum}) == %{
               "code" => -32_602,
               "message" => "minConsolidatedThreads must be between 1 and 4096"
             }

      assert_empty_memory(pid)
    end

    assert_idle(ctx, pid)
  end

  @tag in_memory: true
  test "an in-memory thread store retains native sqlite-backed memory status", ctx do
    pid = TurnFixture.start(ctx)
    assert_empty_memory(pid)
    assert_unregistered_threads(diagnostics(pid, ctx))
    assert_idle(ctx, pid)
  end

  defp diagnostics(pid, ctx) do
    result = call(pid, "server/diagnostics", %{})
    process = result["process"]
    assert is_integer(process["id"]) and process["id"] > 0
    assert File.read_link!("/proc/#{process["id"]}/exe") == ctx.binary
    assert is_integer(process["residentMemoryBytes"]) and process["residentMemoryBytes"] > 0
    assert process["physicalFootprintBytes"] == nil
    assert gauge(result, "app.requests.in_flight") in [1, 2]
    assert Enum.all?(result["gauges"], &(is_binary(&1["name"]) and &1["value"] >= 0))
    names = Enum.map(result["gauges"], & &1["name"])
    assert names == Enum.uniq(names)
    result
  end

  defp gauge(result, name) do
    assert %{"value" => value} = Enum.find(result["gauges"], &(&1["name"] == name))
    value
  end

  defp assert_unregistered_threads(result) do
    # Gauges register on first use, rather than listing every static zero gauge.
    refute Enum.any?(result["gauges"], &(&1["name"] == "core.threads.live"))
  end

  defp assert_empty_memory(pid) do
    for params <- [
          %{},
          %{"minConsolidatedThreads" => nil},
          %{"minConsolidatedThreads" => 1},
          %{"minConsolidatedThreads" => 20},
          %{"minConsolidatedThreads" => 4_096}
        ] do
      assert call(pid, "memory/status", params) == %{
               "v2ConsolidatedThreads" => 0,
               "v2Ready" => false
             }
    end
  end

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
