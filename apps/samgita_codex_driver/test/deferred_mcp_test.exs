defmodule SamgitaCodexDriver.DeferredMcpTest do
  use ExUnit.Case, async: false

  import SamgitaCodexDriver.TurnFixture
  alias SamgitaCodexDriver.{ModelFixture, Session}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/deferred_mcp_fixture.py", __DIR__)
  @search "deferred-search-1"
  @tool "deferred-echo-1"
  @message "quasar_echo_824 synthetic λ"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-deferred-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, Map.get(tags, :scenario, "success"))
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    context = %{binary: binary, fixture: fixture, root: root}
    configure_model(context, %{"supports_search_tool" => not Map.get(tags, :no_search, false)})
    context
  end

  test "deferred discovery routes a namespaced MCP call and retains search and result identities",
       ctx do
    {pid, thread, turn, events} = complete(ctx)
    [first, second, third] = ModelFixture.requests(ctx.fixture)
    assert_deferred([first, second, third])
    search = search_output(second)
    assert %{"call_id" => @search, "execution" => "client", "status" => "completed"} = search
    assert [namespace] = search["tools"]
    assert namespace["type"] == "namespace"
    assert namespace["name"] == "mcp__deferred"
    assert namespace["description"] == "Synthetic quasar tools for isolated discovery."
    assert [tool] = namespace["tools"]
    assert %{"name" => "echo", "type" => "function", "defer_loading" => true} = tool
    assert tool["parameters"]["required"] == ["message"]
    assert tool["parameters"]["properties"]["message"] == %{"type" => "string"}
    assert search_output(third) == search

    output = function_output(third)
    assert output["call_id"] == @tool
    assert structured_output(output) == %{"echo" => @message, "association" => @tool}
    assert [call] = mcp_calls(ctx)
    assert get_in(call, ["params", "name"]) == "echo"
    assert get_in(call, ["params", "arguments"]) == %{"message" => @message}
    assert get_in(call, ["params", "_meta", "threadId"]) == thread

    started = mcp_item(events, "item/started")
    completed = mcp_item(events, "item/completed")
    assert started["threadId"] == thread and started["turnId"] == turn
    assert completed["threadId"] == thread and completed["turnId"] == turn
    assert started["item"]["id"] == completed["item"]["id"]

    assert %{
             "server" => "deferred",
             "tool" => "echo",
             "arguments" => %{"message" => @message},
             "status" => "completed",
             "error" => nil
           } = completed["item"]

    assert completed["item"]["result"]["structuredContent"] == %{
             "echo" => @message,
             "association" => @tool
           }

    assert completed["item"]["result"]["content"] == [
             %{"type" => "text", "text" => "Synthetic deferred MCP result: " <> @message}
           ]

    assert :ok = Session.close(pid)
  end

  @tag scenario: "tool_error"
  test "a discovered MCP isError result reaches native items and model history", ctx do
    {pid, _thread, _turn, events} = complete(ctx)
    assert [_, _, third] = requests = ModelFixture.requests(ctx.fixture)
    assert_deferred(requests)

    assert structured_output(function_output(third)) == %{
             "echo" => @message,
             "association" => @tool
           }

    completed = mcp_item(events, "item/completed")["item"]
    assert completed["status"] == "failed"
    assert completed["result"]["structuredContent"]["echo"] == @message
    assert length(mcp_calls(ctx)) == 1
    assert :ok = Session.close(pid)
  end

  @tag scenario: "rpc_error"
  test "a discovered MCP protocol failure remains associated with its model call", ctx do
    {pid, _thread, _turn, events} = complete(ctx)
    assert [_, _, third] = requests = ModelFixture.requests(ctx.fixture)
    assert_deferred(requests)
    output = output_text(function_output(third))
    assert output =~ "synthetic deferred protocol failure"
    refute output =~ "unsupported call"
    completed = mcp_item(events, "item/completed")["item"]
    assert completed["status"] == "failed"
    assert completed["error"]["message"] =~ "synthetic deferred protocol failure"
    assert length(mcp_calls(ctx)) == 1
    assert :ok = Session.close(pid)
  end

  @tag scenario: "filtered"
  test "disabled MCP tools are absent from deferred search results", ctx do
    {pid, _thread, _turn, events} = complete(ctx)
    assert [first, second] = ModelFixture.requests(ctx.fixture)
    assert_deferred([first, second])
    assert search_output(second)["tools"] == []
    assert mcp_calls(ctx) == []
    refute mcp_item(events, "item/started")
    assert :ok = Session.close(pid)
  end

  for scenario <- ["empty_query", "zero_limit"] do
    @tag scenario: scenario
    test "invalid deferred search #{scenario} cannot invoke an MCP tool", ctx do
      {pid, _thread, _turn, events} = complete(ctx)
      assert [first, second] = ModelFixture.requests(ctx.fixture)
      assert_deferred([first, second])
      assert %{"call_id" => @search, "tools" => []} = search_output(second)
      assert mcp_calls(ctx) == []
      refute mcp_item(events, "item/started")
      assert :ok = Session.close(pid)
    end
  end

  @tag scenario: "gating", no_search: true
  test "a model without search support receives the enabled direct MCP namespace", ctx do
    {pid, _thread, _turn, _events} = complete(ctx)
    assert [request] = ModelFixture.requests(ctx.fixture)
    refute Enum.any?(request["tools"], &(&1["type"] == "tool_search"))
    assert namespace = Enum.find(request["tools"], &(&1["name"] == "mcp__deferred"))
    assert Enum.map(namespace["tools"], & &1["name"]) == ["echo"]
    assert mcp_calls(ctx) == []
    assert :ok = Session.close(pid)
  end

  @tag scenario: "hold"
  test "interruption terminates an in-flight discovered MCP call without a model follow-up",
       ctx do
    {pid, thread} = connected(ctx)

    turn =
      start_turn(pid, thread, [%{"type" => "text", "text" => "Run the synthetic deferred tool"}])

    started =
      collect_until(pid, fn events -> mcp_item(events, "item/started") && mcp_calls(ctx) != [] end)

    refute terminal(started, turn)
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}
    events = collect_until(pid, &terminal(&1, turn), started)

    assert %{"threadId" => ^thread, "turn" => %{"status" => "interrupted"}} =
             terminal(events, turn)

    assert length(mcp_calls(ctx)) == 1
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_deferred(ModelFixture.requests(ctx.fixture))
    assert :ok = Session.close(pid)
  end

  defp complete(ctx) do
    {pid, thread} = connected(ctx)

    turn =
      start_turn(pid, thread, [%{"type" => "text", "text" => "Run the synthetic deferred tool"}])

    events = finish_turn(pid, thread, turn)
    {pid, thread, turn, events}
  end

  defp connected(ctx) do
    pid = start(ctx)
    thread = thread(ctx, pid)

    inventory =
      call(pid, "mcpServerStatus/list", %{"threadId" => thread, "serverName" => "deferred"})

    assert [%{"name" => "deferred", "toolsError" => nil}] = inventory["data"]
    {pid, thread}
  end

  defp assert_deferred(requests) do
    for request <- requests do
      assert Enum.any?(request["tools"], &(&1["type"] == "tool_search"))

      refute Enum.any?(
               request["tools"],
               &(&1["name"] in ["mcp__deferred", "mcp__deferred__echo", "echo"])
             )
    end
  end

  defp search_output(request),
    do:
      Enum.find(
        request["input"],
        &(&1["type"] == "tool_search_output" and &1["call_id"] == @search)
      )

  defp function_output(request),
    do:
      Enum.find(
        request["input"],
        &(&1["type"] == "function_call_output" and &1["call_id"] == @tool)
      )

  defp output_text(%{"output" => text}) when is_binary(text), do: text

  defp output_text(%{"output" => content}),
    do: Enum.map_join(content, "\n", &Map.get(&1, "text", ""))

  defp structured_output(output) do
    assert [header, payload] = String.split(output_text(output), "\nOutput:\n", parts: 2)
    assert header =~ ~r/^Wall time: \d+\.\d{4} seconds$/
    JSON.decode!(payload)
  end

  defp mcp_item(events, method),
    do: notification(events, method, &(&1["item"]["type"] == "mcpToolCall"))

  defp terminal(events, turn),
    do: notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

  defp mcp_calls(ctx) do
    path = Path.join(ctx.fixture.codex_home, "mcp.jsonl")

    if File.exists?(path),
      do:
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&JSON.decode!/1)
        |> Enum.filter(&(&1["method"] == "tools/call")),
      else: []
  end

  defp collect_until(pid, predicate, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    refute Enum.any?(incoming, &(&1.kind == :server_request))

    cond do
      predicate.(events) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Deferred MCP event deadline: #{inspect(Session.status(pid))}")

      true ->
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Deferred MCP event gap")
        after
          20 -> :ok
        end

        collect_until(pid, predicate, events, deadline)
    end
  end
end
