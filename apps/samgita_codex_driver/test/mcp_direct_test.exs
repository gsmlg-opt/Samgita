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
             ) == operation_error(-32_043, "synthetic tool failure", protocol)

      assert upstream_error(pid, "mcpServer/tool/call", %{base | "server" => "missing"}) == %{
               "code" => -32_603,
               "message" => "unknown MCP server 'missing'"
             }

      assert upstream_error(pid, "mcpServer/tool/call", %{base | "tool" => "absent"}) == %{
               "code" => -32_601,
               "message" => "synthetic tool absent",
               "data" => %{"tool" => "absent"}
             }

      error = upstream_error(pid, "mcpServer/tool/call", %{base | "threadId" => @missing_thread})
      assert error["message"] =~ "thread not found"

      for extra <- [%{"arguments" => []}, %{"_meta" => "invalid"}] do
        error = upstream_error(pid, "mcpServer/tool/call", Map.merge(base, extra))
        assert error["code"] == -32_603
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

  test "resource reads omit absent and null optional fields while preserving distinct content URIs",
       context do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(context.binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    for {{modern, _protocol}, index} <- Enum.with_index(@protocols) do
      {pid, thread} = configured(context, modern)
      base = %{"server" => "fixture", "uri" => "fixture://optional-contents"}

      for extra <- [%{}, %{"threadId" => thread}] do
        result = call(pid, "mcpServer/resource/read", Map.merge(base, extra))

        # Each URI belongs to its returned content, independently of the request.
        # Native ResourceContent skips None instead of serializing optional nulls.
        assert result === %{
                 "contents" => [
                   %{
                     "uri" => "fixture://optional/text-omitted",
                     "text" => "Owned omitted text\nλ"
                   },
                   %{
                     "uri" => "fixture://optional/text-null",
                     "text" => "Owned null text\nλ"
                   },
                   %{"uri" => "fixture://optional/blob-omitted", "blob" => "AAF/gP8="},
                   %{"uri" => "fixture://optional/blob-null", "blob" => "AAF/gP8="}
                 ],
                 "originCallId" => nil
               }

        for item <- result["contents"] do
          refute Map.has_key?(item, "mimeType")
          refute Map.has_key?(item, "_meta")
          refute item["uri"] == base["uri"]
        end

        for item <- Enum.filter(result["contents"], &Map.has_key?(&1, "blob")) do
          assert Base.decode64!(item["blob"]) === <<0, 1, 127, 128, 255>>
        end
      end

      reads = requests(context, "resources/read") |> Enum.drop(index * 2)
      assert length(reads) == 2

      assert Enum.all?(
               reads,
               &(get_in(&1, ["params", "uri"]) == "fixture://optional-contents")
             )

      assert_no_turn(context, pid)

      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} =
               Session.status(pid)

      assert :ok = Session.close(pid)
    end

    assert length(requests(context, "resources/read")) == 4
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
                 operation_error(-32_042, "synthetic resource failure", protocol)

        assert upstream_error(pid, "mcpServer/resource/read", %{params | "server" => "missing"}) ==
                 %{"code" => -32_603, "message" => "unknown MCP server 'missing'"}
      end

      assert upstream_error(
               pid,
               "mcpServer/resource/read",
               Map.put(base, "originCallId", "orphan")
             ) == %{"code" => -32_600, "message" => "originCallId requires threadId"}

      assert upstream_error(
               pid,
               "mcpServer/resource/read",
               Map.put(base, "target", %{"connectorId" => "synthetic", "linkId" => nil})
             ) == %{
               "code" => -32_600,
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

  test "mixed resource normalization preserves order and recovers from an independent protocol error",
       context do
    assert Base.encode16(:crypto.hash(:sha256, File.read!(context.binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    File.write!(Path.join(context.root, "mcp-direct.jsonl"), "", [:exclusive])

    expected = %{
      "contents" => [
        %{
          "uri" => "fixture://bundle/repeated",
          "text" => "Owned text wins\nλ",
          "mimeType" => "",
          "_meta" => %{}
        },
        %{
          "uri" => "fixture://bundle/repeated",
          "blob" => "not_base64!",
          "_meta" => %{"fixture" => %{"values" => [0, false, nil, "λ"], "empty" => %{}}}
        },
        %{
          "uri" => "fixture://bundle/empty-text",
          "text" => "",
          "mimeType" => "text/plain"
        },
        %{
          "uri" => "fixture://bundle/empty-blob",
          "blob" => "",
          "mimeType" => "application/octet-stream"
        }
      ],
      "originCallId" => nil
    }

    denied = %{
      "code" => -32_042,
      "message" => "owned bundle denied",
      "data" => %{
        "fixture" => "normalization-bundle",
        "partial" => false,
        "nested" => %{"values" => [0, false, nil, "λ"]}
      }
    }

    uris = fn -> Enum.map(requests(context, "resources/read"), &get_in(&1, ["params", "uri"])) end

    for {{modern, protocol}, index} <- Enum.with_index(@protocols) do
      {pid, thread} = configured(context, modern)
      assert is_binary(thread) and byte_size(thread) > 0
      %{instance_id: instance, generation: generation} = Session.status(pid)

      # Establish the loaded runtime first. Threadless reads own a new MCP manager.
      for {binding, binding_index} <- Enum.with_index([%{"threadId" => thread}, %{}]) do
        previous = uris.()
        assert length(previous) == index * 8 + binding_index * 4

        params =
          Map.merge(%{"server" => "fixture", "uri" => "fixture://normalization-bundle"}, binding)

        # The literal oracle differs from the peer's dual-field and envelope input.
        assert call(pid, "mcpServer/resource/read", params) === expected
        assert uris.() === previous ++ ["fixture://normalization-bundle"]
        assert_normalization_ready(context, pid, instance, generation)
        negotiations = negotiated_protocols(context)

        error_id = "owned-bundle-error-#{index}-#{binding_index}"

        assert {:error,
                %SamgitaProtocolCodex.Error{
                  code: :upstream_error,
                  wire: %{"id" => ^error_id, "error" => ^denied} = error_wire
                }} =
                 Session.request(
                   pid,
                   "mcpServer/resource/read",
                   %{params | "uri" => "fixture://bundle-denied"},
                   id: error_id
                 )

        refute Map.has_key?(error_wire, "result")

        assert uris.() ===
                 previous ++ ["fixture://normalization-bundle", "fixture://bundle-denied"]

        assert_normalization_ready(context, pid, instance, generation)

        assert negotiated_protocols(context) ===
                 if(binding_index == 0, do: negotiations, else: negotiations ++ [protocol])

        assert call(pid, "mcpServer/resource/read", params) === expected

        assert uris.() ===
                 previous ++
                   [
                     "fixture://normalization-bundle",
                     "fixture://bundle-denied",
                     "fixture://normalization-bundle"
                   ]

        assert_normalization_ready(context, pid, instance, generation)

        assert call(pid, "mcpServer/resource/read", %{params | "uri" => "fixture://empty-bundle"}) ===
                 %{"contents" => [], "originCallId" => nil}

        assert uris.() ===
                 previous ++
                   [
                     "fixture://normalization-bundle",
                     "fixture://bundle-denied",
                     "fixture://normalization-bundle",
                     "fixture://empty-bundle"
                   ]

        assert_normalization_ready(context, pid, instance, generation)

        assert negotiated_protocols(context) ===
                 if(binding_index == 0,
                   do: negotiations,
                   else: negotiations ++ List.duplicate(protocol, 3)
                 )
      end

      assert requests(context, "tools/call") == []
      assert_no_turn(context, pid)
      assert :ok = Session.close(pid)
    end

    assert length(requests(context, "resources/read")) == 16
    assert Enum.uniq(negotiated_protocols(context)) == Enum.map(@protocols, &elem(&1, 1))
  end

  defp assert_normalization_ready(context, pid, instance, generation) do
    assert ModelFixture.requests(context.fixture) == []
    assert File.ls!(context.fixture.workspace) == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             String.starts_with?(event.wire["method"] || "", ["turn/", "item/"])
           end)

    assert %{
             phase: :ready,
             instance_id: ^instance,
             generation: ^generation,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
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
