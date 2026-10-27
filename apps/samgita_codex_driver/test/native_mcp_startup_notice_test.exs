defmodule SamgitaCodexDriver.NativeMcpStartupNoticeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @peer Path.expand("../../../scripts/codex/mcp_startup_notice_fixture.py", __DIR__)
  @peer_sha "6ade0c9894edad112100fa98e773f3a7e797adf60c355bd39a7201daac244725"
  @method "mcpServer/startupStatus/updated"

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
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    # Retain original framed bytes before Session decoding, including native
    # notifications. Never recreate the captured frame from a decoded map.
    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 4096, else: 65_536

        if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
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

    binary = Path.expand(binary)
    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@provider)) === @provider_sha
    assert hash(File.read!(@peer)) === @peer_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-startup-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: binary, root: root}
  end

  test "ordinary native MCP startup preserves exact thread and null diagnostics across held cold dependencies",
       ctx do
    results =
      for name <- ["owned_startup_alpha", "owned_startup_beta"] do
        profile = profile(ctx, name)
        session = start(profile)

        assert call(profile, session.pid, "thread/loaded/list", %{}) === %{
                 "data" => [],
                 "nextCursor" => nil
               }

        started =
          call(profile, session.pid, "thread/start", %{
            "model" => "mock-model",
            "modelProvider" => "fixture",
            "cwd" => profile.fixture.workspace,
            "ephemeral" => true,
            "approvalPolicy" => "never",
            "sandbox" => "danger-full-access"
          })

        thread = started["thread"]["id"]
        assert is_binary(thread) and byte_size(thread) > 0

        rows =
          await_journal(
            profile,
            &Enum.any?(&1, fn row ->
              row["event"] == "request" and row["method"] == "initialize"
            end)
          )

        assert [%{"id" => init_id}] =
                 Enum.filter(rows, &(&1["event"] == "request" and &1["method"] == "initialize"))

        assert [%{"pid" => child, "name" => ^name}] =
                 Enum.filter(rows, &(&1["event"] == "started"))

        assert is_integer(child) and child > 0 and child != session.native
        assert File.exists?("/proc/#{child}")

        # Independent full oracle from the pinned producer, not observed payloads.
        starting = %{
          "threadId" => thread,
          "name" => name,
          "status" => "starting",
          "error" => nil,
          "failureReason" => nil
        }

        ready = %{
          "threadId" => thread,
          "name" => name,
          "status" => "ready",
          "error" => nil,
          "failureReason" => nil
        }

        events = collect(session.pid, starting, [])
        assert notices(events) === [starting]
        refute File.exists?(profile.release)
        assert_pending_journal(profile, init_id)

        # A live public native RPC completes while dependency initialize remains
        # held. No sleep duration or enlarged timeout stands in for this barrier.
        assert call(profile, session.pid, "thread/loaded/list", %{}) === %{
                 "data" => [thread],
                 "nextCursor" => nil
               }

        events = drain(session.pid, events)
        assert notices(events) === [starting]
        assert raw_notices(profile) === [starting]
        assert_pending_journal(profile, init_id)
        assert_retained(profile)

        release!(profile)

        await_journal(
          profile,
          &Enum.any?(&1, fn row -> row["event"] == "reply" and row["method"] == "initialize" end)
        )

        events = collect(session.pid, ready, events)

        assert call(profile, session.pid, "thread/loaded/list", %{}) === %{
                 "data" => [thread],
                 "nextCursor" => nil
               }

        events = drain(session.pid, events)
        assert notices(events) === [starting, ready]
        assert raw_notices(profile) === [starting, ready]
        assert_peer_completed(profile, init_id)
        assert_retained(profile)
        assert_inventory(profile, events)

        assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
                 Session.status(session.pid)

        assert Session.uncertain_operations(session.pid) === []
        assert Session.interaction_outcomes(session.pid) === []
        close(session, profile)
        close_provider(profile.fixture)
        assert_retained(profile)
        %{thread: thread, native: session.native, child: child, root: profile.root}
      end

    assert Enum.uniq_by(results, & &1.thread) === results
    assert Enum.uniq_by(results, & &1.root) === results

    for result <- results do
      refute File.exists?("/proc/#{result.native}")
      refute File.exists?("/proc/#{result.child}")
    end
  end

  defp profile(ctx, name) do
    root = Path.join(ctx.root, name)
    File.mkdir!(root)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> close_provider(fixture) end)
    File.write!(fixture.requests, "[]")

    profile = %{
      binary: ctx.binary,
      root: root,
      fixture: fixture,
      name: name,
      journal: Path.join(root, "mcp-journal.jsonl"),
      release: Path.join(root, "initialize.release")
    }

    File.write!(profile.journal, "", [:exclusive])
    TurnFixture.configure_model(profile, %{})
    config = Path.join(fixture.codex_home, "config.toml")
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    base =
      File.read!(config)
      |> String.replace(~s(approval_policy = "on-request"), ~s(approval_policy = "never"))
      |> String.replace(~s(sandbox_mode = "read-only"), ~s(sandbox_mode = "danger-full-access"))

    File.write!(
      config,
      "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        base <>
        """

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
        shell_snapshot = false
        memories = false
        mcp_2026_07_28 = false
        [mcp_servers.#{name}]
        command = #{JSON.encode!(python)}
        args = #{JSON.encode!(["-B", @peer, "--journal", profile.journal, "--release", profile.release, "--name", name])}
        required = false
        startup_timeout_sec = 10
        tool_timeout_sec = 10
        """
    )

    inputs = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      @peer,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: {Agent, name})

    Map.merge(profile, %{
      capture: capture,
      inputs: Map.new(inputs, &{&1, bounded_file(&1, 1_048_576)})
    })
  end

  defp start(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: profile.capture,
                    executable: profile.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: profile.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => profile.fixture.home,
                      "CODEX_HOME" => profile.fixture.codex_home,
                      "TMPDIR" => profile.root,
                      "PATH" => profile.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    native_identity = :atomics.new(1, [])

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      native = :atomics.get(native_identity, 1)
      if native > 0, do: refute(File.exists?("/proc/#{native}"))
      assert_peer_gone(profile)
    end)

    id = request_id()
    info = %{"name" => "owned_mcp_startup_notice", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      profile,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(native_identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Map.keys(response) |> Enum.sort() === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, fn ledger ->
      ledger.records |> Enum.reverse() |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
    end)
  end

  defp raw_notices(profile),
    do:
      for(
        %{direction: :in, wire: %{"method" => @method, "params" => params}} <- capture(profile),
        do: params
      )

  defp notices(events),
    do: for(%{wire: %{"method" => @method, "params" => params}} <- events, do: params)

  defp drain(pid, events) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 128
    assert byte_size(JSON.encode!(Enum.map(combined, & &1.wire))) <= 2_097_152
    combined
  end

  defp collect(pid, expected, events), do: collect(pid, expected, events, now() + 5_000)

  defp collect(pid, expected, events, deadline) do
    events = drain(pid, events)

    cond do
      expected in notices(events) ->
        events

      now() >= deadline ->
        flunk("Native ordinary MCP startup notification deadline")

      true ->
        Process.sleep(10)
        collect(pid, expected, events, deadline)
    end
  end

  defp journal(profile) do
    # The peer appends complete bounded rows in single writes. A stat snapshot
    # may precede the next append, so do not require its size to equal a later
    # read's size as we do for immutable fixture inputs.
    assert %{type: :regular, size: size} = File.stat!(profile.journal)
    assert size <= 65_536
    bytes = File.read!(profile.journal)
    assert byte_size(bytes) <= 65_536
    rows = String.split(bytes, "\n", trim: true)
    assert length(rows) <= 64

    for line <- rows do
      assert byte_size(line) <= 4096
      JSON.decode!(line)
    end
  end

  defp await_journal(profile, predicate), do: await_journal(profile, predicate, now() + 5_000)

  defp await_journal(profile, predicate, deadline) do
    rows = journal(profile)
    refute Enum.any?(rows, &(&1["event"] == "fatal"))

    cond do
      predicate.(rows) ->
        rows

      now() >= deadline ->
        flunk("Owned MCP dependency journal deadline")

      true ->
        Process.sleep(10)
        await_journal(profile, predicate, deadline)
    end
  end

  defp assert_pending_journal(profile, init_id) do
    assert [
             %{"event" => "started", "name" => name},
             %{"event" => "request", "method" => "initialize", "id" => ^init_id}
           ] = journal(profile)

    assert name === profile.name
    refute File.exists?(profile.release)
  end

  defp release!(profile) do
    temporary = profile.release <> ".next"

    try do
      File.write!(temporary, "release\n", [:exclusive])
      File.rename!(temporary, profile.release)
    after
      File.rm(temporary)
    end
  end

  defp assert_peer_completed(profile, init_id) do
    rows =
      await_journal(
        profile,
        &Enum.any?(&1, fn row -> row["event"] == "reply" and row["method"] == "tools/list" end)
      )

    assert [%{"id" => ^init_id}] = Enum.filter(rows, &(&1["event"] == "released"))

    assert [%{"id" => ^init_id}] =
             Enum.filter(rows, &(&1["event"] == "reply" and &1["method"] == "initialize"))

    assert [%{"method" => "notifications/initialized"}] =
             Enum.filter(rows, &(&1["event"] == "notification"))

    requests = Enum.filter(rows, &(&1["event"] == "request"))
    assert Enum.map(requests, & &1["method"]) === ["initialize", "tools/list"]

    assert Enum.map(Enum.filter(rows, &(&1["event"] == "reply")), & &1["id"]) ===
             Enum.map(requests, & &1["id"])
  end

  defp assert_inventory(profile, events) do
    outgoing = for %{direction: :out, wire: wire} <- capture(profile), do: wire

    assert Enum.map(outgoing, & &1["method"]) === [
             "initialize",
             "initialized",
             "server/diagnostics",
             "thread/loaded/list",
             "thread/start",
             "thread/loaded/list",
             "thread/loaded/list"
           ]

    requests = Enum.filter(outgoing, &Map.has_key?(&1, "id"))
    assert length(requests) === 6
    assert length(Enum.uniq_by(requests, & &1["id"])) === 6

    for %{direction: :in, wire: wire} <- capture(profile) do
      if Map.has_key?(wire, "id"), do: refute(Map.has_key?(wire, "method"))
    end

    for event <- events do
      assert event.kind in [:notification, :unknown_notification]
      method = event.wire["method"] || ""
      refute method == "error" or String.starts_with?(method, ["turn/", "item/"])
    end
  end

  defp assert_retained(profile) do
    for {path, bytes} <- profile.inputs, do: assert(bounded_file(path, 1_048_576) === bytes)
    assert bounded_file(profile.fixture.requests, 65_536) === "[]"
    assert ModelFixture.requests(profile.fixture) === []
    assert File.ls!(profile.fixture.workspace) === []
  end

  defp close(session, profile) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    refute File.exists?("/proc/#{session.native}")
    assert_peer_gone(profile)
  end

  defp assert_peer_gone(profile) do
    for %{"event" => "started", "pid" => pid} <- journal(profile),
        do: refute(File.exists?("/proc/#{pid}"))
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp bounded_file(path, limit) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size <= limit
    bytes = File.read!(path)
    assert byte_size(bytes) === size
    bytes
  end

  defp request_id, do: "owned-mcp-startup-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
