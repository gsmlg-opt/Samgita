defmodule SamgitaCodexDriver.NativeOrdinaryMarketplaceKindsTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_marketplace_kinds_fixture.py", __DIR__)
  @script_sha "468c6a43690707199f921206fc8440c2cace30e8c032b5ab02fda890cb002f02"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @params_sha "bc6b499161306df7082c5a8cc51fd793cd6d28dda93555b12ae299445132270a"
  @response_sha "a405d2514d6236df75130c87c749e0e070b946a889f143a0448bbcd27d1d8501"
  @prefix "/backend-api/ps/plugins/"

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

  setup ctx do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    assert hash(File.read!(schema_path("v2/PluginListParams.json"))) === @params_sha
    assert hash(File.read!(schema_path("v2/PluginListResponse.json"))) === @response_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-marketplace-kinds-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)
    vertical = Map.get(ctx, :marketplace_profile) === :vertical

    scenario =
      if vertical, do: "ordinary-marketplace-vertical", else: "ordinary-marketplace-kinds"

    fixture =
      try do
        ModelFixture.start(root, scenario)
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
      schema_path("v2/PluginListParams.json"),
      schema_path("v2/PluginListResponse.json")
    ]

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      capture: capture,
      vertical: vertical,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  @tag marketplace_profile: :vertical
  test "ordinary vertical source uses its actual curated collection in a fixed separate native profile",
       ctx do
    warm = start(ctx, 1)
    assert_empty_loaded(ctx, warm.pid)
    assert listing(ctx, warm.pid, "vertical", 1) === expected("vertical")
    assert listing(ctx, warm.pid, "vertical", 1) === expected("vertical")
    assert_business(ctx, ["vertical", "vertical"])
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    cold = start(ctx, 2)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_empty_loaded(ctx, cold.pid)
    assert listing(ctx, cold.pid, "vertical", 1) === expected("vertical")
    assert_business(ctx, ["vertical", "vertical", "vertical"])
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    assert_controls(ctx)
    close(cold)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger, :vertical)
    # Only the actual two per-process featured reads occur; plugin startup was
    # disabled during initialization by the existing exact owned helper.
    assert rows(ctx, "startup") === [
             %{
               "event" => "startup",
               "kind" => "featured",
               "sequence" => 1,
               "path" => "/backend-api/plugins/featured",
               "query" => %{"platform" => ["codex"]}
             },
             %{
               "event" => "startup",
               "kind" => "featured",
               "sequence" => 2,
               "path" => "/backend-api/plugins/featured",
               "query" => %{"platform" => ["codex"]}
             }
           ]

    assert rows(ctx, "startup_ready") === []
    close_provider(ctx)
    assert_controls(ctx)
  end

  test "ordinary remote marketplace source selectors preserve distinct descriptive catalogs and cold reads",
       ctx do
    warm = start(ctx, 1)
    assert_empty_loaded(ctx, warm.pid)
    assert listing(ctx, warm.pid, "workspace-directory", 2) === expected("workspace")
    assert listing(ctx, warm.pid, "shared-with-me", 3) === expected("shared")
    assert listing(ctx, warm.pid, "created-by-me-remote", 4) === expected("created")
    assert listing(ctx, warm.pid, "workspace-directory", 2) === expected("workspace")
    assert_business(ctx, ["workspace", "shared", "created", "workspace"])
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    assert_controls(ctx)

    # Immutable manager startup refreshes every already cached catalog scope.
    # The warm native has populated USER and WORKSPACE. Observe both before
    # issuing any cold list; they are separate from the seven explicit reads.
    File.write!(
      Path.join(ctx.root, "cold-start.json"),
      JSON.encode!(%{"phase" => "cold", "cachedScopes" => ["USER", "WORKSPACE"]}),
      [:exclusive]
    )

    cold = start(ctx, 2)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_empty_loaded(ctx, cold.pid)
    assert listing(ctx, cold.pid, "created-by-me-remote", 4) === expected("created")
    assert listing(ctx, cold.pid, "shared-with-me", 3) === expected("shared")
    assert listing(ctx, cold.pid, "workspace-directory", 2) === expected("workspace")

    assert_business(ctx, [
      "workspace",
      "shared",
      "created",
      "workspace",
      "created",
      "shared",
      "workspace"
    ])

    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    assert_controls(ctx)
    close(cold)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    close_provider(ctx)
    assert_controls(ctx)
  end

  # These independent literal projections intentionally omit computed policy,
  # sharing context, installation and permission fields. No values are derived
  # from the dependency reply, fixture function or actual response under test.
  defp expected("workspace"),
    do: %{
      "name" => "workspace-directory",
      "path" => nil,
      "displayName" => "Workspace Directory",
      "plugins" => [
        %{
          "remotePluginId" => "plugins~Plugin_owned_workspace_beta",
          "name" => "owned-workspace-beta",
          "version" => "2.3.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned workspace beta λ🙂",
          "keywords" => ["workspace-metadata", "ordinary-λ", "beta"]
        },
        %{
          "remotePluginId" => "plugins~Plugin_owned_workspace_alpha",
          "name" => "owned-workspace-alpha",
          "version" => "1.0.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned workspace alpha λ🙂",
          "keywords" => ["workspace-metadata", "ordinary-λ", "alpha"]
        }
      ]
    }

  defp expected("shared"),
    do: %{
      "name" => "workspace-shared-with-me-private",
      "path" => nil,
      "displayName" => "Shared with me",
      "plugins" => [
        %{
          "remotePluginId" => "plugins~Plugin_owned_shared_beta",
          "name" => "owned-shared-beta",
          "version" => "2.3.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned shared beta λ🙂",
          "keywords" => ["shared-metadata", "ordinary-λ", "beta"]
        },
        %{
          "remotePluginId" => "plugins~Plugin_owned_shared_alpha",
          "name" => "owned-shared-alpha",
          "version" => "1.0.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned shared alpha λ🙂",
          "keywords" => ["shared-metadata", "ordinary-λ", "alpha"]
        }
      ]
    }

  defp expected("created"),
    do: %{
      "name" => "created-by-me-remote",
      "path" => nil,
      "displayName" => "Created by me",
      "plugins" => [
        %{
          "remotePluginId" => "plugins~Plugin_owned_created_beta",
          "name" => "owned-created-beta",
          "version" => "2.3.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned created beta λ🙂",
          "keywords" => ["created-metadata", "ordinary-λ", "beta"]
        },
        %{
          "remotePluginId" => "plugins~Plugin_owned_created_alpha",
          "name" => "owned-created-alpha",
          "version" => "1.0.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned created alpha λ🙂",
          "keywords" => ["created-metadata", "ordinary-λ", "alpha"]
        }
      ]
    }

  defp expected("vertical"),
    do: %{
      "name" => "openai-curated-remote",
      "path" => nil,
      "displayName" => "OpenAI Curated Remote",
      "plugins" => [
        %{
          "remotePluginId" => "plugins~Plugin_owned_vertical_beta",
          "name" => "owned-vertical-beta",
          "version" => "2.3.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned vertical beta λ🙂",
          "keywords" => ["vertical-metadata", "ordinary-λ", "beta"]
        },
        %{
          "remotePluginId" => "plugins~Plugin_owned_vertical_alpha",
          "name" => "owned-vertical-alpha",
          "version" => "1.0.0",
          "source" => %{"type" => "remote"},
          "displayName" => "Owned vertical alpha λ🙂",
          "keywords" => ["vertical-metadata", "ordinary-λ", "alpha"]
        }
      ]
    }

  defp listing(ctx, pid, kind, enum_index) do
    literal =
      schema("ClientRequest.json")["definitions"]["PluginListMarketplaceKind"]["enum"]
      |> Enum.at(enum_index)

    assert literal === kind
    assert :ok = Schema.validate(%{"enum" => [literal]}, kind)
    params = %{"marketplaceKinds" => [kind], "forceRefetch" => true}
    assert :ok = Schema.validate(schema("v2/PluginListParams.json"), params, max_depth: 64)
    result = call(ctx, pid, "plugin/list", params)
    assert result["marketplaceLoadErrors"] === []
    assert result["featuredPluginIds"] === []
    assert [marketplace] = Map.fetch!(result, "marketplaces")

    projection = %{
      "name" => Map.fetch!(marketplace, "name"),
      "path" => Map.fetch!(marketplace, "path"),
      "displayName" => get_in(marketplace, ["interface", "displayName"]),
      "plugins" =>
        Enum.map(Map.fetch!(marketplace, "plugins"), fn plugin ->
          Map.take(plugin, ["remotePluginId", "name", "version", "source", "keywords"])
          |> Map.put("displayName", get_in(plugin, ["interface", "displayName"]))
        end)
    }

    assert_controls(ctx)
    projection
  end

  defp assert_business(ctx, buckets) do
    expected_catalogs =
      Enum.with_index(buckets, 1)
      |> Enum.map(fn {bucket, index} ->
        {path, query} =
          case bucket do
            "workspace" ->
              {@prefix <> "list", %{"scope" => ["WORKSPACE"], "limit" => ["200"]}}

            "created" ->
              {@prefix <> "list", %{"scope" => ["USER"], "limit" => ["200"]}}

            "shared" ->
              {@prefix <> "workspace/shared", %{"limit" => ["200"]}}

            "vertical" ->
              {@prefix <> "list",
               %{"scope" => ["GLOBAL"], "limit" => ["200"], "collection" => ["vertical"]}}
          end

        %{
          "event" => "business_catalog",
          "sequence" => index,
          "bucket" => bucket,
          "path" => path,
          "query" => query
        }
      end)

    assert rows(ctx, "business_catalog") === expected_catalogs
    installed = rows(ctx, "business_installed")
    assert length(installed) === length(buckets)
    assert Enum.map(installed, & &1["sequence"]) === Enum.to_list(1..length(buckets))

    expected_scopes =
      Enum.map(buckets, fn bucket ->
        case bucket do
          "created" -> ["USER"]
          "vertical" -> ["GLOBAL"]
          _ -> ["WORKSPACE"]
        end
      end)

    assert Enum.map(installed, & &1["query"]["scope"]) === expected_scopes

    assert Enum.all?(
             installed,
             &(&1["path"] === @prefix <> "installed" and map_size(&1["query"]) === 1)
           )
  end

  defp start(%{vertical: true} = ctx, generation) do
    NativeLaunchFixture.local_plugins_after_initialize(
      Path.join(ctx.fixture.codex_home, "config.toml"),
      fn ->
        start_native(ctx, generation, [
          "-c",
          ~s(approval_policy="never"),
          "-c",
          ~s(sandbox_mode="danger-full-access"),
          "-c",
          "features.recommended_plugins=false",
          "app-server",
          "--listen",
          "stdio://"
        ])
      end
    )
  end

  defp start(ctx, generation),
    do:
      start_native(
        ctx,
        generation,
        NativeLaunchFixture.ordinary_args([
          "-c",
          "features.plugins=true",
          "-c",
          "features.remote_plugin=true",
          "-c",
          "features.plugin_sharing=true",
          "app-server",
          "--listen",
          "stdio://"
        ])
      )

  defp start_native(ctx, generation, args) do
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
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_marketplace_kinds", "version" => "0.1.0"}
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

    unless ctx.vertical,
      do: await_startup(ctx, generation, <<>>, System.monotonic_time(:millisecond) + 5_000)

    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp await_startup(ctx, generation, buffer, deadline) do
    port = ctx.fixture.port
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, part}} ->
        buffer = buffer <> part
        assert byte_size(buffer) <= 4096

        case String.split(buffer, "\n", parts: 2) do
          [line, rest] ->
            assert rest === ""

            assert JSON.decode!(line) === %{
                     "event" => "startup_ready",
                     "generation" => generation
                   }

            assert_startup(ctx, generation)

          [_partial] ->
            await_startup(ctx, generation, buffer, deadline)
        end

      {^port, {:exit_status, status}} ->
        flunk("Owned marketplace fixture exited: #{status}")
    after
      remaining -> flunk("Owned marketplace startup response barrier was not reached")
    end
  end

  defp assert_startup(ctx, generation) do
    routes = [
      {"featured", "/backend-api/plugins/featured", %{"platform" => ["codex"]}},
      {"suggested", @prefix <> "suggested/codex", %{"scope" => ["GLOBAL"]}},
      {"catalog", @prefix <> "list", %{"scope" => ["GLOBAL"], "limit" => ["200"]}},
      {"installed_cache", @prefix <> "installed", %{"limit" => ["200"]}},
      {"installed_bundles", @prefix <> "installed",
       %{"limit" => ["200"], "includeDownloadUrls" => ["true"]}}
    ]

    for {kind, path, query} <- routes do
      selected = Enum.filter(rows(ctx, "startup"), &(&1["kind"] === kind))
      assert length(selected) >= generation
      assert length(selected) <= if(kind in ["featured", "catalog"], do: 2, else: 16)
      assert Enum.map(selected, & &1["sequence"]) === Enum.to_list(1..length(selected))
      assert Enum.all?(selected, &(&1["path"] === path and &1["query"] === query))
    end

    assert rows(ctx, "startup_ready") ===
             Enum.map(1..generation, &%{"event" => "startup_ready", "generation" => &1})

    cached = rows(ctx, "startup_cached_catalog") |> Enum.sort_by(& &1["query"]["scope"])

    expected =
      if generation == 1,
        do: [],
        else:
          Enum.map(["USER", "WORKSPACE"], fn scope ->
            %{
              "event" => "startup_cached_catalog",
              "path" => @prefix <> "list",
              "query" => %{"scope" => [scope], "limit" => ["200"]}
            }
          end)

    assert cached === expected
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 64)

    reply = Session.request_native(pid, wire, timeout_ms: 5_000)
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
    assert {:ok, %{"id" => ^id, "result" => result} = response} = reply

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

  defp assert_controls(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp journal(ctx) do
    data =
      snapshot(Path.join(ctx.root, "ordinary-marketplace-kinds-journal.json")).bytes
      |> JSON.decode!()

    assert length(data["events"]) <= 256
    data
  end

  defp rows(ctx, type), do: Enum.filter(journal(ctx)["events"], &(&1["event"] === type))

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

  defp assert_inventory(ledger, profile \\ :remote) do
    {warm, cold, request_count} =
      case profile do
        :remote ->
          {
            ~w(initialize initialized server/diagnostics thread/loaded/list plugin/list plugin/list plugin/list plugin/list thread/loaded/list),
            ~w(initialize initialized server/diagnostics thread/loaded/list plugin/list plugin/list plugin/list thread/loaded/list),
            15
          }

        :vertical ->
          {
            ~w(initialize initialized server/diagnostics thread/loaded/list plugin/list plugin/list thread/loaded/list),
            ~w(initialize initialized server/diagnostics thread/loaded/list plugin/list thread/loaded/list),
            11
          }
      end

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === request_count and length(Enum.uniq(ids)) === request_count
    assert length(replies) === request_count
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

  defp request_id, do: "owned-marketplace-kind-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
