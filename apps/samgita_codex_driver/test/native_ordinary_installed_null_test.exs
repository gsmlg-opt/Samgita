defmodule SamgitaCodexDriver.NativeOrdinaryInstalledNullTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_installed_null_fixture.py", __DIR__)
  @script_sha "420480edbac94f69dce752a2bf191fbf2d403971c8b728b1b11d152ca027ecb2"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema Path.expand(
            "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/PluginInstalledResponse.json",
            __DIR__
          )
  @schema_sha "8afc8a16fa5c21d67f66d1855bf29890bad10a6229bafc960b3503281fc878e2"
  @null_sha "b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb"
  @null_bytes """
  {
    "type": "null"
  }
  """
  @remote "plugins~Plugin_owned_null_snapshot"
  @name "owned-null-snapshot"
  @market "created-by-me-remote"
  @marker "Owned null snapshot bundle λ🙂\n"
  @skill "---\nname: notes\ndescription: Owned null snapshot notes\n---\nOwned inert snapshot β🙂\n"

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
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, bytes}, :ok, state) do
      case record(state, :in, bytes) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_, :ok, _), do: {:cont, :ok}

    defp record(state, direction, bytes) do
      Agent.get_and_update(state.capture, fn ledger ->
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 64 and byte_size(bytes) <= limit and
             ledger.bytes + byte_size(bytes) <= 1_048_576 do
          frame = %{direction: direction, encoded: bytes, wire: JSON.decode!(bytes)}
          {:ok, %{frames: ledger.frames ++ [frame], bytes: ledger.bytes + byte_size(bytes)}}
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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert is_binary(System.find_executable("openssl")),
           "BLOCKED_ENV: owned listener setup needs OpenSSL"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    assert hash(File.read!(@schema)) === @schema_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-installed-null-#{Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)}"
      )

    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-installed-null")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)
    ctx = %{binary: Path.expand(binary), root: root, fixture: fixture, resources: resources}
    on_exit(fn -> close_provider(ctx) end)
    config = Path.join(fixture.codex_home, "config.toml")
    disabled = File.read!(config)
    marker = "plugins = false\nremote_plugin = false\n"
    assert length(:binary.matches(disabled, marker)) === 1

    enabled =
      String.replace(disabled, marker, "plugins = true\nremote_plugin = true\n", global: false)

    paths = [
      @script,
      @base,
      @schema,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json")
    ]

    Map.merge(ctx, %{
      config: config,
      disabled: disabled,
      enabled: enabled,
      inputs: Map.new(paths, &{&1, File.read!(&1)}),
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    })
  end

  test "committed remote installed snapshot returns present null while new sync stays held",
       ctx do
    native = start(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}, "owned-null-before") ===
             %{"data" => [], "nextCursor" => nil}

    assert rows(ctx, "installed") === [] and rows(ctx, "bundle") === []
    assert File.read!(ctx.config) === ctx.disabled
    pending = ctx.config <> ".pending"
    File.write!(pending, ctx.enabled, [:exclusive])
    File.rename!(pending, ctx.config)

    # The awaited native reconcile commits the snapshot and drops its sync
    # permit before the handler can return this response. No cache is authored.
    result =
      call(
        ctx,
        native.pid,
        "plugin/reconcile",
        %{"reason" => "Owned null snapshot publication"},
        "owned-null-reconcile"
      )

    assert [%{"id" => id, "hasSkills" => true}] =
             Enum.map(result["changedPlugins"], &Map.take(&1, ~w(id hasSkills)))

    assert id === @name <> "@" <> @market
    assert result["failedRemotePluginIds"] === []
    assert result["failedMaterializationRemotePluginIds"] === []
    bundle = assert_bundle(ctx)

    await(
      fn ->
        length(rows(ctx, "installed_response_sent")) === 1 and
          length(rows(ctx, "bundle_response_sent")) === 1
      end,
      now() + 5_000
    )

    assert call(ctx, native.pid, "thread/loaded/list", %{}, "owned-null-after-reconcile") ===
             %{"data" => [], "nextCursor" => nil}

    # This read uses the committed cache. Its separate background GET is
    # intentionally held; that operation is never claimed completed.
    installed = call(ctx, native.pid, "plugin/installed", %{"cwds" => []}, 4572)
    [marketplace] = Enum.filter(installed["marketplaces"], &(&1["name"] === @market))
    [plugin] = marketplace["plugins"]

    assert Map.take(plugin, ~w(id remotePluginId name)) === %{
             "id" => @name <> "@" <> @market,
             "remotePluginId" => @remote,
             "name" => @name
           }

    assert Map.fetch!(marketplace, "path") === nil
    document = JSON.decode!(File.read!(@schema))

    node =
      document["definitions"]["PluginMarketplaceEntry"]["properties"]["path"]["anyOf"]
      |> Enum.fetch!(1)

    assert node === %{"type" => "null"}
    assert hash(@null_bytes) === @null_sha and JSON.decode!(@null_bytes) === node
    assert :ok = Schema.validate(node, Map.fetch!(marketplace, "path"), max_depth: 8)
    await(fn -> length(rows(ctx, "second_held")) === 1 end, now() + 5_000)
    assert_http(ctx, false)
    assert assert_bundle(ctx) === bundle

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert_controls(ctx)

    # Deliberate owned shutdown cancels the still-held background request.
    # Reaping and ACK consumption precede releasing its fixture handler.
    close_native(ctx, native)
    assert_http(ctx, false)
    close_provider(ctx)
    assert_http(ctx, true)
    assert assert_bundle(ctx) === bundle
    assert_controls(ctx)
    assert_inventory(ctx)
  end

  defp start(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
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
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args: args,
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
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_CA_CERTIFICATE" =>
                        Path.join(ctx.root, "ordinary-installed-null-tls/ca.pem"),
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    :atomics.put(ctx.resources, 2, 1)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      :atomics.put(ctx.resources, 2, 2)
    end)

    id = "owned-null-initialize"
    info = %{"name" => "owned_installed_null", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = reply} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    exchange(ctx, wire, reply)
    native = call(ctx, pid, "server/diagnostics", %{}, "owned-null-diagnostics")["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    assert {:os_pid, helper} = Port.info(connection.port, :os_pid)
    %{pid: pid, connection: connection, native: native, helper: helper}
  end

  defp call(ctx, pid, method, params, id) do
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = reply} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    exchange(ctx, wire, reply)
    result
  end

  defp exchange(ctx, wire, reply) do
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.encoded === JSON.encode!(wire) and sent.wire === wire
    assert received.wire === reply and JSON.decode!(received.encoded) === reply

    for {frame, expected} <- [{sent, wire}, {received, reply}] do
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64, max_bytes: 131_072)
      assert decoded === expected
    end

    assert Enum.sort(Map.keys(reply)) === ~w(id result)
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list plugin/reconcile thread/loaded/list plugin/installed)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 6 and length(replies) === 6
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 6
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)

    refute Enum.any?(
             frames(ctx, :in),
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert [%{wire: %{"id" => 4572}}] =
             Enum.filter(requests, &(&1.wire["method"] === "plugin/installed"))
  end

  defp assert_bundle(ctx) do
    root =
      Path.join(ctx.fixture.codex_home, "plugins/cache/created-by-me-remote/owned-null-snapshot")

    manifest = Path.join(root, "1.0.0/.codex-plugin/plugin.json")
    marker = Path.join(root, "1.0.0/marker.txt")
    skill = Path.join(root, "1.0.0/skills/notes/SKILL.md")
    identity = Path.join(root, ".codex-remote-plugin-install.json")
    assert JSON.decode!(File.read!(manifest)) === %{"name" => @name, "version" => "1.0.0"}
    assert File.read!(marker) === @marker and File.read!(skill) === @skill
    assert JSON.decode!(File.read!(identity))["remote_plugin_id"] === @remote
    Map.new([manifest, marker, skill, identity], &{&1, File.read!(&1)})
  end

  defp assert_http(ctx, closed) do
    path = "/backend-api/ps/plugins/installed?limit=200&includeDownloadUrls=true"

    assert rows(ctx, "installed") === [
             %{"event" => "installed", "sequence" => 1, "path" => path},
             %{"event" => "installed", "sequence" => 2, "path" => path}
           ]

    assert rows(ctx, "installed_response_sent") === [
             %{"event" => "installed_response_sent", "sequence" => 1}
           ]

    assert rows(ctx, "second_held") === [%{"event" => "second_held", "sequence" => 2}]
    assert length(rows(ctx, "bundle")) === 1

    assert rows(ctx, "bundle_response_sent") === [
             %{"event" => "bundle_response_sent", "sequence" => 1}
           ]

    expected =
      if closed, do: [%{"event" => "second_closed_without_response", "sequence" => 2}], else: []

    assert rows(ctx, "second_closed_without_response") === expected
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_write") === []
    received = rows(ctx, "http_received")
    auxiliary = rows(ctx, "auxiliary_get") |> Enum.map(& &1["path"])

    allowed =
      ~w(/backend-api/wham/config/bundle /backend-api/wham/accounts/check /backend-api/wham/settings/user)

    assert length(auxiliary) <= 3 and length(Enum.uniq(auxiliary)) === length(auxiliary)
    assert Enum.all?(auxiliary, &(&1 in allowed))
    business = Enum.reject(received, &(&1["path"] in allowed))

    assert business === [
             %{"event" => "http_received", "listener" => "metadata", "path" => path},
             %{
               "event" => "http_received",
               "listener" => "bundle",
               "path" => "/bundles/owned-null-v1"
             },
             %{"event" => "http_received", "listener" => "metadata", "path" => path}
           ]

    assert Enum.map(Enum.filter(received, &(&1["path"] in allowed)), & &1["path"]) === auxiliary
    assert length(received) === 3 + length(auxiliary)

    assert read_journal(ctx)["counts"] === %{
             "installed" => 2,
             "bundle" => 1,
             "http" => length(received)
           }
  end

  defp assert_controls(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(File.read!(path) === bytes)
    assert File.read!(ctx.config) === ctx.enabled
    assert ModelFixture.requests(ctx.fixture) === [] and File.ls!(ctx.fixture.workspace) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
  end

  defp close_native(ctx, native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
    refute File.exists?("/proc/#{native.helper}")
    :atomics.put(ctx.resources, 2, 2)
  end

  defp close_provider(ctx) do
    try do
      if rows(ctx, "fixture_closed") === [] do
        assert {:ok, _} = Stdio.send(ctx.fixture.transport, JSON.encode!(%{"close" => true}))
        await(fn -> rows(ctx, "fixture_closed") != [] end, now() + 5_000)
      end
    after
      assert :ok = ModelFixture.close(ctx.fixture)
    end

    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    assert [%{"pid" => helper}] = rows(ctx, "fixture_started")
    assert [%{"pid" => ^helper}] = rows(ctx, "fixture_closed")
    refute File.exists?("/proc/#{helper}")
    :atomics.put(ctx.resources, 1, 2)
  end

  defp rows(ctx, kind) do
    ctx |> read_journal() |> Map.fetch!("events") |> Enum.filter(&(&1["event"] === kind))
  end

  defp read_journal(ctx) do
    path = Path.join(ctx.root, "ordinary-installed-null-journal.json")
    assert File.stat!(path).size <= 131_072
    document = path |> File.read!() |> JSON.decode!()
    assert length(document["events"]) <= 64
    document
  end

  defp frames(ctx, direction),
    do: Agent.get(ctx.capture, &Enum.filter(&1.frames, fn row -> row.direction === direction end))

  defp await(predicate, deadline) do
    unless predicate.() do
      assert now() < deadline, "Owned installed null observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
