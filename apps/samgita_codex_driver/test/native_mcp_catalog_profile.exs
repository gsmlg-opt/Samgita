defmodule SamgitaCodexDriver.NativeMcpCatalogProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  import TurnFixture, except: [setup: 1]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/mcp_catalog_fixture.py", __DIR__)
  @native_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @fixture_sha "b8b85e329652efd8124577f79980a0f6919359af502e52863242557dd5a2dbc7"
  @protocols [{false, "2025-06-18"}, {true, "2026-07-28"}]

  # Pinned source 83086188ae0614bd882818ff1aa23f3194962012:
  # codex-mcp/connection_manager/resources.rs:38-128 drops an entire failed collection.
  # codex-mcp/rmcp_client.rs:110-116,845-875 strips reserved regular-server tool metadata.
  # protocol/src/mcp.rs:328-346,390-533 projects templates and lossy resource i64 sizes.
  # Resources/templates are joined concurrently: only per-method ordering is asserted.
  # Connected with resources:[] on a protocol error is upstream behavior, not health.

  setup context do
    context = TurnFixture.setup(context)
    assert hash(File.read!(context.binary)) == @native_sha
    assert hash(File.read!(@script)) == @fixture_sha
    config = File.read!(Path.join(context.fixture.codex_home, "config.toml"))
    Map.put(context, :base_config, config)
  end

  test "native rich catalog consumes backend pages and recovers without reconnect or execution",
       context do
    journals =
      for {modern, protocol} <- @protocols do
        {pid, thread, journal, control} = configured(context, modern, protocol)
        %{instance_id: instance, generation: generation} = Session.status(pid)
        selected = %{"threadId" => thread, "serverName" => "catalog", "detail" => "full"}
        expected = %{"data" => [expected_server()], "nextCursor" => nil}

        assert call(pid, "mcpServerStatus/list", selected) === expected
        assert_catalog_requests(journal, protocol, 1)
        assert_ready(context, pid, instance, generation)

        short = expected_server() |> Map.put("resources", []) |> Map.put("resourceTemplates", [])

        assert call(pid, "mcpServerStatus/list", %{selected | "detail" => "toolsAndAuthOnly"}) ===
                 %{"data" => [short], "nextCursor" => nil}

        assert_catalog_requests(journal, protocol, 1)
        assert_ready(context, pid, instance, generation)

        set_mode(control, "reject-resource-page2")
        missing_resources = Map.put(expected_server(), "resources", [])

        # No resourceError field exists in the pinned native status DTO. The exact
        # successful row must omit partial page one and keep toolsError:null.
        assert call(pid, "mcpServerStatus/list", selected) ===
                 %{"data" => [missing_resources], "nextCursor" => nil}

        assert_catalog_requests(journal, protocol, 2)

        assert error_replies(journal) === [
                 %{
                   "code" => -32_042,
                   "message" => "owned resource page rejected",
                   "data" => %{
                     "fixture" => "rich-catalog",
                     "page" => "resource:2",
                     "retryable" => false
                   }
                 }
               ]

        assert_ready(context, pid, instance, generation)
        set_mode(control, "good")
        assert call(pid, "mcpServerStatus/list", selected) === expected
        assert_catalog_requests(journal, protocol, 3)
        assert length(error_replies(journal)) == 1
        assert_ready(context, pid, instance, generation)
        assert :ok = Session.close(pid)
        preserve_evidence(journal, protocol)
        journal
      end

    rows = Enum.flat_map(journals, &journal/1)
    assert length(requests(rows, "tools/list")) == 4
    assert length(requests(rows, "resources/list")) == 12
    assert length(requests(rows, "resources/templates/list")) == 12
    assert Enum.map(negotiations(rows), & &1["protocol"]) == Enum.map(@protocols, &elem(&1, 1))
  end

  defp configured(context, modern, protocol) do
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")
    journal = Path.join(context.root, "catalog-#{protocol}.jsonl")
    control = Path.join(context.root, "catalog-#{protocol}.mode")
    # Creation precedes asynchronous MCP startup; missing journals must never be
    # mistaken for evidence that the peer received no requests.
    File.write!(journal, "", [:exclusive])
    File.write!(control, "good", [:exclusive])

    protocol_env =
      if modern, do: "env = { CODEX_MCP_PROTOCOL_VERSION = \"2026-07-28\" }", else: ""

    File.write!(
      Path.join(context.fixture.codex_home, "config.toml"),
      context.base_config <>
        """

        [features]
        mcp_2026_07_28 = #{modern}
        [mcp_servers.catalog]
        command = #{JSON.encode!(python)}
        args = #{JSON.encode!(["-B", @script, "--journal", journal, "--control", control])}
        startup_timeout_sec = 10
        tool_timeout_sec = 10
        #{protocol_env}
        """
    )

    pid = start(context)
    {pid, thread(context, pid), journal, control}
  end

  defp set_mode(path, value) do
    temporary = path <> ".next"
    File.write!(temporary, value, [:exclusive])
    File.rename!(temporary, path)
  end

  defp preserve_evidence(journal, protocol) do
    if destination = System.get_env("CODEX_CATALOG_EVIDENCE_DIR") do
      File.mkdir_p!(destination)
      File.cp!(journal, Path.join(destination, "catalog-#{protocol}.jsonl"))
    end
  end

  defp assert_catalog_requests(path, protocol, collections) do
    rows = journal(path)
    assert [%{"protocol" => ^protocol}] = negotiations(rows)

    for {method, page, count} <- [
          {"tools/list", "tool:2", 1},
          {"resources/list", "resource:2", collections},
          {"resources/templates/list", "template:2", collections}
        ] do
      calls = requests(rows, method)
      expected_cursors = List.duplicate([nil, page], count) |> List.flatten()
      expected_presence = List.duplicate([false, true], count) |> List.flatten()
      assert Enum.map(calls, & &1["cursor"]) === expected_cursors
      assert Enum.map(calls, & &1["cursorPresent"]) === expected_presence
      assert Enum.all?(calls, &(&1["protocol"] == protocol))
      replies = Enum.filter(rows, &(&1["event"] == "reply" and &1["method"] == method))
      assert Enum.map(replies, & &1["id"]) === Enum.map(calls, & &1["id"])
      assert Enum.map(replies, & &1["cursor"]) === Enum.map(calls, & &1["cursor"])
    end

    refute Enum.any?(rows, &(&1["event"] == "fatal"))

    for row <- Enum.filter(rows, &(&1["event"] == "request")) do
      assert row["method"] in [
               "initialize",
               "server/discover",
               "notifications/initialized",
               "tools/list",
               "resources/list",
               "resources/templates/list",
               "ping"
             ]
    end
  end

  defp assert_ready(context, pid, instance, generation) do
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

  defp journal(path) do
    raw = File.read!(path)
    assert byte_size(raw) <= 262_144
    rows = raw |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert length(rows) <= 512
    rows
  end

  defp requests(rows, method),
    do: Enum.filter(rows, &(&1["event"] == "request" and &1["method"] == method))

  defp negotiations(rows),
    do:
      Enum.filter(
        rows,
        &(&1["event"] == "request" and &1["method"] in ["initialize", "server/discover"])
      )

  defp error_replies(path) do
    for row <- journal(path), row["event"] == "reply" and row["outcome"] == "error" do
      assert row["method"] == "resources/list" and row["cursor"] == "resource:2"
      row["error"]
    end
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  # Literal independent native oracle: never decode peer pages to construct this.
  defp expected_server do
    %{
      "name" => "catalog",
      "runtimeStatus" => "connected",
      "pluginId" => nil,
      "httpOrigin" => nil,
      "serverInfo" => %{
        "name" => "owned-rich-catalog",
        "title" => "Owned catalog λ",
        "version" => "1.0.0",
        "description" => "Read-only synthetic catalog",
        "websiteUrl" => "https://synthetic.invalid/catalog",
        "icons" => [expected_icon()]
      },
      "serverCapabilities" => %{
        "tools" => %{"listChanged" => false},
        "resources" => %{"subscribe" => false, "listChanged" => false}
      },
      "tools" => %{
        "inspect.catalog" => %{
          "name" => "inspect.catalog",
          "title" => "Inspect catalog λ",
          "description" => "Metadata only; never invoked",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"key" => %{"type" => "string"}}
          },
          "outputSchema" => %{
            "type" => "object",
            "properties" => %{"ok" => %{"type" => "boolean"}},
            "required" => ["ok"]
          },
          "annotations" => %{
            "title" => "Annotation title",
            "readOnlyHint" => true,
            "destructiveHint" => false,
            "idempotentHint" => true,
            "openWorldHint" => false
          },
          "icons" => [expected_icon()],
          "_meta" => %{
            "custom" => %{"connector_id" => "nested-data", "values" => [0, false, nil, "λ"]},
            "connectorFutureField" => "ordinary-data"
          }
        },
        "plain.catalog" => %{"name" => "plain.catalog", "inputSchema" => %{}}
      },
      "toolsError" => nil,
      "resources" => [
        %{
          "uri" => "fixture://catalog/rich",
          "name" => "rich",
          "title" => "Rich resource λ",
          "description" => "Owned resource metadata",
          "mimeType" => "text/plain",
          "size" => 5_000_000_000,
          "icons" => [expected_icon()],
          "_meta" => %{
            "connector_id" => "ordinary-resource-data",
            "fixture" => %{"values" => [0, false, nil, "λ"]}
          },
          "annotations" => expected_annotations()
        },
        %{
          "uri" => "fixture://catalog/overflow",
          "name" => "overflow",
          "title" => "Unsigned overflow stays listed"
        }
      ],
      "resourceTemplates" => [
        %{
          "uriTemplate" => "fixture://catalog/{key}",
          "name" => "rich-template",
          "title" => "Rich template λ",
          "description" => "Owned template description",
          "mimeType" => "text/plain",
          "annotations" => expected_annotations()
        },
        %{"uriTemplate" => "fixture://catalog/plain/{key}", "name" => "plain-template"}
      ],
      "authStatus" => "unsupported"
    }
  end

  defp expected_icon do
    %{
      "src" => "fixture://catalog/icon",
      "mimeType" => "image/png",
      "sizes" => ["16x16"],
      "theme" => "dark"
    }
  end

  defp expected_annotations do
    %{
      "audience" => ["assistant", "user"],
      "priority" => 0.5,
      "lastModified" => "2026-10-25T00:00:00Z"
    }
  end
end
