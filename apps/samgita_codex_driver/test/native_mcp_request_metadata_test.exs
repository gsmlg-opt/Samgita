defmodule SamgitaCodexDriver.NativeMcpRequestMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @peer Path.expand("../../../scripts/codex/mcp_direct_fixture.py", __DIR__)
  @peer_sha "aa5afea1031896545c14db874081474b29129602c66f774e992f2eef80b9aacf"
  @arguments %{
    "label" => "普通 λ",
    "values" => [0, false, nil, "雪"],
    "nested" => %{"empty" => %{}, "ordered" => [3, 1, 2]}
  }
  @meta %{"fixture" => %{"label" => "元数据", "values" => [nil, false, 0], "empty" => []}}
  @cases [
    {%{"arguments" => @arguments, "_meta" => @meta}, @arguments},
    {%{}, nil},
    {%{"arguments" => nil, "_meta" => nil}, nil},
    {%{"arguments" => %{}, "_meta" => %{}}, %{}}
  ]

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      incoming_capture = Keyword.fetch!(opts, :incoming_capture)

      initialization = Keyword.fetch!(opts, :capture_initialization)

      with {:ok, state} <-
             Stdio.open(
               Keyword.drop(opts, [:capture, :incoming_capture, :capture_initialization])
             ),
           do:
             {:ok,
              Map.merge(state, %{
                capture: capture,
                incoming_capture: incoming_capture,
                capture_initialization: initialization
              })}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      selected =
        wire["method"] in ~w(server/diagnostics thread/loaded/list thread/start mcpServer/tool/call config/mcpServer/reload mcpServerStatus/list)

      if selected or
           (state.capture_initialization and wire["method"] in ~w(initialize initialized)) do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 24 and byte_size(encoded) <= 8192 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [{encoded, wire}]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case capture_incoming(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp capture_incoming(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case capture_incoming_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp capture_incoming_event(state, {:message, encoded}) do
      case JSON.decode(encoded) do
        {:ok, %{"id" => _} = wire} ->
          if Map.has_key?(wire, "method"),
            do: :ok,
            else:
              Agent.get_and_update(state.incoming_capture, &append_incoming(&1, encoded, wire))

        _ ->
          :ok
      end
    end

    defp capture_incoming_event(_state, _event), do: :ok

    defp append_incoming(ledger, encoded, wire) do
      size = byte_size(encoded)

      if length(ledger.frames) < 32 and size <= 65_536 and ledger.bytes + size <= 1_048_576 do
        {:ok, %{frames: ledger.frames ++ [{encoded, wire}], bytes: ledger.bytes + size}}
      else
        {{:error, SamgitaProtocolCodex.Error.new(:test_incoming_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@provider)) == @provider_sha
    assert hash(File.read!(@peer)) == @peer_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")
    journal = Path.join(ctx.root, "mcp-request-metadata.jsonl")
    File.write!(journal, "", [:exclusive])
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\nmcp_2026_07_28 = false\n" <>
        "\n[mcp_servers.fixture]\ncommand = #{JSON.encode!(python)}\n" <>
        "args = #{JSON.encode!([@peer, "--journal", journal])}\n" <>
        "startup_timeout_sec = 10\ntool_timeout_sec = 10\n"
    )

    assert File.stat!(config).size <= 8192

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          @peer,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    Map.merge(ctx, %{
      config: config,
      journal: journal,
      inputs: inputs,
      capture: start_supervised!({Agent, fn -> [] end}),
      incoming_capture:
        start_supervised!(
          Supervisor.child_spec({Agent, fn -> %{frames: [], bytes: 0} end}, id: :incoming_capture)
        )
    })
  end

  test "native direct MCP requests preserve nested metadata and optional shapes across cold initialization",
       ctx do
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_idle(ctx, warm.pid, [])
    warm_thread = start_thread(ctx, warm.pid)
    assert_idle(ctx, warm.pid, [warm_thread])
    assert_calls(ctx, warm.pid, warm_thread, [])
    assert_idle(ctx, warm.pid, [warm_thread])
    warm_journal = snapshot(ctx.journal)
    warm_peers = owned_peers(ctx, warm_native)
    close(warm, warm_native, warm_peers)
    assert_inputs(ctx)
    assert snapshot(ctx.journal) === warm_journal

    # Cold initialization creates a new empty root thread. It neither resumes
    # nor replays the former thread or any of its direct calls.
    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_idle(ctx, cold.pid, [])
    cold_thread = start_thread(ctx, cold.pid)
    refute cold_thread == warm_thread
    assert_idle(ctx, cold.pid, [cold_thread])
    assert_calls(ctx, cold.pid, cold_thread, expected_calls(warm_thread))
    assert_idle(ctx, cold.pid, [cold_thread])
    cold_journal = snapshot(ctx.journal)
    assert String.starts_with?(cold_journal.bytes, warm_journal.bytes)
    cold_peers = owned_peers(ctx, cold_native)
    close(cold, cold_native, cold_peers)
    assert_inputs(ctx)
    assert snapshot(ctx.journal) === cold_journal
    assert_wire_inventory(ctx, warm_thread, cold_thread)
  end

  test "native unchanged MCP reload and selected status retain typed IDs and one live peer",
       ctx do
    ctx = Map.put(ctx, :capture_initialization, true)
    deadline = now() + 20_000
    session = start(ctx)
    native = native_id(ctx, session.pid)
    assert_idle(ctx, session.pid, [])
    thread = start_thread(ctx, session.pid)
    assert_echo(ctx, session.pid, thread)
    assert_reload_journal(ctx, thread, 0, 1)
    peers = owned_peers(ctx, native)
    assert length(peers) === 1

    pairs = [
      {-504_930, -504_935},
      {504_930, 504_935},
      {"owned-reload-λ🙂", "owned-status-雪🙂"}
    ]

    for {{reload_id, status_id}, index} <- Enum.with_index(pairs, 1) do
      before = snapshot(ctx.journal)
      assert call(ctx, session.pid, "config/mcpServer/reload", :omit, reload_id) === %{}
      assert snapshot(ctx.journal) === before

      # This selected live status waits for dirty-runtime refresh. The reload
      # ACK alone cannot prove that the published connection is ready.
      status = call(ctx, session.pid, "mcpServerStatus/list", status_params(thread), status_id)
      assert_selected_status(status)
      assert_reload_journal(ctx, thread, index, 1)
      assert Enum.sort(owned_peers(ctx, native)) === Enum.sort(peers)
      assert_inputs(ctx)
      assert_ready(ctx, session.pid)
      assert now() <= deadline
    end

    assert_echo(ctx, session.pid, thread)
    assert_reload_journal(ctx, thread, 3, 2)
    assert_idle(ctx, session.pid, [thread])
    assert Enum.sort(owned_peers(ctx, native)) === Enum.sort(peers)
    assert_reload_inventory(ctx, thread, pairs)
    final_journal = snapshot(ctx.journal)
    final_capture = Agent.get(ctx.capture, & &1)
    final_incoming = Agent.get(ctx.incoming_capture, & &1)
    close(session, native, peers)
    assert snapshot(ctx.journal) === final_journal
    assert Agent.get(ctx.capture, & &1) === final_capture
    assert Agent.get(ctx.incoming_capture, & &1) === final_incoming
    assert_inputs(ctx)
    assert now() <= deadline
  end

  defp assert_echo(ctx, pid, thread) do
    assert call(
             ctx,
             pid,
             "mcpServer/tool/call",
             tool_params(thread, %{"arguments" => @arguments})
           ) ===
             %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Synthetic direct MCP result\n",
                   "_meta" => %{"fixture" => "content-preserved"}
                 }
               ],
               "structuredContent" => %{"arguments" => @arguments, "threadId" => thread},
               "isError" => false,
               "_meta" => %{"fixture" => %{"preserved" => true}}
             }
  end

  defp status_params(thread),
    do: %{"threadId" => thread, "serverName" => "fixture", "detail" => "full", "limit" => 1}

  defp assert_selected_status(status) do
    assert %{"data" => [server], "nextCursor" => nil} = status
    assert server["name"] === "fixture"
    assert server["runtimeStatus"] === "connected"

    assert Map.take(server["serverInfo"], ~w(name version)) === %{
             "name" => "synthetic-direct",
             "version" => "1"
           }

    assert Map.keys(server["tools"]) === ["echo"]

    assert Map.take(server["tools"]["echo"], ~w(name description inputSchema)) === %{
             "name" => "echo",
             "description" => "Synthetic echo only",
             "inputSchema" => %{"type" => "object", "properties" => %{}}
           }

    assert server["resources"] === [
             %{
               "uri" => "fixture://contents",
               "name" => "Synthetic resource",
               "mimeType" => "text/plain"
             }
           ]

    assert server["resourceTemplates"] === []
    assert server["toolsError"] === nil
  end

  defp assert_reload_journal(ctx, thread, statuses, calls) do
    rows = journal(ctx)

    expected = %{
      "initialize" => 1,
      "notifications/initialized" => 1,
      "tools/list" => 1,
      "tools/call" => calls
    }

    expected =
      if statuses == 0,
        do: expected,
        else:
          Map.merge(expected, %{
            "resources/list" => statuses,
            "resources/templates/list" => statuses
          })

    assert Enum.frequencies_by(rows, & &1["method"]) === expected

    assert [%{"params" => %{"protocolVersion" => "2025-06-18"}}] =
             Enum.filter(rows, &(&1["method"] === "initialize"))

    requests = Enum.filter(rows, &Map.has_key?(&1, "id"))
    ids = Enum.map(requests, & &1["id"])
    assert Enum.all?(ids, &(is_integer(&1) and &1 >= 0))
    assert length(Enum.uniq(ids)) === length(ids)

    token_requests = Enum.reject(requests, &(&1["method"] === "initialize"))
    tokens = Enum.map(token_requests, &get_in(&1, ["params", "_meta", "progressToken"]))
    assert Enum.sort(tokens) === Enum.to_list(0..(statuses * 2 + calls))

    assert [list] = Enum.filter(rows, &(&1["method"] === "tools/list"))
    assert list["params"] === %{"_meta" => %{"progressToken" => 0}}

    actual_calls = for %{"method" => "tools/call", "params" => params} <- rows, do: params
    expected_calls = for token <- Enum.take([1, 8], calls), do: reload_echo_params(thread, token)
    assert actual_calls === expected_calls

    resources = Enum.filter(rows, &(&1["method"] in ~w(resources/list resources/templates/list)))

    for request <- resources do
      token = get_in(request, ["params", "_meta", "progressToken"])
      assert request["params"] === %{"_meta" => %{"progressToken" => token}}
    end

    expected_resource_tokens =
      if statuses == 0, do: [], else: Enum.to_list(2..(statuses * 2 + 1))

    assert resources
           |> Enum.map(&get_in(&1, ["params", "_meta", "progressToken"]))
           |> Enum.sort() === expected_resource_tokens
  end

  defp reload_echo_params(thread, token),
    do: %{
      "name" => "echo",
      "arguments" => @arguments,
      "_meta" => %{"threadId" => thread, "progressToken" => token}
    }

  defp assert_reload_inventory(ctx, thread, pairs) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) === 14
    assert [{_, initialize}, {_, %{"method" => "initialized"}} | _] = frames
    assert initialize["method"] === "initialize"
    assert is_binary(initialize["id"])

    assert Enum.map(frames, fn {_, wire} -> wire["method"] end) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/start mcpServer/tool/call config/mcpServer/reload mcpServerStatus/list config/mcpServer/reload mcpServerStatus/list config/mcpServer/reload mcpServerStatus/list mcpServer/tool/call thread/loaded/list)

    requests = Enum.reject(frames, fn {_, wire} -> wire["method"] === "initialized" end)
    assert length(Enum.uniq_by(requests, fn {_, wire} -> wire["id"] end)) === 13
    incoming = Agent.get(ctx.incoming_capture, & &1.frames)
    assert length(incoming) === 13

    for {_, request} <- requests do
      assert [{bytes, response}] =
               Enum.filter(incoming, fn {_, wire} -> wire["id"] === request["id"] end)

      assert JSON.decode!(bytes) === response
      assert Enum.sort(Map.keys(response)) === ["id", "result"]
    end

    selected =
      Enum.filter(frames, fn {_, wire} ->
        wire["method"] in ~w(config/mcpServer/reload mcpServerStatus/list)
      end)

    expected =
      Enum.flat_map(pairs, fn {reload, status} ->
        [
          %{"id" => reload, "method" => "config/mcpServer/reload"},
          %{"id" => status, "method" => "mcpServerStatus/list", "params" => status_params(thread)}
        ]
      end)

    assert Enum.map(selected, fn {_, wire} -> wire end) === expected
  end

  defp start_thread(ctx, pid) do
    # Inherit fixed launch defaults; do not use TurnFixture.thread overrides.
    response = call(ctx, pid, "thread/start", thread_params(ctx))
    thread = Map.fetch!(response, "thread")
    assert is_binary(thread["id"]) and thread["id"] != ""
    assert ModelFixture.requests(ctx.fixture) == []
    thread["id"]
  end

  defp thread_params(ctx) do
    %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => ctx.fixture.workspace,
      "ephemeral" => true
    }
  end

  defp assert_calls(ctx, pid, thread, previous) do
    for {{extra, arguments}, index} <- Enum.with_index(@cases, 1) do
      assert call(
               ctx,
               pid,
               "mcpServer/tool/call",
               tool_params(thread, extra),
               tool_id(previous, index)
             ) === %{
               "content" => [
                 %{
                   "type" => "text",
                   "text" => "Synthetic direct MCP result\n",
                   "_meta" => %{"fixture" => "content-preserved"}
                 }
               ],
               "structuredContent" => %{"arguments" => arguments, "threadId" => thread},
               "isError" => false,
               "_meta" => %{"fixture" => %{"preserved" => true}}
             }

      rows = journal(ctx)
      calls = for %{"method" => "tools/call", "params" => params} <- rows, do: params
      assert calls === previous ++ Enum.take(expected_calls(thread), index)
      refute Enum.any?(rows, &(&1["method"] in ["resources/read", "server/discover"]))

      negotiations =
        for %{"method" => "initialize", "params" => params} <- rows, do: params["protocolVersion"]

      starts = if previous == [], do: 1, else: 2
      assert length(negotiations) == starts
      assert Enum.all?(negotiations, &(&1 == "2025-06-18"))
      lists = for %{"method" => "tools/list", "params" => params} <- rows, do: params
      assert lists === List.duplicate(%{"_meta" => %{"progressToken" => 0}}, starts)
      assert_inputs(ctx)
      assert_ready(ctx, pid)
    end
  end

  defp tool_id(previous, index) do
    generation = if previous == [], do: 1, else: 2

    case index do
      1 -> -955_000 - generation
      2 -> 955_000 + generation
      3 -> "owned-tool-λ🙂-#{generation}"
      4 -> nil
    end
  end

  defp expected_calls(thread) do
    # Omission and explicit null converge only at the native Option boundary.
    # Empty objects remain present; rich nested values and order remain exact.
    # Pinned RMCP allocates per-Peer tokens: startup tools/list consumes zero,
    # then these four calls consume 1..4. A cold Peer restarts that sequence.
    [
      %{
        "name" => "echo",
        "arguments" => @arguments,
        "_meta" => Map.merge(@meta, %{"threadId" => thread, "progressToken" => 1})
      },
      %{"name" => "echo", "_meta" => %{"threadId" => thread, "progressToken" => 2}},
      %{"name" => "echo", "_meta" => %{"threadId" => thread, "progressToken" => 3}},
      %{
        "name" => "echo",
        "arguments" => %{},
        "_meta" => %{"threadId" => thread, "progressToken" => 4}
      }
    ]
  end

  defp tool_params(thread, extra) do
    Map.merge(%{"threadId" => thread, "server" => "fixture", "tool" => "echo"}, extra)
  end

  defp journal(ctx) do
    bytes = snapshot(ctx.journal).bytes
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 128
    assert Enum.all?(lines, &(byte_size(&1) <= 65_536))
    Enum.map(lines, &JSON.decode!/1)
  end

  defp assert_inputs(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) == []
    assert File.ls!(ctx.fixture.workspace) == []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) == []
  end

  defp start(ctx) do
    args = NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"])

    assert {:ok, pid} =
             Session.start_link(
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    incoming_capture: ctx.incoming_capture,
                    capture_initialization: Map.get(ctx, :capture_initialization, false),
                    executable: ctx.binary,
                    args: args,
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_mcp_request_metadata", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params, id \\ nil) do
    before = length(Agent.get(ctx.capture, & &1))
    id = id || "owned-mcp-request-metadata-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method}
    wire = if params === :omit, do: wire, else: Map.put(wire, "params", params)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert byte_size(JSON.encode!(response)) <= 65_536
    assert [{bytes, actual}] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert actual === wire
    assert JSON.decode!(bytes) === wire
    assert bytes === JSON.encode!(wire)
    incoming = Agent.get(ctx.incoming_capture, & &1.frames)
    assert [{raw, raw_wire}] = Enum.filter(incoming, fn {_raw, frame} -> frame["id"] == id end)
    assert raw_wire === response
    assert JSON.decode!(raw) === response
    assert {:ok, decoded_request} = Wire.decode(bytes, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(raw, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]

    if method in ~w(config/mcpServer/reload mcpServerStatus/list mcpServer/tool/call) do
      assert :ok = Schema.validate(request_schema(), wire, max_depth: 32)
    end

    result
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp owned_peers(ctx, native) do
    peers =
      native
      |> descendants()
      |> Enum.filter(fn pid ->
        case File.read("/proc/#{pid}/cmdline") do
          {:ok, bytes} ->
            assert byte_size(bytes) <= 8192
            argv = String.split(bytes, <<0>>, trim: true)
            @peer in argv and ctx.journal in argv

          {:error, :enoent} ->
            false
        end
      end)

    assert peers != [] and length(peers) <= 4
    peers
  end

  defp descendants(native), do: descendants([{native, 0}], [])

  defp descendants([], found), do: found

  defp descendants([{pid, depth} | pending], found) do
    assert depth <= 8
    paths = Path.wildcard("/proc/#{pid}/task/*/children")
    assert length(paths) <= 128

    children =
      paths
      |> Enum.flat_map(fn path ->
        case File.read(path) do
          {:ok, bytes} ->
            assert byte_size(bytes) <= 8192
            bytes |> String.split() |> Enum.map(&String.to_integer/1)

          {:error, :enoent} ->
            []
        end
      end)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in found))

    assert length(children) <= 32
    found = found ++ children
    assert length(found) <= 64
    pending = pending ++ Enum.map(children, &{&1, depth + 1})
    assert length(pending) <= 64
    descendants(pending, found)
  end

  defp close(session, native, peers) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{native}")
    for peer <- peers, do: refute(File.exists?("/proc/#{peer}"))
  end

  defp assert_idle(ctx, pid, loaded) do
    assert call(ctx, pid, "thread/loaded/list", %{})["data"] === loaded
    assert_inputs(ctx)
    assert_ready(ctx, pid)
  end

  defp assert_ready(ctx, pid) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 128
    assert byte_size(:erlang.term_to_binary(events)) <= 1_048_576

    refute Enum.any?(events, fn event ->
             method = Map.get(event, :wire, %{})["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or
               method == "error" or String.starts_with?(method, "hook/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_wire_inventory(ctx, warm_thread, cold_thread) do
    frames = Agent.get(ctx.capture, & &1)
    assert length(frames) == 18
    assert length(Enum.uniq_by(frames, fn {_bytes, wire} -> wire["id"] end)) == 18

    assert Enum.frequencies_by(frames, fn {_bytes, wire} -> wire["method"] end) == %{
             "server/diagnostics" => 2,
             "thread/loaded/list" => 6,
             "thread/start" => 2,
             "mcpServer/tool/call" => 8
           }

    expected =
      Enum.flat_map([warm_thread, cold_thread], fn thread ->
        [
          {"server/diagnostics", %{}},
          {"thread/loaded/list", %{}},
          {"thread/start", thread_params(ctx)},
          {"thread/loaded/list", %{}}
        ] ++
          Enum.map(@cases, fn {extra, _arguments} ->
            {"mcpServer/tool/call", tool_params(thread, extra)}
          end) ++ [{"thread/loaded/list", %{}}]
      end)

    assert Enum.map(frames, fn {_bytes, wire} -> {wire["method"], wire["params"]} end) ===
             expected
  end

  defp request_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ClientRequest.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
