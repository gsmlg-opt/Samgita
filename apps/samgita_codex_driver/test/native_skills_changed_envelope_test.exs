defmodule SamgitaCodexDriver.NativeSkillsChangedEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @changed "skills/changed"

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

    # Preserve original native bodies before Session decoding, without replacing
    # or manufacturing any app-server message.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)

      if ledger.count < 128 and size <= 65_536 and ledger.bytes + size <= 2_097_152 do
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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-skills-envelope-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    for child <- ~w(home codex workspace tmp extra-a extra-b),
        do: File.mkdir!(Path.join(root, child))

    config = Path.join(root, "codex/config.toml")

    File.write!(config, """
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
    """)

    skills = %{
      control: write_skill(Path.join(root, "codex/skills"), "owned-control"),
      a: write_skill(Path.join(root, "extra-a"), "owned-extra-a"),
      b: write_skill(Path.join(root, "extra-b"), "owned-extra-b")
    }

    frozen =
      Map.new(
        [config | Enum.map(skills, fn {_key, skill} -> skill["path"] end)],
        &{&1, File.read!(&1)}
      )

    %{binary: Path.expand(binary), root: root, skills: skills, frozen: frozen}
  end

  test "native skills notifications preserve root replacement, deduplication, clearing and restart effects",
       ctx do
    first = start_native(ctx)
    assert {:ok, []} = Session.drain(first.pid, 128)
    assert_catalog(ctx, first, [:control])

    a = Path.join(ctx.root, "extra-a")
    b = Path.join(ctx.root, "extra-b")

    operations = [
      {[a], [:control, :a]},
      {[b, b], [:control, :b]},
      {[], [:control]},
      {[b], [:control, :b]}
    ]

    events =
      Enum.reduce(operations, [], fn {roots, expected}, previous ->
        lower = System.system_time(:millisecond)

        {result, response, request} =
          call(first, "skills/extraRoots/set", %{"extraRoots" => roots})

        assert result === %{}
        [event] = await_notice(first.pid, [], now() + 5_000)
        upper = System.system_time(:millisecond)
        assert_notice(first, event, lower, upper)
        assert_causal_frame(first, request, event, response)
        assert_catalog(ctx, first, expected)
        assert {:ok, []} = Session.drain(first.pid, 128)
        assert_frozen(ctx)
        previous ++ [event]
      end)

    sequences = Enum.map(events, & &1.sequence)
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences === Enum.sort(Enum.uniq(sequences))
    assert length(events) === 4
    assert_idle(first)
    close_native(first)
    assert_originals(first, events)
    assert_inventory(first, 4, 5)
    assert_frozen(ctx)

    # Runtime roots are process-local. The same unchanged files must not make B
    # appear in a different native process after the final live B snapshot.
    cold = start_native(ctx)
    refute cold.native === first.native
    assert {:ok, []} = Session.drain(cold.pid, 128)
    assert_catalog(ctx, cold, [:control])
    assert_idle(cold)
    close_native(cold)
    assert_originals(cold, [])
    assert_inventory(cold, 0, 1)
    assert_frozen(ctx)
  end

  defp write_skill(root, name) do
    path = Path.join(root, name <> "/SKILL.md")
    File.mkdir_p!(Path.dirname(path))
    description = "Owned inert #{name} metadata."

    File.write!(
      path,
      "---\nname: #{name}\ndescription: #{description}\n---\n\nInert local text.\n"
    )

    %{
      "name" => name,
      "description" => description,
      "path" => path,
      "enabled" => true,
      "scope" => "user"
    }
  end

  defp start_native(ctx) do
    capture =
      start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end}, id: make_ref())

    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: Path.join(ctx.root, "workspace"),
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
    session = %{pid: pid, connection: connection, identity: identity, capture: capture}
    on_exit(fn -> close_native(session) end)
    id = request_id()
    info = %{"name" => "owned_skills_changed_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      session,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    {result, _response, _request} = call(session, "server/diagnostics", %{})
    native = result["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    Map.merge(session, %{native: native, generation: Session.status(pid).generation})
  end

  defp call(session, method, params) do
    wire = %{"id" => request_id(), "method" => method, "params" => params}

    assert {:ok, %{"result" => result} = response} =
             Session.request_native(session.pid, wire, timeout_ms: 5_000)

    assert_exchange(session, wire, response)
    {result, response, wire}
  end

  defp assert_exchange(session, wire, response) do
    assert response["id"] === wire["id"]
    assert [sent, received] = Enum.filter(capture(session), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_catalog(ctx, session, keys) do
    cwd = Path.join(ctx.root, "workspace")

    {result, _response, _request} =
      call(session, "skills/list", %{"cwds" => [cwd], "forceReload" => false})

    assert %{"data" => [%{"cwd" => ^cwd, "skills" => skills, "errors" => []}]} = result
    expected = Enum.map(keys, &Map.fetch!(ctx.skills, &1)) |> Enum.sort_by(& &1["name"])

    actual =
      Enum.map(skills, &Map.take(&1, ~w(name description path enabled scope)))
      |> Enum.sort_by(& &1["name"])

    assert actual === expected
  end

  defp await_notice(pid, events, deadline) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    combined = events ++ fresh
    assert length(combined) <= 4

    if combined == [] do
      assert now() < deadline, "Native skills/changed notification deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native skills event gap")
      after
        10 -> :ok
      end

      await_notice(pid, combined, deadline)
    else
      combined
    end
  end

  defp assert_notice(session, event, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === session.generation
    assert event.wire === %{"method" => @changed, "params" => %{}, "emittedAtMs" => emitted}
    assert :ok = Schema.validate(notification_schema(), event.wire, max_depth: 32)
  end

  defp assert_causal_frame(session, request, event, response) do
    records = capture(session)
    assert [sent] = positions(records, :out, request)
    assert [received] = positions(records, :in, response)
    # Distinct native envelopes may share a millisecond timestamp. Match the
    # original within this request's actual wire interval, not by global value.
    assert [notice] =
             Enum.filter(positions(records, :in, event.wire), &(sent < &1 and &1 < received))

    assert sent < notice and notice < received
  end

  defp positions(records, direction, wire),
    do:
      for(
        {record, index} <- Enum.with_index(records),
        record.direction === direction and record.wire === wire,
        do: index
      )

  defp assert_originals(session, events) do
    originals =
      Enum.filter(capture(session), &(&1.direction === :in and &1.wire["method"] === @changed))

    assert Enum.map(originals, & &1.wire) === Enum.map(events, & &1.wire)

    for {original, event} <- Enum.zip(originals, events),
        do: assert(JSON.decode!(original.encoded) === event.wire)
  end

  defp assert_inventory(session, sets, lists) do
    records = capture(session)
    outgoing = Enum.filter(records, &(&1.direction === :out))
    methods = Enum.map(outgoing, & &1.wire["method"])
    assert Enum.count(methods, &(&1 === "skills/extraRoots/set")) === sets
    assert Enum.count(methods, &(&1 === "skills/list")) === lists
    assert Enum.count(methods, &(&1 === "thread/loaded/list")) === 1

    assert Enum.all?(
             methods,
             &(&1 in ~w(initialize initialized server/diagnostics skills/list skills/extraRoots/set thread/loaded/list))
           )

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    assert length(requests) === sets + lists + 3
    assert length(Enum.uniq_by(requests, & &1.wire["id"])) === length(requests)

    for request <- requests do
      assert [_sent, received] = Enum.filter(records, &(&1.wire["id"] === request.wire["id"]))
      assert_exchange(session, request.wire, received.wire)
    end
  end

  defp assert_idle(session) do
    assert {%{"data" => [], "nextCursor" => nil}, _response, _request} =
             call(session, "thread/loaded/list", %{})

    assert %{
             phase: :ready,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil,
             buffered_events: 0
           } = Session.status(session.pid)

    assert Session.uncertain_operations(session.pid) === []
    assert {:ok, []} = Session.drain(session.pid, 128)
  end

  defp assert_frozen(ctx),
    do: Enum.each(ctx.frozen, fn {path, bytes} -> assert File.read!(path) === bytes end)

  defp capture(session),
    do:
      Agent.get(session.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp notification_schema do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_native(session) do
    connection = session.connection
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = StdioSessionFixture.close(session.pid, connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(session.identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id, do: "owned-skills-envelope-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
