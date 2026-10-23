defmodule SamgitaCodexDriver.NativeThreadControlQueriesTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}

  import TurnFixture,
    only: [
      call: 3,
      start: 1,
      start: 2,
      thread: 2,
      thread: 3,
      upstream_error: 3,
      upstream_error: 4
    ]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @cursor_before "00000000-0000-0000-0000-000000000000"
  @cursor_after "ffffffff-ffff-ffff-ffff-ffffffffffff"

  setup {TurnFixture, :setup}

  test "empty loaded queries preserve nullable defaults and return before string cursor parsing",
       ctx do
    pid = start(ctx)

    for params <- [
          %{},
          %{"cursor" => nil, "limit" => nil},
          %{"limit" => 0},
          %{"cursor" => "not-a-thread-id"},
          %{"cursor" => "not-a-thread-id", "limit" => 0}
        ] do
      assert loaded(pid, params) == %{"data" => [], "nextCursor" => nil}
    end

    assert_idle(ctx, pid)
  end

  test "loaded pagination sorts exact identities and treats zero as one and null as unlimited",
       ctx do
    pid = start(ctx)
    ids = for _ <- 1..3, do: thread(ctx, pid)
    [first, second, last] = expected = Enum.sort(ids)

    for params <- [%{}, %{"limit" => nil}, %{"cursor" => nil, "limit" => 99}] do
      assert loaded(pid, params) == %{"data" => expected, "nextCursor" => nil}
    end

    assert loaded(pid, %{"limit" => 0}) == %{"data" => [first], "nextCursor" => first}

    assert loaded(pid, %{"cursor" => first, "limit" => 1}) == %{
             "data" => [second],
             "nextCursor" => second
           }

    assert loaded(pid, %{"cursor" => second, "limit" => 0}) == %{
             "data" => [last],
             "nextCursor" => nil
           }

    assert loaded(pid, %{"cursor" => first, "limit" => nil}) == %{
             "data" => [second, last],
             "nextCursor" => nil
           }

    assert loaded(pid, %{"cursor" => first}) == %{
             "data" => [second, last],
             "nextCursor" => nil
           }

    assert loaded(pid, %{"cursor" => last, "limit" => 1}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    assert loaded(pid) == %{"data" => expected, "nextCursor" => nil}
    assert_idle(ctx, pid)
  end

  test "valid absent cursors use UUID insertion points before and after loaded identities", ctx do
    pid = start(ctx)
    expected = Enum.sort(for _ <- 1..3, do: thread(ctx, pid))
    assert @cursor_before < hd(expected)
    assert @cursor_after > List.last(expected)

    assert loaded(pid, %{"cursor" => @cursor_before}) == %{
             "data" => expected,
             "nextCursor" => nil
           }

    assert loaded(pid, %{"cursor" => @cursor_before, "limit" => 1}) == %{
             "data" => [hd(expected)],
             "nextCursor" => hd(expected)
           }

    assert loaded(pid, %{"cursor" => @cursor_after}) == %{"data" => [], "nextCursor" => nil}

    # Parsing canonicalizes a UUID cursor before binary search.
    assert loaded(pid, %{"cursor" => String.upcase(hd(expected))}) == %{
             "data" => tl(expected),
             "nextCursor" => nil
           }

    assert loaded(pid) == %{"data" => expected, "nextCursor" => nil}
    assert_idle(ctx, pid)
  end

  test "native malformed cursor and unsigned-limit errors preserve loaded membership", ctx do
    pid = start(ctx)
    id = thread(ctx, pid)

    assert upstream_error(pid, "thread/loaded/list", %{"cursor" => "not-a-thread-id"}) ==
             invalid("invalid cursor: not-a-thread-id")

    for {params, reason} <- [
          {%{"cursor" => 17}, "expected a string"},
          {%{"limit" => "one"}, "expected u32"},
          {%{"limit" => -1}, "expected u32"},
          {%{"limit" => 4_294_967_296}, "expected u32"}
        ] do
      assert_invalid_wire(pid, "thread/loaded/list", params, reason)
      assert loaded(pid) == %{"data" => [id], "nextCursor" => nil}
    end

    assert_idle(ctx, pid)
  end

  test "unsubscribe distinguishes unknown unsubscribed and not-subscribed without unloading",
       ctx do
    pid = start(ctx)

    assert call(pid, "thread/unsubscribe", %{"threadId" => @cursor_before}) == %{
             "status" => "notLoaded"
           }

    id = thread(ctx, pid)

    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{
             "status" => "unsubscribed"
           }

    assert call(pid, "thread/unsubscribe", %{"threadId" => id}) == %{
             "status" => "notSubscribed"
           }

    # The default 1800-second idle delay stays unchanged. Receipt of unsubscribe
    # does not itself prove thread/closed; the thread is still loaded here.
    assert loaded(pid) == %{"data" => [id], "nextCursor" => nil}

    assert call(pid, "thread/read", %{"threadId" => id})["thread"]["status"] == %{
             "type" => "idle"
           }

    assert_idle(ctx, pid)
  end

  test "thread-local elicitation counters balance independently and reject zero underflow", ctx do
    pid = start(ctx)
    first = thread(ctx, pid)
    second = thread(ctx, pid)
    assert_zero_underflow(pid, first)
    assert counter(pid, "increment", first) == %{"count" => 1, "paused" => true}
    assert counter(pid, "increment", first) == %{"count" => 2, "paused" => true}
    assert counter(pid, "increment", second) == %{"count" => 1, "paused" => true}
    assert counter(pid, "decrement", first) == %{"count" => 1, "paused" => true}
    assert counter(pid, "decrement", second) == %{"count" => 0, "paused" => false}
    assert_zero_underflow(pid, second)
    assert counter(pid, "decrement", first) == %{"count" => 0, "paused" => false}
    assert_zero_underflow(pid, first)
    assert counter(pid, "increment", first) == %{"count" => 1, "paused" => true}
    assert counter(pid, "decrement", first) == %{"count" => 0, "paused" => false}
    assert loaded(pid)["data"] == Enum.sort([first, second])
    assert_idle(ctx, pid)
  end

  test "cold restart retains an empty named thread but resets its runtime elicitation counter",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "paginated"})
    name = "Owned empty control thread λ"
    assert call(pid, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    assert counter(pid, "increment", id) == %{"count" => 1, "paused" => true}
    assert counter(pid, "increment", id) == %{"count" => 2, "paused" => true}
    original_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(original_process) and original_process > 0
    assert :ok = Session.close(pid)

    cold = start(ctx)
    cold_process = call(cold, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(cold_process) and cold_process > 0
    refute cold_process == original_process
    assert loaded(cold) == %{"data" => [], "nextCursor" => nil}

    for action <- ["increment", "decrement"] do
      assert upstream_error(cold, "thread/#{action}_elicitation", %{"threadId" => id}) ==
               invalid("thread not found: #{id}")
    end

    resumed = call(cold, "thread/resume", %{"threadId" => id, "excludeTurns" => true})["thread"]
    assert resumed["id"] == id
    assert resumed["name"] == name
    assert resumed["historyMode"] == "paginated"
    assert resumed["turns"] == []
    assert_zero_underflow(cold, id)
    assert counter(cold, "increment", id) == %{"count" => 1, "paused" => true}
    assert counter(cold, "decrement", id) == %{"count" => 0, "paused" => false}

    assert call(cold, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
             "turns"
           ] == []

    assert loaded(cold) == %{"data" => [id], "nextCursor" => nil}
    assert_idle(ctx, cold)
  end

  test "the official native experimental self-test echoes values and rejects disabled or invalid input",
       ctx do
    pid = start(ctx)

    for value <- ["", "Unicode λ🙂\n\u0000\"\\"] do
      assert call(pid, "mock/experimentalMethod", %{"value" => value}) == %{"echoed" => value}
    end

    for params <- [%{}, %{"value" => nil}] do
      assert call(pid, "mock/experimentalMethod", params) == %{"echoed" => nil}
    end

    for value <- [false, 17, [], %{}] do
      assert_invalid_wire(
        pid,
        "mock/experimentalMethod",
        %{"value" => value},
        "expected a string"
      )
    end

    assert call(pid, "mock/experimentalMethod", %{"value" => "after rejection"}) == %{
             "echoed" => "after rejection"
           }

    assert_idle(ctx, pid)
    assert :ok = Session.close(pid)
    stable = start(ctx, experimental: false)

    for {method, params} <- [
          {"mock/experimentalMethod", %{"value" => "disabled"}},
          {"thread/increment_elicitation", %{"threadId" => @cursor_before}},
          {"thread/decrement_elicitation", %{"threadId" => @cursor_before}}
        ] do
      assert upstream_error(stable, method, params, validation: :wire) ==
               invalid("#{method} requires experimentalApi capability")
    end

    assert loaded(stable) == %{"data" => [], "nextCursor" => nil}
    assert_idle(ctx, stable)
  end

  defp loaded(pid, params \\ %{}), do: call(pid, "thread/loaded/list", params)

  defp counter(pid, action, id),
    do: call(pid, "thread/#{action}_elicitation", %{"threadId" => id})

  defp assert_zero_underflow(pid, id) do
    assert upstream_error(pid, "thread/decrement_elicitation", %{"threadId" => id}) ==
             invalid("out-of-band elicitation count is already zero")
  end

  defp assert_invalid_wire(pid, method, params, reason) do
    error = upstream_error(pid, method, params, validation: :wire)
    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "Invalid request: ")
    assert error["message"] =~ reason
  end

  defp invalid(message), do: %{"code" => -32_600, "message" => message}

  defp assert_idle(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
  end
end
