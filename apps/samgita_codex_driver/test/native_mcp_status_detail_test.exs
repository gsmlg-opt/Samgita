defmodule SamgitaCodexDriver.NativeMcpStatusDetailTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @peer Path.expand("support/native_mcp_status_catalog_fixture.py", __DIR__)
  @peer_sha "bc363da3756359be7eeb9b03024c3921e92b7545cdbd9cb3ced9dc5b6d6edb50"
  @projection %{
    "name" => "owned_detail",
    "resources" => [
      %{
        "uri" => "fixture://status-detail/resource",
        "name" => "owned-resource",
        "title" => "Resource λ",
        "description" => "Fixed catalog resource",
        "mimeType" => "text/plain",
        "size" => 37
      }
    ],
    "resourceTemplates" => [
      %{
        "uriTemplate" => "fixture://status-detail/{key}",
        "name" => "owned-template",
        "title" => "Template λ",
        "description" => "Fixed catalog template",
        "mimeType" => "text/plain"
      }
    ]
  }

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next.capture, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Capture original payloads before Session decoding; never reconstruct replies.
    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 64 and size <= 65_536 and ledger.bytes + size <= 524_288 do
          entry = %{direction: direction, encoded: encoded}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@peer)) === @peer_sha
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-mcp-detail-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    journal = Path.join(root, "catalog.jsonl")
    File.write!(journal, "", [:exclusive])

    config = """
    check_for_update_on_startup = false
    [memories]
    generate_memories = false
    use_memories = false
    [analytics]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    memories = false
    shell_snapshot = false
    mcp_2026_07_28 = false
    [mcp_servers.owned_detail]
    command = #{JSON.encode!(python)}
    args = #{JSON.encode!(["-B", @peer, "--journal", journal])}
    startup_timeout_sec = 10
    tool_timeout_sec = 10
    """

    path = Path.join(root, "codex/config.toml")
    File.write!(path, config, [:exclusive])
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    %{
      binary: Path.expand(binary),
      root: root,
      workspace: Path.join(root, "workspace"),
      journal: journal,
      config_path: path,
      config: config,
      capture: capture
    }
  end

  test "native MCP status omitted null and full detail each discover nonempty resource catalogs",
       ctx do
    session = start(ctx)

    # Pinned v2/mcp.rs detail:Option plus mcp_processor.rs:394 defaults both
    # absent and null to Full. The threadless producer uses an owned eager MCP
    # connection per request; no thread, model, provider or tool call is needed.
    cases = [
      {"omitted", %{"serverName" => "owned_detail"}},
      {"null", %{"serverName" => "owned_detail", "detail" => nil}},
      {"full", %{"serverName" => "owned_detail", "detail" => "full"}},
      {"null-repeat", %{"serverName" => "owned_detail", "detail" => nil}}
    ]

    for {{label, params}, ordinal} <- Enum.with_index(cases, 1) do
      response = request(ctx, session.pid, "detail-" <> label, "mcpServerStatus/list", params)
      assert %{"data" => [row], "nextCursor" => nil} = response["result"]

      # Fixed literal oracle is independent of peer replies and observed output.
      # Other status fields are deliberately outside this ordinary check.
      assert Map.take(row, Map.keys(@projection)) === @projection
      await_catalogs(ctx, ordinal, now() + 5_000)
      assert_catalogs(ctx, ordinal)
      assert File.read!(ctx.config_path) === ctx.config
      assert File.ls!(ctx.workspace) === []
    end

    assert_quiet(session.pid)
    assert :ok = StdioSessionFixture.close(session.pid, session.connection)
    await_peers_gone(ctx, now() + 5_000)
    assert_catalogs(ctx, 4)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 32,
               max_event_bytes: 131_072,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => Path.join(ctx.root, "home"),
                      "CODEX_HOME" => Path.join(ctx.root, "codex"),
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => "/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    on_exit(fn -> cleanup(ctx, pid, connection, identity) end)
    id = "detail-initialize"
    info = %{"name" => "owned_mcp_status_detail", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    diagnostics = request(ctx, pid, "detail-diagnostics", "server/diagnostics", %{})
    native = diagnostics["result"]["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection}
  end

  defp request(ctx, pid, id, method, params) do
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => _} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    response
  end

  defp assert_exchange(ctx, wire, response) do
    records = Agent.get(ctx.capture, &Enum.reverse(&1.records))

    selected =
      Enum.filter(records, fn record -> JSON.decode!(record.encoded)["id"] === wire["id"] end)

    assert [sent, received] = selected
    assert sent.direction === :out and sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.direction === :in and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp journal(ctx) do
    raw = File.read!(ctx.journal)
    assert byte_size(raw) <= 131_072
    rows = raw |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert length(rows) <= 128
    refute Enum.any?(rows, &(&1["event"] === "fatal"))
    rows
  end

  defp await_catalogs(ctx, count, deadline) do
    replies = Enum.filter(journal(ctx), &(&1["event"] === "reply"))

    cond do
      length(replies) === count * 4 ->
        :ok

      now() >= deadline ->
        flunk("Owned catalog reply journal deadline")

      true ->
        receive do
        after
          10 -> await_catalogs(ctx, count, deadline)
        end
    end
  end

  defp assert_catalogs(ctx, count) do
    rows = journal(ctx)
    starts = Enum.filter(rows, &(&1["event"] === "started"))
    assert length(starts) === count
    assert length(Enum.uniq_by(starts, & &1["pid"])) === count

    for start <- starts do
      owned = Enum.filter(rows, &(&1["pid"] === start["pid"]))
      requests = Enum.filter(owned, &(&1["event"] === "request"))
      replies = Enum.filter(owned, &(&1["event"] === "reply"))

      assert Enum.sort(Enum.map(requests, & &1["request"]["method"])) ===
               ["initialize", "resources/list", "resources/templates/list", "tools/list"]

      assert Enum.sort(Enum.map(replies, & &1["method"])) ===
               ["initialize", "resources/list", "resources/templates/list", "tools/list"]

      for request <- requests do
        assert [reply] = Enum.filter(replies, &(&1["reply"]["id"] === request["request"]["id"]))
        assert reply["method"] === request["request"]["method"]
        assert Map.has_key?(reply["reply"], "result")
      end

      assert [%{"method" => "notifications/initialized"}] =
               Enum.filter(owned, &(&1["event"] === "notification"))
    end
  end

  defp assert_quiet(pid) do
    assert {:ok, events} = Session.drain(pid, 32)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or
               method === "error" or String.starts_with?(method, "thread/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp cleanup(ctx, pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
    await_peers_gone(ctx, now() + 5_000)
  end

  defp await_peers_gone(ctx, deadline) do
    pids = for row <- journal(ctx), row["event"] === "started", do: row["pid"]

    cond do
      Enum.all?(pids, &(not File.exists?("/proc/#{&1}"))) ->
        :ok

      now() >= deadline ->
        flunk("Owned catalog dependency reaping deadline")

      true ->
        receive do
        after
          10 -> await_peers_gone(ctx, deadline)
        end
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
