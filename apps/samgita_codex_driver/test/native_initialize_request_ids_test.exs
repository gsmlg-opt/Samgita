defmodule SamgitaCodexDriver.NativeInitializeRequestIdsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @request_schema_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  @initialize_ids [0, "owned-init-λ🙂", 9_007_199_254_740_993]
  @info %{"name" => "owned_initialize_ids", "version" => "0.1.0"}
  @capabilities %{"experimentalApi" => true}

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)) do
        case Agent.get_and_update(capture, &opened(&1, state.port)) do
          {:ok, generation} ->
            {:ok, Map.merge(state, %{capture: capture, capture_generation: generation})}

          {:error, failure} ->
            :ok = Stdio.close(state)
            {:error, failure}
        end
      end
    end

    defp opened(ledger, port) do
      if length(ledger.connections) < 3 do
        generation = length(ledger.connections) + 1
        entry = %{generation: generation, port: port}
        {{:ok, generation}, %{ledger | connections: ledger.connections ++ [entry]}}
      else
        {{:error, Error.new(:test_connection_capture_overflow)}, ledger}
      end
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
      Enum.reduce_while(events, :ok, fn event, :ok ->
        result =
          case event do
            {:message, encoded} -> record(state, :in, encoded)
            _ -> :ok
          end

        case result do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)

      if selected?(direction, wire) do
        Agent.get_and_update(state.capture, &append(&1, state, direction, encoded, wire))
      else
        :ok
      end
    end

    defp append(ledger, state, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 32 and size <= limit and ledger.bytes + size <= 1_048_576 do
        entry = %{
          direction: direction,
          generation: state.capture_generation,
          port: state.port,
          encoded: encoded,
          wire: wire
        }

        next =
          ledger
          |> Map.put(direction, entries ++ [entry])
          |> Map.put(:timeline, ledger.timeline ++ [entry])
          |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:out, %{"method" => "initialized"}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert digest(@provider) === @provider_sha
    assert digest(request_schema_path()) === @request_schema_sha
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

    assert digest(ctx.binary) === @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nplugins = false\nremote_plugin = false\napps = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture =
      start_supervised!(
        {Agent, fn -> %{connections: [], out: [], in: [], timeline: [], bytes: 0} end}
      )

    Map.merge(ctx, %{inputs: inputs, capture: capture})
  end

  test "native initialize IDs and concurrent typed reads remain scoped across clean reconnects",
       ctx do
    {pid, initial_connection} = start(ctx)
    initial = Session.status(pid)
    assert initial.phase === :new
    assert initial.generation === 1

    owners =
      @initialize_ids
      |> Enum.with_index(1)
      |> Enum.reduce([], fn {id, generation}, owners ->
        if generation > 1 do
          previous = List.last(owners)
          assert :ok = Session.reconnect(pid)
          assert_closed(previous)
        end

        connection = if generation === 1, do: initial_connection, else: remember_connection(pid)
        assert connection.capture_generation === generation
        assert scoped(ctx, :out, generation, connection.port) === []

        assert %{phase: :new, pending: 0, generation: ^generation, instance_id: instance} =
                 Session.status(pid)

        assert instance === initial.instance_id
        assert_gap(pid, generation)
        initialized = initialize(ctx, pid, generation, connection.port, id)
        assert_initialized(ctx, generation, connection.port)

        diagnostics = %{
          "id" => "owned-initialize-diagnostics-#{generation}",
          "method" => "server/diagnostics",
          "params" => %{}
        }

        assert {:ok, %{"result" => result} = response} =
                 Session.request_native(pid, diagnostics, timeout_ms: 5_000)

        assert_exchange(ctx, generation, connection.port, diagnostics, response)
        native = get_in(result, ["process", "id"])
        assert is_integer(native) and native > 0
        assert digest("/proc/#{native}/exe") === @binary_sha

        refute Enum.any?(
                 owners,
                 &(&1.native === native or &1.connection.port === connection.port)
               )

        concurrent_reads(ctx, pid, generation, connection.port)
        read(ctx, pid, generation, connection.port, "0")
        assert_initialized(ctx, generation, connection.port)
        assert initialized["id"] === id

        assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
        assert Session.uncertain_operations(pid) === []
        assert_gap(pid, generation)
        drain(pid)
        assert_sources(ctx)
        owners ++ [%{generation: generation, connection: connection, native: native}]
      end)

    assert :ok = Session.close(pid)
    Enum.each(owners, &assert_closed/1)
    assert_inventory(ctx, owners)
    assert_sources(ctx)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args([
                        "app-server",
                        "--listen",
                        "stdio://"
                      ]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
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

    # Capture wrappers use the existing saved-connection cleanup contract.
    connection = remember_connection(pid)
    {pid, connection}
  end

  defp remember_connection(pid) do
    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    connection
  end

  defp initialize(ctx, pid, generation, port, id) do
    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => @info, "capabilities" => @capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert response["id"] === id
    assert_exchange(ctx, generation, port, wire, response)
    assert Enum.sort(Map.keys(result)) === ~w(codexHome platformFamily platformOs userAgent)
    assert result["codexHome"] === ctx.fixture.codex_home
    assert result["platformFamily"] === "unix"
    assert result["platformOs"] === "linux"
    assert String.starts_with?(result["userAgent"], "owned_initialize_ids/0.163.0 (")
    assert String.ends_with?(result["userAgent"], " (owned_initialize_ids; 0.1.0)")
    response
  end

  defp concurrent_reads(ctx, pid, generation, port) do
    requests =
      try do
        assert :ok = :sys.suspend(pid, 5_000)

        for id <- [7, "7"] do
          wire = read_wire(id)
          ref = :gen_server.send_request(pid, {:request_native, wire, [timeout_ms: 5_000]})
          {ref, wire}
        end
      after
        # Always resume before any assertion-driven shutdown/on_exit cleanup.
        assert :ok = :sys.resume(pid, 5_000)
      end

    # Consume both aliases with bounded waits before asserting either result.
    replies =
      for {ref, wire} <- requests,
          do: {wire, :gen_server.receive_response(ref, 5_000)}

    for {wire, reply} <- replies do
      expected = %{"id" => wire["id"], "result" => %{"data" => [], "nextCursor" => nil}}
      assert reply === {:reply, {:ok, expected}}
      assert_exchange(ctx, generation, port, wire, expected)
    end

    entries = Agent.get(ctx.capture, & &1.timeline) |> in_connection(generation, port)

    positions =
      for {entry, position} <- Enum.with_index(entries),
          entry.wire["id"] === 7 or entry.wire["id"] === "7",
          do: {entry.direction, position}

    sent = for {:out, position} <- positions, do: position
    received = for {:in, position} <- positions, do: position
    assert length(sent) === 2
    assert length(received) === 2
    assert Enum.max(sent) < Enum.min(received)
  end

  defp read(ctx, pid, generation, port, id) do
    wire = read_wire(id)
    expected = %{"id" => id, "result" => %{"data" => [], "nextCursor" => nil}}
    assert Session.request_native(pid, wire, timeout_ms: 5_000) === {:ok, expected}
    assert_exchange(ctx, generation, port, wire, expected)
  end

  defp read_wire(id),
    do: %{"id" => id, "method" => "thread/loaded/list", "params" => %{}}

  defp assert_exchange(ctx, generation, port, wire, response) do
    id = wire["id"]

    assert [sent] =
             scoped(ctx, :out, generation, port)
             |> Enum.filter(&(Map.has_key?(&1.wire, "id") and &1.wire["id"] === id))

    assert [received] =
             scoped(ctx, :in, generation, port)
             |> Enum.filter(&(&1.wire["id"] === id))

    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]

    assert :ok =
             Schema.validate(
               JSON.decode!(File.read!(request_schema_path())),
               sent.wire,
               max_depth: 32
             )

    for entry <- [sent, received] do
      assert {:ok, preserved} = Wire.decode(entry.encoded, max_depth: 32)
      assert preserved === entry.wire
    end
  end

  defp assert_initialized(ctx, generation, port) do
    assert [entry] =
             scoped(ctx, :out, generation, port)
             |> Enum.filter(&(&1.wire["method"] === "initialized"))

    assert entry.wire === %{"method" => "initialized"}
    assert JSON.decode!(entry.encoded) === %{"method" => "initialized"}
  end

  defp assert_gap(pid, 1), do: assert(Session.status(pid).gap === nil)

  defp assert_gap(pid, generation) do
    previous = generation - 1

    assert %{reason: :explicit_reconnect, generation: ^previous, after_sequence: sequence} =
             Session.status(pid).gap

    assert is_integer(sequence) and sequence >= 0
  end

  defp assert_inventory(ctx, owners) do
    ledger = Agent.get(ctx.capture, & &1)
    assert length(ledger.connections) === 3
    assert length(ledger.out) === 18
    assert length(ledger.in) === 15

    for owner <- owners do
      %{generation: generation, connection: %{port: port}} = owner
      requests = scoped(ctx, :out, generation, port)
      replies = scoped(ctx, :in, generation, port)

      assert Enum.map(requests, & &1.wire["method"]) === [
               "initialize",
               "initialized",
               "server/diagnostics",
               "thread/loaded/list",
               "thread/loaded/list",
               "thread/loaded/list"
             ]

      ids = for entry <- requests, Map.has_key?(entry.wire, "id"), do: entry.wire["id"]
      assert length(ids) === 5
      assert MapSet.size(MapSet.new(ids)) === 5
      assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
      assert length(replies) === 5
      assert Enum.find(ledger.connections, &(&1.generation === generation)).port === port
    end

    keys = for entry <- ledger.in, do: {entry.generation, entry.port, entry.wire["id"]}
    assert MapSet.size(MapSet.new(keys)) === 15
  end

  defp scoped(ctx, direction, generation, port),
    do: Agent.get(ctx.capture, &Map.fetch!(&1, direction)) |> in_connection(generation, port)

  defp in_connection(entries, generation, port),
    do: Enum.filter(entries, &(&1.generation === generation and &1.port === port))

  defp assert_closed(%{connection: connection, native: native}) do
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    refute File.exists?("/proc/#{native}")
  end

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    refute Enum.any?(events, &(&1.kind === :server_request))
    assert {:ok, []} = Session.drain(pid, 256)
  end

  defp assert_sources(ctx) do
    assert digest(ctx.binary) === @binary_sha
    assert digest(@provider) === @provider_sha
    for {path, saved} <- ctx.inputs, do: assert(snapshot(path) === saved)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: :crypto.hash(:sha256, bytes)}
  end

  defp digest(path),
    do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp request_schema_path,
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/ClientRequest.json")
end
