defmodule SamgitaCodexDriver.NativeOrdinaryInitializeExtensions219Test do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @peer Path.expand("../../../scripts/codex/ordinary_initialize_extensions_fixture.py", __DIR__)
  @peer_sha "0fd5100f8f5340439b5b1a50c65c4a3cad895fc9f038c90941889826f4a32fb2"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/McpResourceReadParams.json" =>
      "7ff0e4de6d70bd1c86b6d32ae781c9a841fee4d2e6d11eff8d8d0f224f7ad801",
    "v2/McpResourceReadResponse.json" =>
      "a48af749203ed3307414750d5070facb5ae6ef8b00253f1cfd9a8124bdfcfe41"
  }
  @extensions_node_bytes """
  {
    "additionalProperties": true,
    "description": "MCP extension settings declared by the app-server client.",
    "type": [
      "object",
      "null"
    ]
  }
  """
  @extensions_node_sha "5846294feadb997908d3b5cf4367981f19d988cbc47a934b9da80bae04952793"
  @extensions %{
    "io.modelcontextprotocol/ui" => %{
      "mimeTypes" => ["text/html;profile=mcp-app"],
      "ownedDescriptor" => %{"label" => "Owned descriptor λ🙂", "revision" => 1}
    }
  }
  @initialize_id 219_001
  @server "owned_ext_219"
  @uri "fixture://extension-219/data"
  @id "owned-extension-219-resource-read"
  @text "Owned extension219 resource λ🙂\nDescriptor observed by the actual peer.\n"
  @contents [
    %{
      "uri" => @uri,
      "mimeType" => "text/plain",
      "text" => @text
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
        "owned-initialize-extensions-219-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    cleanup = :atomics.new(1, [])

    on_exit(fn ->
      assert :atomics.get(cleanup, 1) in [0, 2],
             "Owned cleanup unconfirmed; retaining descriptor fixture #{root}"

      File.rm_rf!(root)
    end)

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
    journal = Path.join(root, "extension219-peer-journal.json")
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
              "instructions_template" => "No model work in this descriptor profile."
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
      cleanup: cleanup,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native initialize extensions reach the real thread-bound MCP peer unchanged",
       ctx do
    native = start(ctx)
    assert_controls(ctx)

    started =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "unused_owned",
        "cwd" => ctx.workspace,
        "ephemeral" => true
      })

    thread = Map.fetch!(Map.fetch!(started, "thread"), "id")
    assert is_binary(thread) and byte_size(thread) in 1..128
    assert started["cwd"] === ctx.workspace
    await_thread_created(ctx, native.pid, thread, System.monotonic_time(:millisecond) + 5_000, 64)
    # The thread runtime carries this initialized connection's MCP extensions;
    # the threadless collector is a separate runtime and cannot qualify219.
    params = %{"threadId" => thread, "server" => @server, "uri" => @uri}
    wire = %{"id" => @id, "method" => "mcpServer/resource/read", "params" => params}
    assert :ok = Schema.validate(schema("v2/McpResourceReadParams.json"), params, max_depth: 32)
    result = call(ctx, native.pid, wire)
    assert result === %{"contents" => @contents, "originCallId" => nil}
    assert :ok = Schema.validate(schema("v2/McpResourceReadResponse.json"), result, max_depth: 32)
    assert :ok = Schema.validate_result(:server_response, "mcpServer/resource/read", result)
    assert_physical_owner(ctx)
    assert_controls(ctx)
    assert_idle(native.pid)
    close_native(native)
    assert_native_inventory(ctx, thread)
    assert_peer_inventory(ctx, native.native)
    assert_controls(ctx)
    assert_no_model_connection(ctx.model_trap)
    closed_journal = snapshot(ctx.journal)
    # No replay, second read, peer restart or model/turn/tool invocation.
    assert peer_events(ctx) |> Enum.count(&(&1["event"] === "started")) === 1
    assert snapshot(ctx.journal) === closed_journal
  end

  defp assert_physical_owner(ctx) do
    assert [sent] = Enum.filter(outgoing(ctx), &(&1.wire["method"] === "initialize"))
    assert sent.wire["id"] === @initialize_id and byte_size(sent.encoded) <= 4_096
    actual = sent.wire["params"]["capabilities"]["extensions"]
    assert actual === @extensions
    document = schema("ClientRequest.json")
    node = get_in(document, ["definitions", "InitializeCapabilities", "properties", "extensions"])
    assert JSON.decode!(@extensions_node_bytes) === node
    assert hash(@extensions_node_bytes) === @extensions_node_sha
    assert :ok = Schema.validate(node, actual, max_depth: 32)
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
    assert Enum.at(incoming, 0)["params"]["capabilities"]["extensions"] === @extensions
    request_ids = incoming |> Enum.filter(&Map.has_key?(&1, "id")) |> Enum.map(& &1["id"])
    assert Enum.all?(request_ids, &(is_integer(&1) or is_binary(&1)))
    assert length(Enum.uniq(request_ids)) === 3

    for {request, response} <- Enum.zip(Enum.filter(incoming, &Map.has_key?(&1, "id")), outgoing) do
      assert response["id"] === request["id"]
    end

    assert Enum.at(outgoing, 0)["result"] === %{
             "protocolVersion" => "2025-06-18",
             "capabilities" => %{"resources" => %{}, "tools" => %{}},
             "serverInfo" => %{"name" => "owned-extension-219", "version" => "1"}
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
    args = NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"])

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
    :atomics.put(ctx.cleanup, 1, 1)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      :atomics.put(ctx.cleanup, 1, 2)
    end)

    id = @initialize_id
    info = %{"name" => "owned_extension_219", "version" => "0.1.0"}
    caps = %{"experimentalApi" => true, "extensions" => @extensions}

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

  defp assert_native_inventory(ctx, thread) do
    assert Enum.map(outgoing(ctx), & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/start mcpServer/resource/read)

    requests = Enum.filter(outgoing(ctx), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 4 and length(Enum.uniq(ids)) === 4
    assert Enum.at(ids, 0) === @initialize_id
    assert Enum.at(ids, 3) === @id
    assert Enum.all?(Enum.drop(ids, 1), &is_binary/1)
    responses = Enum.filter(incoming(ctx), &Map.has_key?(&1.wire, "id"))
    assert length(responses) === 4
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    assert [created] = Enum.filter(incoming(ctx), &(&1.wire["method"] === "thread/started"))
    assert created.wire["params"]["thread"]["id"] === thread

    assert [read] = Enum.filter(outgoing(ctx), &(&1.wire["method"] === "mcpServer/resource/read"))
    assert read.wire["params"] === %{"threadId" => thread, "server" => @server, "uri" => @uri}

    for frame <- Enum.reject(incoming(ctx), &Map.has_key?(&1.wire, "id")) do
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
      assert is_integer(frame.wire["emittedAtMs"]) and frame.wire["emittedAtMs"] > 0
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire

      # Thread creation is a correlation oracle only. Do not inspect or assert
      # policy, approval, sandbox or authentication fields on its full result.
      refute String.starts_with?(frame.wire["method"], ["turn/", "item/"])
    end
  end

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

  defp await_thread_created(ctx, pid, thread, deadline, budget) do
    assert budget > 0, "Owned native notification bound"
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    refute Enum.any?(events, &(&1.kind === :server_request))

    case Enum.filter(incoming(ctx), &(&1.wire["method"] === "thread/started")) do
      [notice] ->
        assert notice.wire["params"]["thread"]["id"] === thread

      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Owned native thread notice deadline"

        receive do
          {:codex_driver, ^pid, :events_available} ->
            await_thread_created(ctx, pid, thread, deadline, budget - 1)
        after
          remaining -> flunk("Missing native thread/started notification")
        end
    end
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

  defp request_id,
    do: "owned-extension219-control-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
