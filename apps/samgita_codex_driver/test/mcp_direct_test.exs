defmodule SamgitaCodexDriver.McpDirectTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_direct_fixture.py", __DIR__)
  @missing_thread "00000000-0000-4000-8000-000000000000"
  @protocols [{false, "2025-06-18"}, {true, "2026-07-28"}]

  setup context do
    context = TurnFixture.setup(context)
    config = File.read!(Path.join(context.fixture.codex_home, "config.toml"))
    Map.put(context, :base_config, config)
  end

  test "direct tool calls preserve results and overwrite caller supplied thread identity",
       context do
    for {{modern, _protocol}, index} <- Enum.with_index(@protocols) do
      {pid, thread} = configured(context, modern)
      base = %{"threadId" => thread, "server" => "fixture", "tool" => "echo"}

      for {extra, arguments, is_error} <- [
            {%{}, nil, false},
            {%{"arguments" => nil, "_meta" => nil}, nil, false},
            {%{"arguments" => %{}}, %{}, false},
            {%{
               "arguments" => %{"message" => "λ", "toolError" => true},
               "_meta" => %{"threadId" => "spoofed", "source" => "synthetic-client"}
             }, %{"message" => "λ", "toolError" => true}, true}
          ] do
        assert call(pid, "mcpServer/tool/call", Map.merge(base, extra)) == %{
                 "content" => [
                   %{
                     "type" => "text",
                     "text" => "Synthetic direct MCP result\n",
                     "_meta" => %{"fixture" => "content-preserved"}
                   }
                 ],
                 "structuredContent" => %{"arguments" => arguments, "threadId" => thread},
                 "isError" => is_error,
                 "_meta" => %{"fixture" => %{"preserved" => true}}
               }
      end

      calls = requests(context, "tools/call") |> Enum.drop(index * 4)
      assert length(calls) == 4

      assert Enum.map(calls, &get_in(&1, ["params", "arguments"])) == [
               nil,
               nil,
               %{},
               %{"message" => "λ", "toolError" => true}
             ]

      assert Enum.all?(calls, &(get_in(&1, ["params", "_meta", "threadId"]) == thread))
      assert get_in(List.last(calls), ["params", "_meta", "source"]) == "synthetic-client"
      assert_no_turn(context, pid)
      assert :ok = Session.close(pid)
    end

    assert length(requests(context, "tools/call")) == 8
    assert negotiated_protocols(context) == Enum.map(@protocols, &elem(&1, 1))
  end

  test "direct tool protocol errors retain code message and data in both negotiated versions",
       context do
    for {modern, protocol} <- @protocols do
      {pid, thread} = configured(context, modern)
      base = %{"threadId" => thread, "server" => "fixture", "tool" => "echo"}

      assert upstream_error(
               pid,
               "mcpServer/tool/call",
               Map.put(base, "arguments", %{"protocolError" => true})
             ) == operation_error(-32043, "synthetic tool failure", protocol)

      assert upstream_error(pid, "mcpServer/tool/call", %{base | "server" => "missing"}) == %{
               "code" => -32603,
               "message" => "unknown MCP server 'missing'"
             }

      assert upstream_error(pid, "mcpServer/tool/call", %{base | "tool" => "absent"}) == %{
               "code" => -32601,
               "message" => "synthetic tool absent",
               "data" => %{"tool" => "absent"}
             }

      error = upstream_error(pid, "mcpServer/tool/call", %{base | "threadId" => @missing_thread})
      assert error["message"] =~ "thread not found"

      for extra <- [%{"arguments" => []}, %{"_meta" => "invalid"}] do
        error = upstream_error(pid, "mcpServer/tool/call", Map.merge(base, extra))
        assert error["code"] == -32603
        assert error["message"] =~ "must be a JSON object"
      end

      assert_no_turn(context, pid)
      assert :ok = Session.close(pid)
    end

    assert negotiated_protocols(context) ==
             Enum.map(@protocols, &elem(&1, 1))

    assert length(requests(context, "tools/call")) == 4
  end

  test "resource reads preserve text blob mime type and metadata with and without a thread",
       context do
    for {{modern, _protocol}, index} <- Enum.with_index(@protocols) do
      {pid, thread} = configured(context, modern)
      base = %{"server" => "fixture", "uri" => "fixture://contents"}

      for extra <- [
            %{},
            %{"threadId" => nil},
            %{"threadId" => thread},
            %{
              "threadId" => thread,
              "originCallId" => "ignored-for-local-server",
              "connectorId" => "synthetic-connector"
            }
          ] do
        assert call(pid, "mcpServer/resource/read", Map.merge(base, extra)) == %{
                 "contents" => [
                   %{
                     "uri" => "fixture://contents",
                     "mimeType" => "text/plain",
                     "text" => "Synthetic resource text\nλ",
                     "_meta" => %{"fixture" => %{"kind" => "text"}}
                   },
                   %{
                     "uri" => "fixture://contents",
                     "mimeType" => "application/octet-stream",
                     "blob" => Base.encode64(<<0, 1, 127, 128, 255>>),
                     "_meta" => %{"fixture" => %{"kind" => "blob"}}
                   }
                 ],
                 "originCallId" => nil
               }
      end

      reads = requests(context, "resources/read") |> Enum.drop(index * 4)
      assert length(reads) == 4
      assert Enum.all?(reads, &(get_in(&1, ["params", "uri"]) == "fixture://contents"))

      assert get_in(List.last(reads), ["params", "_meta", "x-codex-turn-metadata"]) == %{
               "mcp_request_meta" => %{"selected_connector_ids" => ["synthetic-connector"]}
             }

      assert_no_turn(context, pid)
      assert :ok = Session.close(pid)
    end

    assert length(requests(context, "resources/read")) == 8
    assert Enum.uniq(negotiated_protocols(context)) == Enum.map(@protocols, &elem(&1, 1))
  end

  test "resource protocol failures and scoping guards preserve native error boundaries",
       context do
    for {modern, protocol} <- @protocols do
      {pid, thread} = configured(context, modern)
      base = %{"server" => "fixture", "uri" => "fixture://error"}

      for extra <- [%{}, %{"threadId" => thread}] do
        params = Map.merge(base, extra)

        assert upstream_error(pid, "mcpServer/resource/read", params) ==
                 operation_error(-32042, "synthetic resource failure", protocol)

        assert upstream_error(pid, "mcpServer/resource/read", %{params | "server" => "missing"}) ==
                 %{"code" => -32603, "message" => "unknown MCP server 'missing'"}
      end

      assert upstream_error(
               pid,
               "mcpServer/resource/read",
               Map.put(base, "originCallId", "orphan")
             ) == %{"code" => -32600, "message" => "originCallId requires threadId"}

      assert upstream_error(
               pid,
               "mcpServer/resource/read",
               Map.put(base, "target", %{"connectorId" => "synthetic", "linkId" => nil})
             ) == %{
               "code" => -32600,
               "message" => "target requires codex_apps, a connectorId, and a real linkId or null"
             }

      error =
        upstream_error(pid, "mcpServer/resource/read", Map.put(base, "threadId", @missing_thread))

      assert error["message"] =~ "thread not found"
      assert_no_turn(context, pid)
      assert :ok = Session.close(pid)
    end

    assert length(requests(context, "resources/read")) == 4

    assert Enum.uniq(negotiated_protocols(context)) == Enum.map(@protocols, &elem(&1, 1))
  end

  defp configured(context, modern) do
    config = Path.join(context.fixture.codex_home, "config.toml")
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")
    journal = Path.join(context.root, "mcp-direct.jsonl")

    protocol_env =
      if modern, do: "env = { CODEX_MCP_PROTOCOL_VERSION = \"2026-07-28\" }", else: ""

    File.write!(
      config,
      context.base_config <>
        """

        [features]
        mcp_2026_07_28 = #{modern}
        [mcp_servers.fixture]
        command = #{JSON.encode!(python)}
        args = #{JSON.encode!([@script, "--journal", journal])}
        startup_timeout_sec = 10
        tool_timeout_sec = 10
        #{protocol_env}
        """
    )

    pid = start(context)
    {pid, thread(context, pid)}
  end

  defp requests(context, method) do
    context.root
    |> Path.join("mcp-direct.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
    |> Enum.filter(&(&1["method"] == method))
  end

  defp negotiated_protocols(context) do
    context.root
    |> Path.join("mcp-direct.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&JSON.decode!/1)
    |> Enum.flat_map(fn
      %{"method" => "initialize", "params" => %{"protocolVersion" => version}} ->
        [version]

      %{"method" => "server/discover", "params" => %{"_meta" => meta}} ->
        [meta["io.modelcontextprotocol/protocolVersion"]]

      _ ->
        []
    end)
  end

  defp operation_error(code, message, protocol),
    do: %{
      "code" => code,
      "message" => message,
      "data" => %{
        "protocolVersion" => protocol,
        "nested" => %{"values" => [1, nil]},
        "_meta" => %{"fixture" => "error-preserved"}
      }
    }

  defp assert_no_turn(context, pid) do
    assert ModelFixture.requests(context.fixture) == []
    assert {:ok, events} = Session.drain(pid)
    refute notification(events, "turn/started")
    refute notification(events, "item/mcpToolCall/progress")
    assert Session.status(pid).phase == :ready
  end
end
