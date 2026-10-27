defmodule SamgitaCodexDriver.NativeCollaborationCatalogueTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @config """
  check_for_update_on_startup = false
  [memories]
  generate_memories = false
  use_memories = false
  [features]
  apps = false
  plugins = false
  remote_plugin = false
  recommended_plugins = false
  memories = false
  shell_snapshot = false
  """
  @catalogue %{
    "data" => [
      %{
        "name" => "Plan",
        "mode" => "plan",
        "model" => nil,
        "reasoning_effort" => "medium"
      },
      %{
        "name" => "Default",
        "mode" => "default",
        "model" => nil,
        "reasoning_effort" => nil
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
        {:ok, next} -> record_sent(next, encoded)
        other -> other
      end
    end

    defp record_sent(state, encoded) do
      case record(state.capture, :out, encoded) do
        :ok -> {:ok, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} -> record_received(next, events)
        other -> other
      end
    end

    defp record_received(state, events) do
      case Enum.reduce_while(events, :ok, &record_event(&1, &2, state.capture)) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Retain original payloads before Session decode, including all notifications.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 64 and size <= limit and ledger.bytes + size <= 524_288 do
        entry = %{direction: direction, encoded: encoded}

        {:ok,
         %{count: ledger.count + 1, bytes: ledger.bytes + size, records: [entry | ledger.records]}}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
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

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-collaboration-catalogue-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    config = Path.join(root, "codex/config.toml")
    File.write!(config, @config, [:exclusive])
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    %{
      binary: Path.expand(binary),
      root: root,
      workspace: Path.join(root, "workspace"),
      config: config,
      capture: capture
    }
  end

  test "actual built-in Plan and Default catalogues retain exact rows across warm and cold reads",
       ctx do
    assert_inputs(ctx)
    warm = start(ctx, "warm")
    assert_catalogue(ctx, warm.pid, "warm-first")
    assert_catalogue(ctx, warm.pid, "warm-repeat")
    assert_quiet(ctx, warm.pid)
    close(warm)

    cold = start(ctx, "cold")
    refute cold.native === warm.native
    assert_catalogue(ctx, cold.pid, "cold-first")
    assert_catalogue(ctx, cold.pid, "cold-repeat")
    assert_quiet(ctx, cold.pid)
    close(cold)
    assert_inputs(ctx)
    assert_inventory(ctx)
  end

  defp assert_catalogue(ctx, pid, suffix) do
    id = "owned-collaboration-" <> suffix

    # Literal full rows precede native execution. Default is outer None in the
    # pinned closed producer; raw JSON null alone cannot distinguish both Options.
    assert request(ctx, pid, id, "collaborationMode/list", %{}) ===
             %{"id" => id, "result" => @catalogue}

    assert_inputs(ctx)
  end

  defp start(ctx, label) do
    assert_inputs(ctx)

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
    on_exit(fn -> cleanup(pid, connection, identity) end)
    id = "owned-collaboration-" <> label <> "-initialize"
    info = %{"name" => "owned_collaboration_catalogue", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    diagnostics_id = "owned-collaboration-" <> label <> "-diagnostics"

    diagnostics = request(ctx, pid, diagnostics_id, "server/diagnostics", %{})
    native = diagnostics["result"]["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    assert_inputs(ctx)
    %{pid: pid, connection: connection, identity: identity, native: native}
  end

  defp request(ctx, pid, id, method, params) do
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => _} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    response
  end

  defp assert_exchange(ctx, wire, response) do
    selected = Enum.filter(records(ctx), &(&1.wire["id"] === wire["id"]))
    assert [sent, received] = selected
    assert sent.direction === :out
    assert sent.encoded === JSON.encode!(wire)
    assert sent.wire === wire
    assert received.direction === :in
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp records(ctx) do
    ctx.capture
    |> Agent.get(&Enum.reverse(&1.records))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp assert_inventory(ctx) do
    captured = records(ctx)
    outbound = Enum.filter(captured, &(&1.direction === :out))
    requests = Enum.filter(outbound, &Map.has_key?(&1.wire, "id"))

    assert Enum.map(requests, &{&1.wire["id"], &1.wire["method"]}) === [
             {"owned-collaboration-warm-initialize", "initialize"},
             {"owned-collaboration-warm-diagnostics", "server/diagnostics"},
             {"owned-collaboration-warm-first", "collaborationMode/list"},
             {"owned-collaboration-warm-repeat", "collaborationMode/list"},
             {"owned-collaboration-cold-initialize", "initialize"},
             {"owned-collaboration-cold-diagnostics", "server/diagnostics"},
             {"owned-collaboration-cold-first", "collaborationMode/list"},
             {"owned-collaboration-cold-repeat", "collaborationMode/list"}
           ]

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 8

    replies =
      Enum.filter(captured, fn record ->
        record.direction === :in and Map.has_key?(record.wire, "id") and
          not Map.has_key?(record.wire, "method")
      end)

    assert length(replies) === 8
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
    notifications = Enum.reject(outbound, &Map.has_key?(&1.wire, "id"))

    assert Enum.map(notifications, & &1.wire) === [
             %{"method" => "initialized"},
             %{"method" => "initialized"}
           ]

    ledger = Agent.get(ctx.capture, & &1)
    assert ledger.count === length(captured)
    assert ledger.count <= 64
    assert ledger.bytes === Enum.reduce(captured, 0, &(byte_size(&1.encoded) + &2))
    assert ledger.bytes <= 524_288
  end

  defp assert_quiet(ctx, pid) do
    assert {:ok, events} = Session.drain(pid, 32)
    assert length(events) <= 32
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 131_072

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or
               method == "error" or String.starts_with?(method, "thread/") or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)

    assert_inputs(ctx)
  end

  defp assert_inputs(ctx) do
    assert File.stat!(ctx.config).size <= 8192
    assert File.read!(ctx.config) === @config
    assert File.ls!(ctx.workspace) === []
  end

  defp close(session), do: cleanup(session.pid, session.connection, session.identity)

  defp cleanup(pid, connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
