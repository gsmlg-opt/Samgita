defmodule SamgitaCodexDriver.NativeOrdinaryShareCheckoutDeleteTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_share_checkout_delete_fixture.py", __DIR__)
  @script_sha "2f0faa131dc0802e9f6075c6d39c373ebe197796ac62e6ddf9f209cf6c0d9797"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @tls_helper Path.expand("../../../scripts/codex/ordinary_remote_lifecycle_fixture.py", __DIR__)
  @tls_helper_sha "4b16350a181fa2bd002cd4d90380e6797dd7d8ed3e36f2fb36570db32a2b37ca"
  @stdio_helper Path.join(__DIR__, "support/stdio_session_fixture.ex")
  @stdio_helper_sha "a164a57adff4cba26360a7e2788b8c3e9e6829a0a5e77eae28e857c29dc201a0"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/PluginShareCheckoutParams.json" =>
      "25fd868fff9500ff244150a4ecd36322c0d31b339a4709649594b79aa1349185",
    "v2/PluginShareCheckoutResponse.json" =>
      "d6271afa9bba5531574ba255d22b03f70fe10b8ef159185355625d92b6f9fac6",
    "v2/PluginShareDeleteParams.json" =>
      "d422a3fdecf91612bdf839d4fea6f1cddccb794869dc03ad3b8998bcb8e27fff",
    "v2/PluginShareDeleteResponse.json" =>
      "ae881a7f898f5287354de5adf6f42094cef9029a9b9376bfd12aa1b0fe0b3106",
    "v2/PluginShareListResponse.json" =>
      "d349a496947956fd5f4d125b8348faa2ef0c91daf7f3cd74ae0616f55c8e328b"
  }
  @id_node_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_node_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @checkout "plugin/share/checkout"
  @delete "plugin/share/delete"
  @checkout_ids [-1, "-1"]
  @delete_id 1_514_001
  @remote "plugins~Plugin_owned_ordinary_checkout_delete"
  @name "ordinary-share-checkout-delete"
  @version "3.4.0"
  @manifest ~s({"name":"ordinary-share-checkout-delete","version":"3.4.0"}\n)
  @marker "Owned ordinary checkout marker λ🙂\n"
  @edited_marker "Owned explicit local checkout edit γ🙂\n"
  @skill "---\nname: notes\ndescription: Owned ordinary checkout notes\n---\nKeep the independent project notes β🙂.\n"

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
          case record_events(next.capture, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(capture, events) do
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(capture, :in, encoded) do
            :ok -> {:cont, :ok}
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction === :out, do: 8_192, else: 131_072

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

    for {path, expected} <- [
          {@script, @script_sha},
          {@base, @base_sha},
          {@tls_helper, @tls_helper_sha},
          {@stdio_helper, @stdio_helper_sha}
        ],
        do: assert(hash(File.read!(path)) === expected)

    for {relative, expected} <- @schemas,
        do: assert(hash(File.read!(schema_path(relative))) === expected)

    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    assert is_binary(System.find_executable("openssl")),
           "BLOCKED_ENV: fixed owned HTTPS listener setup requires OpenSSL"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-share-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))

    ctx = %{
      root: root,
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      bin: Path.join(root, "bin"),
      requests: Path.join(root, "requests.json"),
      python: python,
      binary: Path.expand(binary),
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    provider = start_provider(ctx)
    config = Path.join(ctx.codex, "config.toml")
    startup = File.read!(config)
    assert byte_size(startup) <= 16_384

    enabled =
      Enum.reduce(["plugins", "plugin_sharing"], startup, fn feature, text ->
        fragment = "\n#{feature} = false\n"
        assert length(:binary.matches(text, fragment)) === 1
        String.replace(text, fragment, "\n#{feature} = true\n", global: false)
      end)

    paths =
      [
        @script,
        @base,
        @tls_helper,
        @stdio_helper,
        ctx.requests,
        Path.join(ctx.codex, "models.json"),
        Path.join(ctx.root, "ordinary-share-checkout-bundle.tar.gz"),
        Path.join(ctx.bin, "sh")
      ] ++ Enum.map(Map.keys(@schemas), &schema_path/1)

    Map.merge(ctx, %{
      provider: provider,
      config: config,
      startup: startup,
      enabled: enabled,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    })
  end

  test "native share checkout survives a cold local edit and deletion removes only the share mapping",
       ctx do
    deadline = now() + 30_000
    refute File.exists?(checkout_path(ctx))
    refute File.exists?(marketplace_path(ctx))
    refute File.exists?(mapping_path(ctx))
    assert_remote(ctx, true)
    warm = start_native(ctx)
    set_features(ctx, true)
    result = checkout(ctx, warm.pid, Enum.at(@checkout_ids, 0))
    assert result === expected_result(ctx)
    assert_files(ctx, @marker)
    assert mapping(ctx) === %{@remote => checkout_path(ctx)}
    assert_marketplace(ctx)
    assert_payload(ctx)
    assert_backend(ctx, :warm)
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx, true)
    mapping_before = snapshot(mapping_path(ctx))

    # This one explicit owned content edit precedes both the cold request and
    # its independent backend observation. It is not a repeated remote action.
    File.write!(Path.join(checkout_path(ctx), "marker.txt"), @edited_marker)
    assert_files(ctx, @edited_marker)
    assert snapshot(mapping_path(ctx)) === mapping_before
    close_native(warm)
    prefix = frames(ctx)
    set_features(ctx, false)
    cold = start_native(ctx)
    assert cold.native !== warm.native and cold.instance !== warm.instance
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    assert_files(ctx, @edited_marker)
    assert snapshot(mapping_path(ctx)) === mapping_before
    set_features(ctx, true)
    assert checkout(ctx, cold.pid, Enum.at(@checkout_ids, 1)) === result
    assert_files(ctx, @edited_marker)
    assert mapping(ctx) === %{@remote => checkout_path(ctx)}
    assert snapshot(mapping_path(ctx)) === mapping_before
    assert_marketplace(ctx)
    assert_payload(ctx)
    assert_backend(ctx, :cold)
    assert_remote(ctx, true)

    assert call(ctx, cold.pid, %{
             "id" => @delete_id,
             "method" => @delete,
             "params" => %{"remotePluginId" => @remote}
           }) === %{}

    assert_physical_owner(ctx, @delete, 82, [@delete_id])
    # Deletion's response alone is not the effect oracle: a separate dependency
    # record, real mapping-file absence and retained local bytes are all required.
    refute File.exists?(mapping_path(ctx))
    assert_files(ctx, @edited_marker)
    assert_marketplace(ctx)
    assert_remote(ctx, false)

    assert read_json(ctx, "ordinary-share-delete-effect.json") === %{
             "remotePluginId" => @remote,
             "deleted" => true,
             "pluginPath" => checkout_path(ctx),
             "files" => expected_files(@edited_marker),
             "mapping" => %{@remote => checkout_path(ctx)}
           }

    assert call(ctx, cold.pid, "plugin/share/list", %{}) === %{"data" => []}
    assert_backend(ctx, :deleted)
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    assert_physical_owner(ctx, @checkout, 81, @checkout_ids)
    assert_controls(ctx, true)
    assert_inventory(ctx)
    assert now() < deadline
    close_native(cold)
    assert Enum.take(frames(ctx), length(prefix)) === prefix
    assert_files(ctx, @edited_marker)
    assert_marketplace(ctx)
    refute File.exists?(mapping_path(ctx))
    assert_remote(ctx, false)
    effect = snapshot(Path.join(ctx.root, "ordinary-share-delete-effect.json"))
    close_provider(ctx.provider)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.provider.native}
           ]

    assert_backend(ctx, :deleted)
    assert snapshot(Path.join(ctx.root, "ordinary-share-delete-effect.json")) === effect
    assert_controls(ctx, true)
    assert_inventory(ctx)
  end

  defp checkout(ctx, pid, id) do
    params = %{"remotePluginId" => @remote}
    assert :ok = Schema.validate(schema("v2/PluginShareCheckoutParams.json"), params)
    result = call(ctx, pid, %{"id" => id, "method" => @checkout, "params" => params})
    assert :ok = Schema.validate(schema("v2/PluginShareCheckoutResponse.json"), result)
    result
  end

  defp expected_result(ctx),
    do: %{
      "remotePluginId" => @remote,
      "pluginId" => @name <> "@codex-curated",
      "pluginName" => @name,
      "pluginPath" => checkout_path(ctx),
      "marketplaceName" => "codex-curated",
      "marketplacePath" => marketplace_path(ctx),
      "remoteVersion" => @version
    }

  defp expected_files(marker),
    do: %{
      ".codex-plugin/plugin.json" => @manifest,
      "marker.txt" => marker,
      "skills/notes/SKILL.md" => @skill
    }

  defp assert_files(ctx, marker) do
    for {relative, expected} <- expected_files(marker),
        do: assert(File.read!(Path.join(checkout_path(ctx), relative)) === expected)

    assert Enum.sort(File.ls!(checkout_path(ctx))) === [".codex-plugin", "marker.txt", "skills"]
    assert File.ls!(Path.join(checkout_path(ctx), ".codex-plugin")) === ["plugin.json"]
    assert File.ls!(Path.join(checkout_path(ctx), "skills")) === ["notes"]
    assert File.ls!(Path.join(checkout_path(ctx), "skills/notes")) === ["SKILL.md"]
    assert File.ls!(Path.join(ctx.home, "plugins")) === [@name]
  end

  defp assert_marketplace(ctx) do
    marketplace = snapshot(marketplace_path(ctx)).bytes |> JSON.decode!()
    assert marketplace["name"] === "codex-curated"
    assert [plugin] = marketplace["plugins"]
    # Observe only the ordinary identity/source association. Required native
    # policy/default fields remain opaque and receive no behavior credit.
    assert Map.take(plugin, ~w(name source)) === %{
             "name" => @name,
             "source" => %{"source" => "local", "path" => "./plugins/" <> @name}
           }
  end

  defp assert_payload(ctx) do
    bytes = snapshot(Path.join(ctx.root, "ordinary-share-checkout-bundle.tar.gz")).bytes
    assert byte_size(bytes) <= 131_072
    tar = :zlib.gunzip(bytes)
    assert byte_size(tar) <= 131_072
    assert {:ok, entries} = :erl_tar.extract({:binary, tar}, [:memory])

    assert Map.new(entries, fn {name, content} -> {List.to_string(name), content} end) ===
             expected_files(@marker)

    assert rows(ctx, "bundle") === [
             %{
               "event" => "bundle",
               "path" => "/bundles/ordinary-checkout-v1",
               "size" => byte_size(bytes),
               "sha256" => hash(bytes)
             }
           ]
  end

  defp assert_backend(ctx, stage) do
    first = [
      %{
        "event" => "detail",
        "sequence" => 1,
        "path" => detail_path(),
        "query" => %{"includeDownloadUrls" => ["true"]}
      },
      %{
        "event" => "scope",
        "sequence" => 1,
        "path" => "/backend-api/ps/plugins/installed",
        "query" => %{"scope" => ["WORKSPACE"]},
        "items" => []
      }
    ]

    assert [bundle] = rows(ctx, "bundle")
    expected = first ++ [bundle]

    expected =
      if stage in [:cold, :deleted],
        do:
          expected ++
            [
              %{
                "event" => "detail",
                "sequence" => 2,
                "path" => detail_path(),
                "query" => %{"includeDownloadUrls" => ["true"]}
              },
              %{
                "event" => "scope",
                "sequence" => 2,
                "path" => "/backend-api/ps/plugins/installed",
                "query" => %{"scope" => ["WORKSPACE"]},
                "items" => []
              }
            ],
        else: expected

    expected =
      if stage === :deleted,
        do:
          expected ++
            [
              %{
                "event" => "delete",
                "path" => "/backend-api/public/plugins/workspace/" <> @remote,
                "status" => 204,
                "remotePluginId" => @remote
              },
              %{
                "event" => "created",
                "path" => "/backend-api/ps/plugins/workspace/created",
                "query" => %{"limit" => ["200"]},
                "items" => []
              }
            ],
        else: expected

    functional = ~w(detail scope bundle delete created)
    assert Enum.filter(journal(ctx), &(&1["event"] in functional)) === expected
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert [%{"pid" => native}] = rows(ctx, "fixture_started")
    assert native === ctx.provider.native

    assert Enum.all?(
             journal(ctx),
             &(&1["event"] in (functional ++ ~w(fixture_started fixture_closed startup_read)))
           )
  end

  defp assert_physical_owner(ctx, method, index, ids) do
    sent = Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["method"] === method))
    assert Enum.map(sent, & &1.wire["id"]) === ids
    root = schema("ClientRequest.json")
    variants = Map.fetch!(root, "oneOf")

    assert [selected] =
             Enum.filter(
               variants,
               &(get_in(&1, ["properties", "method", "enum"]) === [method])
             )

    assert selected === Enum.at(variants, index)
    node = selected |> Map.fetch!("properties") |> Map.fetch!("id")
    assert node === %{"$ref" => "#/definitions/RequestId"}
    assert JSON.decode!(@id_node_bytes) === node
    assert hash(@id_node_bytes) === @id_node_sha
    definitions = Map.fetch!(root, "definitions")

    assert Map.fetch!(definitions, "RequestId") === %{
             "anyOf" => [
               %{"type" => "string"},
               %{"format" => "int64", "type" => "integer"}
             ]
           }

    for frame <- sent do
      assert :ok = Schema.validate(Map.put(node, "definitions", definitions), frame.wire["id"])

      assert :ok =
               Schema.validate(Map.put(selected, "definitions", definitions), frame.wire,
                 max_depth: 32
               )

      assert :ok = Schema.validate(root, frame.wire, max_depth: 32)
      assert byte_size(frame.encoded) <= 8_192
    end
  end

  defp assert_inventory(ctx) do
    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))

    expected =
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/share/checkout thread/loaded/list) ++
        ~w(initialize initialized server/diagnostics thread/loaded/list plugin/share/checkout plugin/share/delete plugin/share/list thread/loaded/list)

    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        frames(ctx),
        &(&1.direction === :in and Map.has_key?(&1.wire, "id") and
            not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 12 and length(Enum.uniq(ids)) === 12
    assert length(responses) === 12
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    assert Enum.map(Enum.filter(requests, &(&1.wire["method"] === @checkout)), & &1.wire["id"]) ===
             @checkout_ids

    assert [%{wire: %{"id" => @delete_id}}] =
             Enum.filter(requests, &(&1.wire["method"] === @delete))
  end

  defp assert_controls(ctx, enabled) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === if(enabled, do: ctx.enabled, else: ctx.startup)
    assert File.read!(ctx.requests) |> JSON.decode!() === []
    assert File.ls!(ctx.workspace) === []
    assert Path.wildcard(Path.join(ctx.codex, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
  end

  defp set_features(ctx, enabled) do
    before = if enabled, do: ctx.startup, else: ctx.enabled
    after_value = if enabled, do: ctx.enabled, else: ctx.startup
    assert File.read!(ctx.config) === before
    pending = ctx.config <> ".ordinary-pending"
    File.write!(pending, after_value, [:exclusive])
    File.rename!(pending, ctx.config)
    assert File.read!(ctx.config) === after_value
  end

  defp assert_remote(ctx, exists),
    do:
      assert(
        read_json(ctx, "ordinary-share-remote-state.json") ===
          %{"remotePluginId" => @remote, "exists" => exists}
      )

  defp mapping(ctx),
    do:
      snapshot(mapping_path(ctx)).bytes
      |> JSON.decode!()
      |> Map.fetch!("localPluginPathsByRemotePluginId")

  defp checkout_path(ctx), do: Path.join([ctx.home, "plugins", @name])
  defp marketplace_path(ctx), do: Path.join(ctx.home, ".agents/plugins/marketplace.json")
  defp mapping_path(ctx), do: Path.join(ctx.codex, ".tmp/plugin-share-local-paths-v1.json")
  defp detail_path, do: "/backend-api/ps/plugins/" <> @remote

  defp start_provider(ctx) do
    assert {:ok, transport} =
             Stdio.open(
               executable: ctx.python,
               args: [
                 @script,
                 "--codex-home",
                 ctx.codex,
                 "--workspace",
                 ctx.workspace,
                 "--requests-file",
                 ctx.requests,
                 "--scenario",
                 "ordinary-share-checkout-delete"
               ],
               cwd: ctx.workspace,
               inherit_env: [],
               max_message_bytes: 8_192,
               env: %{
                 "HOME" => ctx.home,
                 "CODEX_HOME" => ctx.codex,
                 "TMPDIR" => Path.join(ctx.root, "tmp"),
                 "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                 "PYTHONDONTWRITEBYTECODE" => "1"
               }
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = startup["pid"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(ctx.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    %{transport: transport, identity: identity, native: native, url: startup["url"]}
  end

  defp provider_startup(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0, "Owned ordinary share dependency startup deadline"
    assert byte_size(bytes) <= 8_192

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected ordinary share dependency startup output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} ->
            provider_startup(port, bytes <> chunk, deadline)

          {^port, {:exit_status, status}} ->
            flunk("Owned ordinary share dependency startup exit #{status}")
        after
          remaining -> flunk("Owned ordinary share dependency startup deadline")
        end
    end
  end

  defp start_native(ctx) do
    assert File.read!(ctx.config) === ctx.startup
    # Fixed ordinary YOLO setup only. Unlike ordinary_args/1, these explicit
    # arguments leave plugin-positive setup in the owned TOML authoritative.
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
                    cwd: ctx.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
                    env: %{
                      "HOME" => ctx.home,
                      "CODEX_HOME" => ctx.codex,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.bin <> ":/usr/bin:/bin",
                      "SHELL" => "/bin/sh",
                      "NO_PROXY" => "*",
                      "no_proxy" => "*",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "PYTHONDONTWRITEBYTECODE" => "1",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "CODEX_CA_CERTIFICATE" =>
                        Path.join(ctx.root, "ordinary-remote-lifecycle-tls/ca.pem")
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity}
    on_exit(fn -> close_native(native) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_share_checkout_delete", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      ctx,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    os_pid = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @binary_sha
    assert_empty_loaded(ctx, pid)
    Map.merge(native, %{native: os_pid, instance: Session.status(pid).instance_id})
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    assert :ok = Schema.validate_result(:server_response, wire["method"], result)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent, received] = Enum.filter(frames(ctx), &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
  end

  defp assert_empty_loaded(ctx, pid),
    do:
      assert(
        call(ctx, pid, "thread/loaded/list", %{}) ===
          %{"data" => [], "nextCursor" => nil}
      )

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 1_048_576

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )
  end

  defp close_native(native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    close_transport(native.connection, native.identity)
  end

  defp close_provider(provider) do
    if Port.info(provider.transport.port) !== nil,
      do: assert(match?({:ok, _}, Stdio.send(provider.transport, "stop")))

    close_transport(provider.transport, provider.identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp journal(ctx), do: read_json(ctx, "ordinary-share-checkout-delete-journal.json")["events"]
  defp rows(ctx, kind), do: Enum.filter(journal(ctx), &(&1["event"] === kind))
  defp frames(ctx), do: Agent.get(ctx.capture, & &1.frames)

  defp read_json(ctx, relative),
    do: snapshot(Path.join(ctx.root, relative)).bytes |> JSON.decode!()

  defp snapshot(path) do
    # The owned shell is copied from the actual host executable. Its source size
    # is separate from the fixed ceiling for ordinary JSON/text fixture inputs.
    limit =
      if Path.basename(path) === "sh" and Path.basename(Path.dirname(path)) === "bin",
        do: File.stat!("/bin/sh").size,
        else: 1_048_576

    assert File.stat!(path).size <= limit
    bytes = File.read!(path)
    assert byte_size(bytes) <= limit
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(relative), do: schema_path(relative) |> File.read!() |> JSON.decode!()

  defp schema_path(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)

  defp request_id,
    do: "owned-share-checkout-delete-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
