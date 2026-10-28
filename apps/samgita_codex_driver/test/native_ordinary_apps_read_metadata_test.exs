defmodule SamgitaCodexDriver.NativeOrdinaryAppsReadMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_app_metadata_fixture.py", __DIR__)
  @script_sha "39b9d8c7bba1934139c9234533de47e225e7d4863c0dddbb5a266757d6a5e6a3"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @alpha %{
    "id" => "metadata-alpha",
    "name" => "Owned Alpha",
    "description" => "Owned Alpha display metadata λ🙂",
    "iconUrl" => "https://synthetic.invalid/metadata-alpha/light.svg",
    "iconUrlDark" => "https://synthetic.invalid/metadata-alpha/dark.svg",
    "distributionChannel" => "OWNED_METADATA_DIRECTORY",
    "pluginDisplayNames" => [],
    "toolSummaries" => [
      %{
        "name" => "metadata-alpha_lookup",
        "title" => "Alpha lookup β",
        "description" => "Display-only Alpha tool summary 🙂",
        "isEnabled" => true,
        "disabledReason" => "Opaque metadata label λ",
        "isReadOnly" => true
      }
    ]
  }
  @beta %{
    "id" => "metadata-beta",
    "name" => "Owned Beta",
    "description" => "Owned Beta display metadata λ🙂",
    "iconUrl" => "https://synthetic.invalid/metadata-beta/light.svg",
    "iconUrlDark" => "https://synthetic.invalid/metadata-beta/dark.svg",
    "distributionChannel" => "OWNED_METADATA_DIRECTORY",
    "pluginDisplayNames" => [],
    "toolSummaries" => [
      %{
        "name" => "metadata-beta_lookup",
        "title" => "Beta lookup β",
        "description" => "Display-only Beta tool summary 🙂",
        "isEnabled" => true,
        "disabledReason" => "Opaque metadata label λ",
        "isReadOnly" => true
      }
    ]
  }
  @first_batch %{
    "app_ids" => ["metadata-beta", "metadata-absent", "metadata-alpha"],
    "include_tools" => false
  }
  @promoted_batch %{"app_ids" => ["metadata-beta", "metadata-alpha"], "include_tools" => true}
  @cold_batch %{"app_ids" => ["metadata-alpha", "metadata-beta"], "include_tools" => true}
  @missing_batch %{"app_ids" => ["metadata-absent"], "include_tools" => true}

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
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 128, else: 768
      message_limit = if direction == :out, do: 4096, else: 131_072
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 4_194_304 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
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
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-app-metadata-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-app-metadata")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)

    paths = [
      @script,
      @base,
      Path.join(fixture.codex_home, "config.toml"),
      Path.join(fixture.codex_home, "models.json"),
      fixture.requests,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex"),
      schema_path("ClientRequest.json"),
      schema_path("v2/AppsReadResponse.json")
    ]

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native app metadata keeps exact projection order and cache promotion across a cold process",
       ctx do
    warm = start(ctx)
    assert_empty_loaded(ctx, warm.pid)
    # This case checks only copied descriptive fields. It issues no tool call
    # or configuration change.
    assert read(
             ctx,
             warm.pid,
             ["metadata-beta", "metadata-absent", "metadata-alpha", "metadata-beta"],
             false
           ) ===
             expected(ctx, [@beta, @alpha], false, ["metadata-absent"])

    assert_batches(ctx, [@first_batch])

    assert read(ctx, warm.pid, ["metadata-alpha", "metadata-beta"], false) ===
             expected(ctx, [@alpha, @beta], false, [])

    assert_batches(ctx, [@first_batch])

    assert read(ctx, warm.pid, ["metadata-beta", "metadata-alpha"], true) ===
             expected(ctx, [@beta, @alpha], true, [])

    assert_batches(ctx, [@first_batch, @promoted_batch])

    assert read(ctx, warm.pid, ["metadata-alpha", "metadata-beta"], false) ===
             expected(ctx, [@alpha, @beta], false, [])

    assert_batches(ctx, [@first_batch, @promoted_batch])

    assert read(ctx, warm.pid, ["metadata-alpha", "metadata-beta"], true) ===
             expected(ctx, [@alpha, @beta], true, [])

    assert_batches(ctx, [@first_batch, @promoted_batch])
    assert_empty_loaded(ctx, warm.pid)
    assert_controls(ctx)
    assert_idle(warm.pid)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    assert_controls(ctx)

    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_empty_loaded(ctx, cold.pid)
    # This is the first content RPC of the fresh stock native process. The
    # process-wide metadata cache must refetch from the same local dependency.
    assert read(ctx, cold.pid, ["metadata-alpha", "metadata-beta"], true) ===
             expected(ctx, [@alpha, @beta], true, [])

    assert_batches(ctx, [@first_batch, @promoted_batch, @cold_batch])

    assert read(ctx, cold.pid, ["metadata-beta", "metadata-alpha"], true) ===
             expected(ctx, [@beta, @alpha], true, [])

    assert_batches(ctx, [@first_batch, @promoted_batch, @cold_batch])

    assert read(ctx, cold.pid, ["metadata-beta", "metadata-alpha"], false) ===
             expected(ctx, [@beta, @alpha], false, [])

    assert_batches(ctx, [@first_batch, @promoted_batch, @cold_batch])

    assert read(
             ctx,
             cold.pid,
             ["metadata-beta", "metadata-absent", "metadata-alpha", "metadata-beta"],
             true
           ) ===
             expected(ctx, [@beta, @alpha], true, ["metadata-absent"])

    assert_batches(ctx, [@first_batch, @promoted_batch, @cold_batch, @missing_batch])
    assert_empty_loaded(ctx, cold.pid)
    assert_controls(ctx)
    assert_idle(cold.pid)
    close(cold)
    assert_controls(ctx)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    close_provider(ctx)
    assert_controls(ctx)
  end

  defp expected(ctx, apps, tools, missing) do
    projected =
      Enum.map(apps, fn app ->
        slug = if app["id"] === "metadata-alpha", do: "owned-alpha", else: "owned-beta"
        app = Map.put(app, "installUrl", ctx.fixture.url <> "/apps/" <> slug <> "/" <> app["id"])
        if tools, do: app, else: Map.put(app, "toolSummaries", nil)
      end)

    %{"apps" => projected, "missingAppIds" => missing}
  end

  defp read(ctx, pid, ids, tools) do
    response =
      call(ctx, pid, "app/read", %{"appIds" => ids, "threadId" => nil, "includeTools" => tools})

    assert :ok = Schema.validate(schema("v2/AppsReadResponse.json"), response, max_depth: 64)
    assert_controls(ctx)
    response
  end

  defp assert_batches(ctx, expected) do
    batches = rows(ctx, "batch")
    assert Enum.map(batches, & &1["body"]) === expected
    assert Enum.map(batches, & &1["sequence"]) === Enum.to_list(1..length(expected))

    for batch <- batches do
      assert is_binary(batch["raw"]) and byte_size(batch["raw"]) <= 65_536
      assert batch["size"] === byte_size(batch["raw"])
      assert JSON.decode!(batch["raw"]) === batch["body"]
    end
  end

  defp assert_controls(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp rows(ctx, type) do
    data =
      snapshot(Path.join(ctx.root, "ordinary-app-metadata-journal.json")).bytes |> JSON.decode!()

    assert length(data["events"]) <= 256
    Enum.filter(data["events"], &(&1["event"] == type))
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "CODEX_APP_SERVER_CHATGPT_BASE_URL" => ctx.fixture.url <> "/backend-api",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_app_metadata", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert {:ok, []} = Session.drain(pid, 256)
  end

  defp close(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    assert [%{"pid" => native}] = rows(ctx, "fixture_started")
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    refute File.exists?("/proc/#{native}")
    assert [%{"pid" => ^native}] = rows(ctx, "fixture_closed")
  end

  defp assert_inventory(ledger) do
    warm =
      ~w(initialize initialized server/diagnostics thread/loaded/list app/read app/read app/read app/read app/read thread/loaded/list)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list app/read app/read app/read app/read thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 17 and length(Enum.uniq(ids)) === 17
    assert length(replies) === 17
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 2_097_152
    bytes = File.read!(path)
    assert byte_size(bytes) <= 2_097_152
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-app-metadata-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
