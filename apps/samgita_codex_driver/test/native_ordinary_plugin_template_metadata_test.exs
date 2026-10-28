defmodule SamgitaCodexDriver.NativeOrdinaryPluginTemplateMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_plugin_template_fixture.py", __DIR__)
  @script_sha "8853fd4c91aa4b0c2d2004e96cc397c806e19c9332d3e0927a7da981a2cc839a"
  @read_params_sha "f15952a2828c90501cc32f347c1e1691ea65cd2d97f503ab40e7be08757de74d"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @alpha "plugins~Plugin_metadata_alpha"
  @beta "plugins~Plugin_metadata_beta"
  @empty "plugins~Plugin_metadata_empty"
  @prefix "/backend-api/ps/plugins/"
  @skills [
    %{
      "name" => "metadata-notes",
      "description" => "Owned remote notes λ🙂",
      "shortDescription" => nil,
      "interface" => nil,
      "path" => nil
    }
  ]
  @alpha_templates [
    %{
      "templateId" => "template-alpha",
      "name" => "Alpha template λ🙂",
      "description" => "Alpha descriptive metadata β",
      "category" => "Owned category λ",
      "canonicalConnectorId" => "descriptive-canonical-alpha",
      "logoUrl" => "https://synthetic.invalid/template-alpha/light.svg",
      "logoUrlDark" => "https://synthetic.invalid/template-alpha/dark.svg",
      "materializedAppIds" => [
        "descriptive-app-beta",
        "descriptive-app-alpha",
        "descriptive-app-beta"
      ],
      "reason" => nil
    },
    %{
      "templateId" => "template-minimal",
      "name" => "Minimal template β",
      "description" => nil,
      "category" => nil,
      "canonicalConnectorId" => nil,
      "logoUrl" => nil,
      "logoUrlDark" => nil,
      "materializedAppIds" => [],
      "reason" => nil
    },
    %{
      "templateId" => "template-alpha",
      "name" => "Duplicate template name γ",
      "description" => "Duplicate row must be preserved",
      "category" => nil,
      "canonicalConnectorId" => nil,
      "logoUrl" => nil,
      "logoUrlDark" => nil,
      "materializedAppIds" => ["descriptive-app-duplicate"],
      "reason" => nil
    }
  ]
  @beta_templates [
    %{
      "templateId" => "template-beta",
      "name" => "Beta explicit nulls δ",
      "description" => nil,
      "category" => nil,
      "canonicalConnectorId" => nil,
      "logoUrl" => nil,
      "logoUrlDark" => nil,
      "materializedAppIds" => [],
      "reason" => nil
    }
  ]

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
    assert hash(File.read!(schema_path("v2/PluginReadParams.json"))) === @read_params_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-templates-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-plugin-templates")
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
      schema_path("v2/PluginReadParams.json"),
      schema_path("v2/PluginReadResponse.json")
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

  test "ordinary remote template metadata preserves defaults order duplicates and cold reads",
       ctx do
    warm = start(ctx, 1)
    assert_empty_loaded(ctx, warm.pid)
    # Only descriptive app-template/skill fields are compared. Native summary
    # behavior and nonnull workspace-status reasons are outside this case.
    assert read(ctx, warm.pid, @alpha) === expected(@alpha_templates, @skills)
    assert_backend(ctx, [@alpha])
    assert read(ctx, warm.pid, @beta) === expected(@beta_templates, @skills)
    assert_backend(ctx, [@alpha, @beta])
    assert read(ctx, warm.pid, @empty) === expected([], [])
    assert_backend(ctx, [@alpha, @beta, @empty])
    assert read(ctx, warm.pid, @alpha, true) === expected(@alpha_templates, @skills)
    assert_backend(ctx, [@alpha, @beta, @empty, @alpha])
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    assert_controls(ctx)

    cold = start(ctx, 2)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_empty_loaded(ctx, cold.pid)
    # First cold content RPC queries a different static metadata record, with
    # no runtime load, history hydration, model request or tool invocation.
    assert read(ctx, cold.pid, @beta) === expected(@beta_templates, @skills)
    assert_backend(ctx, [@alpha, @beta, @empty, @alpha, @beta])
    assert read(ctx, cold.pid, @alpha) === expected(@alpha_templates, @skills)
    assert_backend(ctx, [@alpha, @beta, @empty, @alpha, @beta, @alpha])
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    assert_controls(ctx)
    close(cold)
    assert_controls(ctx)
    ledger = Agent.get(ctx.capture, & &1)
    assert Enum.take(ledger.out, length(warm_capture.out)) === warm_capture.out
    assert Enum.take(ledger.in, length(warm_capture.in)) === warm_capture.in
    assert_inventory(ledger)
    close_provider(ctx)
    assert_controls(ctx)
  end

  defp expected(templates, skills),
    do: %{"appTemplates" => templates, "marketplacePath" => nil, "skills" => skills}

  defp read(ctx, pid, id, explicit_null \\ false) do
    params = %{
      "remoteMarketplaceName" => "openai-curated-remote",
      "pluginName" => id
    }

    params = if explicit_null, do: Map.put(params, "marketplacePath", nil), else: params
    params_schema = schema("v2/PluginReadParams.json")
    assert :ok = Schema.validate(params_schema, params, max_depth: 16)
    properties = Map.fetch!(params_schema, "properties")
    remote_name = Map.fetch!(properties, "remoteMarketplaceName")
    assert remote_name === %{"type" => ["string", "null"]}
    assert :ok = Schema.validate(remote_name, Map.fetch!(params, "remoteMarketplaceName"))

    if explicit_null do
      null_path = properties["marketplacePath"]["anyOf"] |> Enum.at(1)
      assert null_path === %{"type" => "null"}
      assert :ok = Schema.validate(null_path, Map.fetch!(params, "marketplacePath"))
    else
      refute Map.has_key?(params, "marketplacePath")
    end

    result = call(ctx, pid, "plugin/read", params)

    plugin = Map.fetch!(result, "plugin")
    document = schema("v2/PluginReadResponse.json")
    definitions = Map.fetch!(document, "definitions")
    templates = Map.fetch!(plugin, "appTemplates")

    metadata_schema = %{
      "$ref" => "#/definitions/AppTemplateSummary",
      "definitions" =>
        Map.take(definitions, ["AppTemplateSummary", "AppTemplateUnavailableReason"])
    }

    for template <- templates,
        do: assert(:ok = Schema.validate(metadata_schema, template, max_depth: 64))

    marketplace = Map.fetch!(plugin, "marketplacePath")

    null_marketplace =
      get_in(definitions, ["PluginDetail", "properties", "marketplacePath", "anyOf"])
      |> Enum.at(1)

    assert :ok = Schema.validate(null_marketplace, marketplace)

    null_skill =
      get_in(definitions, ["SkillSummary", "properties", "path", "anyOf"]) |> Enum.at(1)

    skills =
      Enum.map(Map.fetch!(plugin, "skills"), fn skill ->
        assert :ok = Schema.validate(null_skill, Map.fetch!(skill, "path"))
        Map.take(skill, ["name", "description", "shortDescription", "interface", "path"])
      end)

    assert_controls(ctx)
    %{"appTemplates" => templates, "marketplacePath" => marketplace, "skills" => skills}
  end

  defp assert_backend(ctx, ids) do
    expected =
      Enum.flat_map(Enum.with_index(ids, 1), fn {id, index} ->
        [
          %{"event" => "detail", "sequence" => index, "path" => @prefix <> id, "query" => %{}},
          %{
            "event" => "installed",
            "sequence" => index,
            "path" => @prefix <> "installed",
            "query" => %{"scope" => ["GLOBAL"]}
          }
        ]
      end)

    events = journal(ctx)["events"] |> Enum.filter(&(&1["event"] in ["detail", "installed"]))
    assert events === expected
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
      snapshot(Path.join(ctx.root, "ordinary-plugin-template-journal.json")).bytes
      |> JSON.decode!()

    assert length(data["events"]) <= 256
    data
  end

  defp rows(ctx, type), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == type))

  defp start(ctx, generation) do
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
                      NativeLaunchFixture.ordinary_args([
                        "-c",
                        "features.plugins=true",
                        "-c",
                        "features.remote_plugin=true",
                        "app-server",
                        "--listen",
                        "stdio://"
                      ]),
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
    info = %{"name" => "owned_ordinary_plugin_templates", "version" => "0.1.0"}
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
    await_startup(ctx, generation)
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
  end

  defp await_startup(ctx, generation) do
    await_startup(ctx, generation, <<>>, System.monotonic_time(:millisecond) + 5_000)
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
        flunk("Owned startup metadata fixture exited: #{status}")
    after
      remaining -> flunk("Owned startup metadata response barrier was not reached")
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

    expected =
      for {kind, path, query} <- routes, sequence <- 1..generation do
        %{
          "event" => "startup",
          "kind" => kind,
          "sequence" => sequence,
          "path" => path,
          "query" => query
        }
      end

    assert Enum.sort(rows(ctx, "startup")) === Enum.sort(expected)

    assert rows(ctx, "startup_ready") ===
             Enum.map(1..generation, &%{"event" => "startup_ready", "generation" => &1})
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
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/read plugin/read plugin/read plugin/read thread/loaded/list)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/read plugin/read thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 14 and length(Enum.uniq(ids)) === 14
    assert length(replies) === 14
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

  defp request_id, do: "owned-plugin-template-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
