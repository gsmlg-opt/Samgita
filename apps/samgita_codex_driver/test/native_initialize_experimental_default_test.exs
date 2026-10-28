defmodule SamgitaCodexDriver.NativeInitializeExperimentalDefaultTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @config """
  check_for_update_on_startup = false
  allow_login_shell = false
  [analytics]
  enabled = false
  [otel]
  exporter = "none"
  trace_exporter = "none"
  metrics_exporter = "none"
  [memories]
  generate_memories = false
  use_memories = false
  [skills.bundled]
  enabled = false
  [features]
  apps = false
  plugins = false
  remote_plugin = false
  recommended_plugins = false
  remote_models = false
  memories = false
  shell_snapshot = false
  hooks = false
  """

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

      if ledger.count < 96 and size <= limit and ledger.bytes + size <= 1_048_576 do
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
        "owned-initialize-default-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    # Registered session cleanup callbacks run before this older callback.
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

  test "null initialize remains retryable while omitted and false experimental flags gate durable project effects",
       ctx do
    params = %{
      "name" => "Owned enabled project λ",
      "roots" => [%{"path" => ctx.workspace}],
      "metadata" => %{"marker" => "native-initialize-default"},
      "idempotencyKey" => "owned-initialize-feature-project"
    }

    first = start(ctx)
    invalid = %{"experimentalApi" => nil}
    before = outgoing(ctx)
    info = info("null-recovery")

    # Normal validation is retained. This local failure is not native evidence.
    assert {:error, %Error{code: :schema_violation, uncertain: false}} =
             Session.initialize(first.pid, info, invalid,
               id: "owned-initialize-null-local",
               timeout_ms: 5_000
             )

    assert outgoing(ctx) === before
    assert %{phase: :new, pending: 0, uncertain: 0} = Session.status(first.pid)

    # Deliberate malformed-input probe through the supported lossless wire mode.
    # No positive compatibility claim uses wire-only validation.
    error = initialize_error(ctx, first, info, invalid)

    assert error === %{
             "code" => -32_600,
             "message" => "Invalid request: invalid type: null, expected a boolean"
           }

    assert %{phase: :new, pending: 0, uncertain: 0} = Session.status(first.pid)
    assert {:ok, []} = Session.drain(first.pid, 32)

    first = initialize(ctx, first, "absent", %{})
    reject_create(ctx, first, Map.put(params, "name", "Rejected absent flag"))
    close(first)
    assert_inputs(ctx)

    second = initialize(ctx, start(ctx), "false", %{"experimentalApi" => false})
    refute first.native === second.native
    reject_create(ctx, second, Map.put(params, "name", "Rejected false flag"))
    close(second)
    assert_inputs(ctx)

    enabled = initialize(ctx, start(ctx), "true", %{"experimentalApi" => true})
    refute enabled.native in [first.native, second.native]
    assert result(ctx, enabled, "project/list", %{}) === %{"data" => [], "nextCursor" => nil}

    lower = System.system_time(:millisecond)
    project = result(ctx, enabled, "project/create", params)["project"]
    upper = System.system_time(:millisecond)
    assert_project(project, params, div(lower, 1000), div(upper, 1000))
    project_id = project["id"]
    notices = project_notices(enabled.pid, [], System.monotonic_time(:millisecond) + 5_000)
    assert [%{"emittedAtMs" => emitted} = notice] = notices
    assert is_integer(emitted) and emitted in lower..upper

    assert notice === %{
             "method" => "project/changed",
             "emittedAtMs" => emitted,
             "params" => %{"projectId" => project_id, "changeType" => "created"}
           }

    assert result(ctx, enabled, "project/read", %{"projectId" => project_id}) === %{
             "project" => project
           }

    assert result(ctx, enabled, "project/list", %{}) === %{
             "data" => [project],
             "nextCursor" => nil
           }

    quiet(ctx, enabled)
    close(enabled)
    assert_inputs(ctx)

    cold = initialize(ctx, start(ctx), "cold-true", %{"experimentalApi" => true})
    refute cold.native in [first.native, second.native, enabled.native]

    assert result(ctx, cold, "project/read", %{"projectId" => project_id}) === %{
             "project" => project
           }

    assert result(ctx, cold, "project/list", %{}) === %{"data" => [project], "nextCursor" => nil}
    quiet(ctx, cold)
    close(cold)
    assert_inputs(ctx)
    inventory(ctx)
  end

  defp reject_create(ctx, session, params) do
    before = outgoing(ctx)

    assert {:error, %Error{code: :experimental_api_required, uncertain: false}} =
             Session.request(session.pid, "project/create", params, timeout_ms: 5_000)

    assert outgoing(ctx) === before
    id = id("create-wire")
    wire = %{"id" => id, "method" => "project/create", "params" => params}

    assert {:error,
            %Error{
              code: :upstream_error,
              uncertain: false,
              wire: %{"id" => ^id, "error" => error} = response
            }} =
             Session.request_native(session.pid, wire, validation: :wire, timeout_ms: 5_000)

    exchange(ctx, wire, response)

    assert error === %{
             "code" => -32_600,
             "message" => "project/create requires experimentalApi capability"
           }

    quiet(ctx, session)
  end

  defp initialize_error(ctx, session, client_info, capabilities) do
    wire = %{
      "id" => "owned-initialize-null-native",
      "method" => "initialize",
      "params" => %{"clientInfo" => client_info, "capabilities" => capabilities}
    }

    assert {:error,
            %Error{
              code: :upstream_error,
              uncertain: false,
              wire: %{"id" => "owned-initialize-null-native", "error" => error} = response
            }} =
             Session.request_native(session.pid, wire, validation: :wire, timeout_ms: 5_000)

    exchange(ctx, wire, response)
    error
  end

  defp initialize(ctx, session, label, capabilities) do
    client_info = info(label)
    request_id = "owned-initialize-" <> label

    wire = %{
      "id" => request_id,
      "method" => "initialize",
      "params" => %{"clientInfo" => client_info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^request_id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(session.pid, client_info, capabilities,
               id: request_id,
               timeout_ms: 5_000
             )

    exchange(ctx, wire, response)
    native = owned_native(ctx, session.connection)
    :atomics.put(session.identity, 1, native)

    # Diagnostics itself is experimental. Never dispatch it under absent/false
    # negotiation; true connections independently corroborate transport identity.
    if capabilities["experimentalApi"] === true do
      assert result(ctx, session, "server/diagnostics", %{})["process"]["id"] === native
    end

    Map.put(session, :native, native)
  end

  defp owned_native(ctx, connection) do
    # Port.os_pid identifies the owned Python group helper, never Codex itself.
    # Inspect only that exact helper's direct children, not the process table.
    assert {:os_pid, helper} = Port.info(connection.port, :os_pid)
    assert is_integer(helper) and helper > 0
    command = File.read!("/proc/#{helper}/cmdline")
    assert byte_size(command) <= 8192
    argv = String.split(command, <<0>>, trim: true)
    owner_script = Path.join(:code.priv_dir(:samgita_codex_driver), "stdio_owner.py")
    assert Enum.at(argv, 1) === owner_script
    assert Enum.at(argv, 2) === ctx.binary

    children = File.read!("/proc/#{helper}/task/#{helper}/children")
    assert byte_size(children) <= 128
    assert [native] = children |> String.split() |> Enum.map(&String.to_integer/1)
    assert native > 0 and native != helper
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    stat = File.read!("/proc/#{native}/stat")
    assert byte_size(stat) <= 8192
    assert [_, parent, group] = Regex.run(~r/\A\d+ \(.*\) \S ([0-9]+) ([0-9]+) /s, stat)
    assert parent === Integer.to_string(helper)
    assert group === Integer.to_string(native)
    native
  end

  defp result(ctx, session, method, params) do
    request_id = id(method)
    wire = %{"id" => request_id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^request_id, "result" => value} = response} =
             Session.request_native(session.pid, wire, timeout_ms: 5_000)

    exchange(ctx, wire, response)
    value
  end

  defp project_notices(pid, notices, until) do
    assert {:ok, events} = Session.drain(pid, 32)
    ordinary(events)

    notices =
      notices ++ for(event <- events, event.wire["method"] == "project/changed", do: event.wire)

    assert length(notices) <= 1

    if length(notices) == 1 do
      notices
    else
      assert System.monotonic_time(:millisecond) < until, "native project notification deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
      after
        10 -> :ok
      end

      project_notices(pid, notices, until)
    end
  end

  defp quiet(ctx, session) do
    assert result(ctx, session, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert {:ok, events} = Session.drain(session.pid, 32)
    ordinary(events)
    refute Enum.any?(events, &(&1.wire["method"] == "project/changed"))

    assert %{
             phase: :ready,
             pending: 0,
             uncertain: 0,
             interactions: 0,
             gap: nil,
             buffered_events: 0
           } = Session.status(session.pid)

    assert Session.uncertain_operations(session.pid) === []
    assert_inputs(ctx)
  end

  defp ordinary(events) do
    assert length(events) <= 32
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 131_072

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or method == "error" or
               String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp assert_project(project, params, lower, upper) do
    assert Enum.sort(Map.keys(project)) ===
             ~w(createdAt id metadata name position recencyAt roots updatedAt)

    assert is_binary(project["id"]) and project["id"] != ""

    assert Map.take(project, ~w(name roots metadata)) ===
             Map.take(params, ~w(name roots metadata))

    assert project["position"] === 0
    assert project["recencyAt"] === nil
    assert is_integer(project["createdAt"]) and project["createdAt"] in lower..upper
    assert project["updatedAt"] === project["createdAt"]
  end

  defp exchange(ctx, wire, response) do
    selected = Enum.filter(records(ctx), &(&1.wire["id"] === wire["id"]))
    assert [sent, received] = selected
    assert sent.direction === :out
    assert sent.encoded === JSON.encode!(wire)
    assert sent.wire === wire
    assert received.direction === :in
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
  end

  defp records(ctx),
    do:
      ctx.capture
      |> Agent.get(&Enum.reverse(&1.records))
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp outgoing(ctx), do: Enum.filter(records(ctx), &(&1.direction === :out))

  defp inventory(ctx) do
    captured = records(ctx)
    outbound = Enum.filter(captured, &(&1.direction === :out))
    requests = Enum.filter(outbound, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(captured, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(requests) === 19
    assert length(outbound) === 23
    assert length(Enum.uniq(ids)) === 19
    assert length(replies) === 19
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
    assert Enum.count(requests, &(&1.wire["method"] == "initialize")) === 5
    assert Enum.count(requests, &(&1.wire["method"] == "project/create")) === 3
    assert Enum.count(requests, &(&1.wire["method"] == "server/diagnostics")) === 2

    assert Enum.count(
             captured,
             &(&1.direction === :in and &1.wire["method"] == "project/changed")
           ) === 1
  end

  defp start(ctx) do
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
    %{pid: pid, connection: connection, identity: identity}
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

  defp info(label), do: %{"name" => "owned_initialize_default_" <> label, "version" => "0.1.0"}

  defp id(label),
    do:
      "owned-initialize-" <>
        label <> "-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
