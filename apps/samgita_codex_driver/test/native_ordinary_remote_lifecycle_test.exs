defmodule SamgitaCodexDriver.NativeOrdinaryRemoteLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_remote_lifecycle_fixture.py", __DIR__)
  @script_sha "4b16350a181fa2bd002cd4d90380e6797dd7d8ed3e36f2fb36570db32a2b37ca"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema Path.expand(
            "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/PluginInstallParams.json",
            __DIR__
          )
  @schema_sha "d6a8ff6356aed22c916cfd5a791ecce34ee2ac509750f690e7d0ef483fec7472"
  @uninstall_schema Path.expand(
                      "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/PluginUninstallParams.json",
                      __DIR__
                    )
  @uninstall_schema_sha "4c9e1da7048fc99ef5269d4c3f4c6c3297dac01992c2756340fa210ae8f800cc"
  @remote "plugins~Plugin_ordinary_remote_lifecycle"
  @market "created-by-me-remote"
  @plugin "ordinary-remote-lifecycle@created-by-me-remote"
  @manifest ~s({"name":"ordinary-remote-lifecycle","version":"1.0.0"}\n)
  @marker "Owned ordinary remote install marker λ🙂\n"
  @skill "---\nname: notes\ndescription: Owned ordinary install notes\n---\nOwned installed skill text β🙂\n"

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
            {:error, error} -> {:error, error, next}
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
            {:error, error} -> {:error, error, next}
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
        limit = if direction == :out, do: 8192, else: 131_072

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

    assert is_binary(System.find_executable("openssl")),
           "BLOCKED_ENV: owned listener setup needs OpenSSL"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    assert hash(File.read!(@schema)) === @schema_sha
    assert hash(File.read!(@uninstall_schema)) === @uninstall_schema_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-remote-lifecycle-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-remote-lifecycle")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      fixture: fixture,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    on_exit(fn -> close_provider(ctx) end)
    config = Path.join(fixture.codex_home, "config.toml")
    startup = File.read!(config)
    marker = "plugins = false\nremote_plugin = false\n"
    assert length(:binary.matches(startup, marker)) === 1

    enabled =
      String.replace(startup, marker, "plugins = true\nremote_plugin = true\n", global: false)

    paths = [
      @script,
      @base,
      @schema,
      @uninstall_schema,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json"),
      Path.join(root, "ordinary-remote-lifecycle-bundle.tar.gz"),
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.merge(ctx, %{
      config: config,
      startup: startup,
      enabled: enabled,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    })
  end

  test "ordinary native remote install publishes its bundle before genuine uninstall removes it",
       ctx do
    native = start(ctx)
    enable_plugins(ctx)
    refute File.exists?(plugin_root(ctx))
    refute File.exists?(Path.join(ctx.root, "ordinary-remote-lifecycle-state.json"))
    assert own_skills(ctx, native.pid) === []

    assert rows(ctx, "detail") === [] and rows(ctx, "install") === [] and
             rows(ctx, "refresh") === []

    # One genuine install, positive metadata publication, then one genuine remote uninstall.
    params = %{
      "marketplacePath" => nil,
      "remoteMarketplaceName" => @market,
      "pluginName" => @remote
    }

    document = @schema |> File.read!() |> JSON.decode!()
    assert Enum.at(document["properties"]["marketplacePath"]["anyOf"], 1) === %{"type" => "null"}
    assert document["properties"]["remoteMarketplaceName"] === %{"type" => ["string", "null"]}
    assert :ok = Schema.validate(document, params, max_depth: 16)

    assert :ok =
             Schema.validate(Enum.at(document["properties"]["marketplacePath"]["anyOf"], 1), nil,
               max_depth: 8
             )

    assert :ok =
             Schema.validate(document["properties"]["remoteMarketplaceName"], @market,
               max_depth: 8
             )

    assert is_map(
             call(ctx, native.pid, %{
               "id" => 4511,
               "method" => "plugin/install",
               "params" => params
             })
           )

    cached = assert_bundle(ctx)

    assert JSON.decode!(File.read!(Path.join(ctx.root, "ordinary-remote-lifecycle-state.json"))) ===
             %{"installed" => @remote}

    await(fn -> length(rows(ctx, "refresh_response_sent")) === 1 end, now() + 5_000)
    assert_backend(ctx, :installed)
    assert await_skills(ctx, native.pid, 8) === [expected_skill(ctx)]
    assert assert_bundle(ctx) === cached
    assert_controls(ctx)

    uninstall = %{"pluginId" => @remote}

    assert :ok =
             Schema.validate(JSON.decode!(File.read!(@uninstall_schema)), uninstall, max_depth: 8)

    assert call(ctx, native.pid, %{
             "id" => "ordinary-lifecycle-uninstall",
             "method" => "plugin/uninstall",
             "params" => uninstall
           }) === %{}

    refute File.exists?(plugin_root(ctx))

    assert JSON.decode!(File.read!(Path.join(ctx.root, "ordinary-remote-lifecycle-state.json"))) ===
             %{"removed" => @remote}

    # This barrier proves the empty refresh response was sent, not async snapshot publication.
    await(fn -> length(rows(ctx, "refresh_response_sent")) === 2 end, now() + 5_000)
    assert_backend(ctx, :removed)
    assert own_skills(ctx, native.pid) === []
    refute File.exists?(plugin_root(ctx))
    assert_controls(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert {:ok, events} = Session.drain(native.pid, 128)

    refute Enum.any?(
             events,
             &(&1.kind === :server_request or
                 &1.wire["method"] in ~w(error turn/started turn/completed))
           )

    assert {:ok, []} = Session.drain(native.pid, 128)
    assert_inventory(ctx)
    close_native(native)
    refute File.exists?(plugin_root(ctx))
    assert_controls(ctx)
    close_provider(ctx)
    assert_backend(ctx, :removed)
    refute File.exists?(plugin_root(ctx))
    assert_controls(ctx)
  end

  defp own_skills(ctx, pid) do
    result =
      call(ctx, pid, "skills/list", %{"cwds" => [ctx.fixture.workspace], "forceReload" => true})

    assert [%{"cwd" => cwd, "skills" => skills, "errors" => []}] = result["data"]
    assert cwd === ctx.fixture.workspace
    assert is_list(skills) and length(skills) <= 32

    skills
    |> Enum.filter(&(&1["pluginId"] === @plugin))
    |> Enum.map(&Map.take(&1, ~w(name description path pluginId)))
  end

  defp await_skills(ctx, pid, remaining) do
    result = own_skills(ctx, pid)

    if result === [] and remaining > 1 do
      receive do
      after
        25 -> :ok
      end

      await_skills(ctx, pid, remaining - 1)
    else
      result
    end
  end

  defp expected_skill(ctx),
    do: %{
      "name" => "ordinary-remote-lifecycle:notes",
      "description" => "Owned ordinary install notes",
      "pluginId" => @plugin,
      "path" => Path.join(plugin_root(ctx), "1.0.0/skills/notes/SKILL.md")
    }

  defp assert_bundle(ctx) do
    version = Path.join(plugin_root(ctx), "1.0.0")

    paths = [
      {Path.join(version, ".codex-plugin/plugin.json"), @manifest},
      {Path.join(version, "marker.txt"), @marker},
      {Path.join(version, "skills/notes/SKILL.md"), @skill}
    ]

    for {path, expected} <- paths, do: assert(File.read!(path) === expected)
    identity = Path.join(plugin_root(ctx), ".codex-remote-plugin-install.json")
    assert JSON.decode!(File.read!(identity))["remote_plugin_id"] === @remote
    Map.new(Enum.map(paths, &elem(&1, 0)) ++ [identity], &{&1, snapshot(&1)})
  end

  defp plugin_root(ctx),
    do:
      Path.join(
        ctx.fixture.codex_home,
        "plugins/cache/created-by-me-remote/ordinary-remote-lifecycle"
      )

  defp assert_backend(ctx, stage) do
    detail_path = "/backend-api/ps/plugins/" <> @remote

    detail = [
      %{
        "event" => "detail",
        "sequence" => 1,
        "path" => detail_path,
        "query" => %{"includeDownloadUrls" => ["true"]},
        "rawQuery" => "includeDownloadUrls=true"
      }
    ]

    detail =
      if stage === :removed,
        do:
          detail ++
            [
              %{
                "event" => "detail",
                "sequence" => 2,
                "path" => detail_path,
                "query" => %{},
                "rawQuery" => ""
              }
            ],
        else: detail

    assert rows(ctx, "detail") === detail

    assert rows(ctx, "scope") === [
             %{
               "event" => "scope",
               "sequence" => 1,
               "path" => "/backend-api/ps/plugins/installed",
               "query" => %{"scope" => ["USER"]},
               "items" => []
             }
           ]

    assert rows(ctx, "install") === [
             %{
               "event" => "install",
               "sequence" => 1,
               "path" => detail_path <> "/install",
               "items" => [@remote],
               "materialized" => true
             }
           ]

    refresh = [
      %{
        "event" => "refresh",
        "sequence" => 1,
        "path" => "/backend-api/ps/plugins/installed",
        "query" => %{"limit" => ["200"]},
        "items" => [@remote]
      }
    ]

    refresh =
      if stage === :removed,
        do:
          refresh ++
            [
              %{
                "event" => "refresh",
                "sequence" => 2,
                "path" => "/backend-api/ps/plugins/installed",
                "query" => %{"limit" => ["200"]},
                "items" => []
              }
            ],
        else: refresh

    assert rows(ctx, "refresh") === refresh

    removed =
      if stage === :removed,
        do: [
          %{
            "event" => "uninstall",
            "sequence" => 1,
            "path" => detail_path <> "/uninstall",
            "items" => [@remote],
            "materialized" => true
          }
        ],
        else: []

    assert rows(ctx, "uninstall") === removed
    payload = File.read!(Path.join(ctx.root, "ordinary-remote-lifecycle-bundle.tar.gz"))

    assert rows(ctx, "bundle") === [
             %{
               "event" => "bundle",
               "sequence" => 1,
               "path" => "/bundles/ordinary-v1",
               "size" => byte_size(payload),
               "sha256" => hash(payload)
             }
           ]

    counts = %{
      "detail" => length(detail),
      "scope" => 1,
      "bundle" => 1,
      "install" => 1,
      "uninstall" => length(removed),
      "refresh" => length(refresh)
    }

    for {kind, count} <- counts do
      expected =
        if count === 0,
          do: [],
          else:
            Enum.map(
              1..count,
              &%{"event" => kind <> "_response_sent", "sequence" => &1}
            )

      assert rows(ctx, kind <> "_response_sent") === expected
    end

    kinds = ~w(detail scope bundle install refresh uninstall)
    observed = all_rows(ctx) |> Enum.filter(&(&1["event"] in kinds)) |> Enum.map(& &1["event"])
    expected = ~w(detail scope bundle install refresh)
    expected = if stage === :removed, do: expected ++ ~w(detail uninstall refresh), else: expected
    assert observed === expected
  end

  defp enable_plugins(ctx) do
    assert File.read!(ctx.config) === ctx.startup
    pending = ctx.config <> ".ordinary-pending"
    File.write!(pending, ctx.enabled, [:exclusive])
    File.rename!(pending, ctx.config)
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === ctx.enabled
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "unexpected_http") === [] and rows(ctx, "fixture_error") === []
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
                        Path.join(ctx.root, "ordinary-remote-lifecycle-tls/ca.pem"),
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_remote_lifecycle", "version" => "1"}
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
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)
    methods = Enum.map(outgoing, & &1.wire["method"])

    assert Enum.take(methods, 5) ===
             ~w(initialize initialized server/diagnostics skills/list plugin/install)

    assert Enum.take(methods, -3) === ~w(plugin/uninstall skills/list thread/loaded/list)
    probes = Enum.drop(methods, 5) |> Enum.drop(-3)
    assert length(probes) in 1..8 and Enum.all?(probes, &(&1 === "skills/list"))
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        frames(ctx, :in),
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(requests) === length(probes) + 7 and length(responses) === length(requests)
    assert length(Enum.uniq(ids)) === length(ids)
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    assert [%{wire: %{"id" => 4511}}] =
             Enum.filter(requests, &(&1.wire["method"] === "plugin/install"))

    assert [%{wire: %{"id" => "ordinary-lifecycle-uninstall"}}] =
             Enum.filter(requests, &(&1.wire["method"] === "plugin/uninstall"))
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    try do
      if rows(ctx, "fixture_closed") === [] do
        path = Path.join(ctx.root, "ordinary-remote-lifecycle-close.json")

        unless File.exists?(path) do
          pending = path <> ".pending"
          File.write!(pending, JSON.encode!(%{"action" => "close"}), [:exclusive])
          File.rename!(pending, path)
        end

        await(fn -> rows(ctx, "fixture_closed") != [] end, now() + 5_000)
      end
    after
      assert :ok = ModelFixture.close(ctx.fixture)
    end

    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    assert [%{"pid" => helper}] = rows(ctx, "fixture_started")
    assert [%{"pid" => ^helper}] = rows(ctx, "fixture_closed")
    await(fn -> not File.exists?("/proc/#{helper}") end, now() + 5_000)
  end

  defp all_rows(ctx) do
    path = Path.join(ctx.root, "ordinary-remote-lifecycle-journal.json")

    if File.exists?(path) do
      rows = snapshot(path).bytes |> JSON.decode!() |> Map.fetch!("events")
      assert length(rows) <= 64
      rows
    else
      []
    end
  end

  defp rows(ctx, event), do: Enum.filter(all_rows(ctx), &(&1["event"] === event))

  defp await(predicate, until) do
    unless predicate.() do
      assert now() < until, "ordinary install observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, until)
    end
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id,
    do: "ordinary-remote-lifecycle-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
