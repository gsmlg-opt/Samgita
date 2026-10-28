defmodule SamgitaCodexDriver.NativeOrdinaryMcpResourceTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @peer Path.expand("../../../scripts/codex/ordinary_mcp_resource_fixture.py", __DIR__)
  @peer_sha "db73b73e84a4ca14dbef753d93045f765d71f7240d543344495de97c5a0540eb"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/McpResourceReadParams.json" =>
      "7ff0e4de6d70bd1c86b6d32ae781c9a841fee4d2e6d11eff8d8d0f224f7ad801",
    "v2/McpResourceReadResponse.json" =>
      "a48af749203ed3307414750d5070facb5ae6ef8b00253f1cfd9a8124bdfcfe41"
  }
  @id_node_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_node_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @server "owned_resource_940"
  @uri "fixture://owned-resource-940"
  @id "owned-resource-read-940"
  @text "Owned ordinary resource text λ🙂\nSecond line β.\n"
  @contents [
    %{
      "uri" => @uri,
      "mimeType" => "text/plain",
      "text" => @text,
      "_meta" => %{"owned" => %{"kind" => "text", "marker" => "resource-940"}}
    },
    %{
      "uri" => @uri,
      "mimeType" => "application/octet-stream",
      "blob" => "AAF/gP8=",
      "_meta" => %{"owned" => %{"kind" => "blob", "values" => [0, false, nil]}}
    }
  ]

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
          case record(next, :out, encoded) do
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
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8_192, else: 65_536

        if length(ledger.frames) < 64 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}
          {:ok, %{frames: ledger.frames ++ [frame], bytes: ledger.bytes + size}}
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
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-ordinary-resource-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    home = Path.join(root, "home")
    codex_home = Path.join(root, "codex")
    workspace = Path.join(root, "workspace")
    bin = Path.join(root, "bin")
    Enum.each([home, codex_home, workspace, bin], &File.mkdir!/1)
    File.cp!("/bin/sh", Path.join(bin, "sh"))
    # This socket serves no HTTP or model output. An accepted connection is an
    # unexpected ordinary inference/network effect, without inspecting bytes.
    assert {:ok, model_trap} =
             :gen_tcp.listen(0, [
               :binary,
               active: false,
               ip: {127, 0, 0, 1},
               reuseaddr: true,
               backlog: 1
             ])

    on_exit(fn -> :gen_tcp.close(model_trap) end)
    assert {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(model_trap)
    unused_url = "http://127.0.0.1:#{port}"
    journal = Path.join(root, "resource-peer-journal.json")
    File.write!(journal, JSON.encode!(%{"events" => []}), [:exclusive])
    catalog = Path.join(codex_home, "models.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "mock-model",
            "display_name" => "Unused owned ordinary local model",
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{
              "instructions_template" => "No model work in this resource profile."
            },
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    config = Path.join(codex_home, "config.toml")

    File.write!(config, """
    model = "mock-model"
    model_provider = "unused_owned"
    model_catalog_json = #{JSON.encode!(catalog)}
    approval_policy = "never"
    sandbox_mode = "danger-full-access"
    cli_auth_credentials_store = "ephemeral"
    check_for_update_on_startup = false
    allow_login_shell = false
    web_search = "disabled"
    chatgpt_base_url = #{JSON.encode!(unused_url)}
    openai_base_url = #{JSON.encode!(unused_url <> "/v1")}
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    codex_hooks = false
    shell_snapshot = false
    memories = false
    mcp_2026_07_28 = false
    [memories]
    generate_memories = false
    use_memories = false
    [analytics]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [model_providers.unused_owned]
    name = "Unused owned ordinary provider"
    base_url = #{JSON.encode!(unused_url <> "/v1")}
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    [mcp_servers.#{@server}]
    command = #{JSON.encode!(python)}
    args = #{JSON.encode!(["-B", @peer, "--journal", journal])}
    startup_timeout_sec = 5
    tool_timeout_sec = 5
    """)

    paths = [@peer, config, catalog | Enum.map(Map.keys(@schemas), &schema_path/1)]
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    %{
      binary: binary,
      root: root,
      home: home,
      codex_home: codex_home,
      workspace: workspace,
      bin: bin,
      journal: journal,
      model_trap: model_trap,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native threadless MCP resource read preserves its physical request id and real peer content",
       ctx do
    native = start(ctx)
    assert_empty_loaded(ctx, native.pid)
    assert peer_events(ctx) === []
    assert_controls(ctx)
    params = %{"server" => @server, "uri" => @uri}
    wire = %{"id" => @id, "method" => "mcpServer/resource/read", "params" => params}
    assert :ok = Schema.validate(schema("v2/McpResourceReadParams.json"), params, max_depth: 32)
    result = call(ctx, native.pid, wire)
    assert result === %{"contents" => @contents, "originCallId" => nil}
    assert :ok = Schema.validate(schema("v2/McpResourceReadResponse.json"), result, max_depth: 32)
    assert :ok = Schema.validate_result(:server_response, "mcpServer/resource/read", result)
    assert Base.decode64!(Enum.at(result["contents"], 1)["blob"]) === <<0, 1, 127, 128, 255>>
    assert_physical_owner(ctx)
    assert_empty_loaded(ctx, native.pid)
    assert_controls(ctx)
    assert_idle(native.pid)
    close_native(native)
    assert_native_inventory(ctx)
    assert_peer_inventory(ctx, native.native)
    assert_controls(ctx)
    assert_no_model_connection(ctx.model_trap)
    closed_journal = snapshot(ctx.journal)
    # No replay, second read, peer restart or model/turn/tool invocation.
    assert peer_events(ctx) |> Enum.count(&(&1["event"] === "started")) === 1
    assert snapshot(ctx.journal) === closed_journal
  end

  defp assert_physical_owner(ctx) do
    assert [sent] = Enum.filter(outgoing(ctx), &(&1.wire["method"] === "mcpServer/resource/read"))
    assert sent.wire["id"] === @id and byte_size(sent.encoded) <= 4_096
    document = schema("ClientRequest.json")
    variants = Map.fetch!(document, "oneOf")

    assert [selected] =
             Enum.filter(
               variants,
               &(get_in(&1, ["properties", "method", "enum"]) === ["mcpServer/resource/read"])
             )

    assert selected === Enum.at(variants, 133)
    node = selected |> Map.fetch!("properties") |> Map.fetch!("id")
    assert node === %{"$ref" => "#/definitions/RequestId"}
    assert JSON.decode!(@id_node_bytes) === node
    assert hash(@id_node_bytes) === @id_node_sha
    definitions = Map.fetch!(document, "definitions")

    assert Map.fetch!(definitions, "RequestId") === %{
             "anyOf" => [
               %{"type" => "string"},
               %{"format" => "int64", "type" => "integer"}
             ]
           }

    assert :ok = Schema.validate(Map.put(node, "definitions", definitions), sent.wire["id"])

    assert :ok =
             Schema.validate(Map.put(selected, "definitions", definitions), sent.wire,
               max_depth: 32
             )

    assert :ok = Schema.validate(document, sent.wire, max_depth: 32)
  end

  defp assert_peer_inventory(ctx, native) do
    events = peer_events(ctx)
    assert [started] = Enum.filter(events, &(&1["event"] === "started"))
    peer = Map.fetch!(started, "pid")
    assert is_integer(peer) and peer > 0
    assert started["parent"] === native
    assert started["script"] === @peer and started["lifetime_seconds"] === 20

    assert File.read!(ctx.journal <> ".owner") |> JSON.decode!() === %{
             "pid" => peer,
             "parent" => native
           }

    assert [closed] = Enum.filter(events, &(&1["event"] === "closed"))
    assert closed["pid"] === peer and closed["reason"] in ["eof", "signal:15"]
    assert closed["messages"] === 4

    assert closed["methods"] === %{
             "initialize" => 1,
             "notifications/initialized" => 1,
             "tools/list" => 1,
             "resources/read" => 1
           }

    assert Enum.all?(events, &(&1["event"] in ~w(started wire closed)))
    refute File.exists?("/proc/#{peer}")
    wires = Enum.filter(events, &(&1["event"] === "wire"))
    assert length(wires) === 7
    incoming = peer_wires(wires, "in")
    outgoing = peer_wires(wires, "out")

    assert Enum.map(incoming, & &1["method"]) ===
             ~w(initialize notifications/initialized tools/list resources/read)

    assert Enum.map(outgoing, & &1["id"]) ===
             incoming |> Enum.filter(&Map.has_key?(&1, "id")) |> Enum.map(& &1["id"])

    assert Enum.all?(incoming ++ outgoing, &(&1["jsonrpc"] === "2.0"))
    assert Enum.at(incoming, 0)["params"]["protocolVersion"] === "2025-06-18"

    assert Enum.at(outgoing, 0)["result"] === %{
             "protocolVersion" => "2025-06-18",
             "capabilities" => %{"resources" => %{}, "tools" => %{}},
             "serverInfo" => %{"name" => "owned-ordinary-resource", "version" => "940"}
           }

    assert Enum.at(outgoing, 1)["result"] === %{"tools" => []}
    assert Enum.at(incoming, 3)["params"]["uri"] === @uri
    assert Enum.at(outgoing, 2)["result"] === %{"contents" => @contents}
  end

  defp peer_wires(wires, direction) do
    wires
    |> Enum.filter(&(&1["direction"] === direction))
    |> Enum.map(fn event ->
      raw = Base.decode64!(event["raw_base64"])
      assert byte_size(raw) <= 16_384 and String.ends_with?(raw, "\n")
      JSON.decode!(raw)
    end)
  end

  defp start(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
      "-c",
      "features.plugins=false",
      "-c",
      "features.recommended_plugins=false",
      "app-server",
      "--listen",
      "stdio://"
    ]

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.home,
                      "CODEX_HOME" => ctx.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_COLOR" => "1",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_mcp_resource", "version" => "940"}
    caps = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => caps}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, caps, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] = Enum.filter(outgoing(ctx), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(incoming(ctx), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
    assert response["id"] === wire["id"]
  end

  defp assert_native_inventory(ctx) do
    assert Enum.map(outgoing(ctx), & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list mcpServer/resource/read thread/loaded/list)

    requests = Enum.filter(outgoing(ctx), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 5 and length(Enum.uniq(ids)) === 5
    responses = Enum.filter(incoming(ctx), &Map.has_key?(&1.wire, "id"))
    assert length(responses) === 5
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    for frame <- Enum.reject(incoming(ctx), &Map.has_key?(&1.wire, "id")) do
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
      assert is_integer(frame.wire["emittedAtMs"]) and frame.wire["emittedAtMs"] > 0
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire

      assert :ok =
               Schema.validate_notification(
                 :server_notification,
                 frame.wire["method"],
                 frame.wire["params"],
                 experimental: true
               )

      refute String.starts_with?(frame.wire["method"], ["thread/", "turn/", "item/"])
    end
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.ls!(ctx.workspace) === []

    for directory <- ~w(sessions archived_sessions) do
      path = Path.join(ctx.codex_home, directory)

      assert path
             |> Path.join("**/*")
             |> Path.wildcard(match_dot: true)
             |> Enum.filter(&File.regular?/1) === []
    end
  end

  defp assert_no_model_connection(listener) do
    case :gen_tcp.accept(listener, 0) do
      {:error, :timeout} ->
        :ok

      {:ok, socket} ->
        :gen_tcp.close(socket)
        flunk("Unexpected ordinary model/startup connection")

      other ->
        flunk("Owned loopback observation failed: #{inspect(other)}")
    end
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert {:ok, []} = Session.drain(pid, 128)
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp peer_events(ctx) do
    bytes = snapshot(ctx.journal).bytes
    assert byte_size(bytes) <= 131_072
    events = JSON.decode!(bytes)["events"]
    assert is_list(events) and length(events) <= 32
    events
  end

  defp outgoing(ctx), do: frames(ctx, :out)
  defp incoming(ctx), do: frames(ctx, :in)

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: schema_path(name) |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-resource-control-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
