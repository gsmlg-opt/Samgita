defmodule SamgitaCodexDriver.NativeOrdinaryCatalogMetadataNotificationTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_catalog_metadata_fixture.py", __DIR__)
  @script_sha "cd21e46bca341400798105d77707b3768f9a00ecde3025afe787df7be8c3cbd6"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @directory "/backend-api/connectors/directory/list"
  @token "owned catalog β"
  @app_fields ~w(id name distributionChannel iconAssets iconDarkAssets labels logoUrl logoUrlDark pluginDisplayNames)
  @branding_fields ~w(category developer privacyPolicy termsOfService website)
  @metadata_fields ~w(categories developer screenshots seoDescription subCategories version versionId versionNotes)
  @empty_branding %{
    "category" => nil,
    "developer" => nil,
    "privacyPolicy" => nil,
    "termsOfService" => nil,
    "website" => nil
  }
  @empty_metadata %{
    "categories" => nil,
    "developer" => nil,
    "screenshots" => nil,
    "seoDescription" => nil,
    "subCategories" => nil,
    "version" => nil,
    "versionId" => nil,
    "versionNotes" => nil
  }
  @expected [
    %{
      "id" => "catalog-alpha",
      "name" => "Owned Catalog Alpha λ",
      "distributionChannel" => "ORDINARY_CATALOG_METADATA",
      "iconAssets" => %{
        "128_square" => "https://synthetic.invalid/catalog-alpha/128.svg",
        "label-λ" => "opaque alpha asset β"
      },
      "iconDarkAssets" => %{"64_square" => "https://synthetic.invalid/catalog-alpha/dark-64.svg"},
      "labels" => %{"channel" => "Owned display label", "λ" => "β🙂"},
      "logoUrl" => "https://synthetic.invalid/catalog-alpha/light.svg",
      "logoUrlDark" => "https://synthetic.invalid/catalog-alpha/dark.svg",
      "pluginDisplayNames" => [],
      "branding" => %{
        "category" => "Owned branding category λ",
        "developer" => "Owned branding developer β",
        "privacyPolicy" => "https://synthetic.invalid/catalog-alpha/privacy",
        "termsOfService" => "https://synthetic.invalid/catalog-alpha/terms",
        "website" => "https://synthetic.invalid/catalog-alpha/site"
      },
      "appMetadata" => %{
        "categories" => ["Owned category λ", "Other β", "Owned category λ"],
        "developer" => "Owned metadata developer γ",
        "screenshots" => [
          %{
            "url" => "https://synthetic.invalid/catalog-alpha/screenshot.png",
            "fileId" => "owned-screenshot-alpha",
            "userPrompt" => "Show ordinary Alpha λ🙂"
          },
          %{"url" => nil, "fileId" => nil, "userPrompt" => "Screenshot with no link β"}
        ],
        "seoDescription" => "Owned search description λ🙂",
        "subCategories" => ["subcategory-two", "subcategory-one"],
        "version" => "1.2.3-λ",
        "versionId" => "owned-version-alpha",
        "versionNotes" => "Owned version notes β🙂"
      }
    },
    %{
      "id" => "catalog-beta",
      "name" => "Owned Catalog Beta β",
      "distributionChannel" => nil,
      "iconAssets" => nil,
      "iconDarkAssets" => nil,
      "labels" => nil,
      "logoUrl" => nil,
      "logoUrlDark" => nil,
      "pluginDisplayNames" => [],
      "branding" => nil,
      "appMetadata" => nil
    },
    %{
      "id" => "catalog-gamma",
      "name" => "Owned Catalog Gamma γ",
      "distributionChannel" => "",
      "iconAssets" => %{},
      "iconDarkAssets" => %{},
      "labels" => %{},
      "logoUrl" => "",
      "logoUrlDark" => "",
      "pluginDisplayNames" => [],
      "branding" => @empty_branding,
      "appMetadata" => @empty_metadata
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

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-catalog-metadata-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-catalog-metadata")
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
      schema_path("ServerNotification.json"),
      schema_path("v2/AppsListParams.json"),
      schema_path("v2/AppsListResponse.json")
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

  test "native catalog notifications preserve only descriptive metadata across cached and cold reads",
       ctx do
    warm = start(ctx)
    assert_empty_loaded(ctx, warm.pid)
    assert_catalog(ctx, warm.pid, -1)
    assert_directory(ctx, 2)
    assert_catalog(ctx, warm.pid, 1)
    assert_directory(ctx, 2)
    # Client pagination uses the completed native cache; backend pagination
    # and full descriptive update payloads are independent from each page.
    assert_page(
      ctx,
      warm.pid,
      "owned-list-page-zero",
      %{"cursor" => nil, "limit" => 0, "forceRefetch" => false},
      Enum.take(@expected, 1),
      "1",
      1
    )

    assert_directory(ctx, 2)

    assert_page(
      ctx,
      warm.pid,
      "owned-list-page-middle",
      %{"cursor" => "1", "limit" => 1},
      Enum.slice(@expected, 1, 1),
      "2",
      0
    )

    assert_directory(ctx, 2)

    assert_page(
      ctx,
      warm.pid,
      "owned-list-page-final",
      %{"cursor" => "2", "limit" => nil},
      Enum.slice(@expected, 2, 1),
      nil,
      0
    )

    assert_directory(ctx, 2)

    assert_page(
      ctx,
      warm.pid,
      "owned-list-page-terminal",
      %{"cursor" => "3", "limit" => nil},
      [],
      nil,
      0
    )

    assert_directory(ctx, 2)
    # Explicit cache bypass must fetch both real directory pages again.
    assert_page(
      ctx,
      warm.pid,
      "owned-list-force-refetch",
      %{"forceRefetch" => true, "limit" => 100},
      @expected,
      nil,
      1
    )

    assert_directory(ctx, 4)
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    assert_controls(ctx)
    warm_capture = Agent.get(ctx.capture, & &1)
    close(warm)
    assert_controls(ctx)

    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_empty_loaded(ctx, cold.pid)
    # First cold content operation is native catalog discovery. Metadata cache
    # writes belong to the stock process; no rollout/database is synthesized.
    assert_catalog(ctx, cold.pid, "owned-list-cold-漢字🙂")
    assert_directory(ctx, 6)
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

  defp assert_catalog(ctx, pid, id),
    do: assert_page(ctx, pid, id, %{"limit" => 100}, @expected, nil, 1)

  defp assert_page(ctx, pid, id, params, expected, next_cursor, update_count) do
    assert :ok = Schema.validate(schema("v2/AppsListParams.json"), params, max_depth: 64)
    first_incoming = length(Agent.get(ctx.capture, & &1.in))
    result = call(ctx, pid, "app/list", params, id)
    actual_cursor = Map.fetch!(result, "nextCursor")
    cursor_schema = schema("v2/AppsListResponse.json")["properties"]["nextCursor"]
    assert :ok = Schema.validate(cursor_schema, actual_cursor, max_depth: 64)
    assert actual_cursor === next_cursor
    assert project(ctx, Map.fetch!(result, "data")) === expected
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    updates = Enum.filter(events, &(&1.wire["method"] == "app/list/updated"))
    originals = Agent.get(ctx.capture, &Enum.drop(&1.in, first_incoming))
    original_updates = Enum.filter(originals, &(&1.wire["method"] == "app/list/updated"))
    assert length(updates) === update_count
    assert length(original_updates) === update_count

    for {event, original} <- Enum.zip(updates, original_updates) do
      assert original.wire === event.wire
      assert JSON.decode!(original.encoded) === event.wire
      assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 64)
      assert decoded === event.wire
      assert is_integer(decoded["emittedAtMs"]) and decoded["emittedAtMs"] > 0
      assert project(ctx, decoded["params"]["data"]) === @expected
    end

    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert_controls(ctx)
  end

  defp project(ctx, apps) do
    Enum.map(apps, fn app ->
      # Deliberate allowlist: no access/enabled/discoverability, review or
      # install/composer outcome field is read, compared or schema validated.
      ordinary = fields(ctx, app, "AppInfo", @app_fields)

      branding =
        case Map.fetch!(app, "branding") do
          nil -> nil
          data when is_map(data) -> fields(ctx, data, "AppBranding", @branding_fields)
        end

      metadata =
        case Map.fetch!(app, "appMetadata") do
          nil -> nil
          data when is_map(data) -> fields(ctx, data, "AppMetadata", @metadata_fields)
        end

      ordinary |> Map.put("branding", branding) |> Map.put("appMetadata", metadata)
    end)
  end

  defp fields(_ctx, data, type, names) do
    definitions = schema("ServerNotification.json")["definitions"]

    Map.new(names, fn name ->
      value = Map.fetch!(data, name)
      node = get_in(definitions, [type, "properties", name])
      # Only screenshots reference another descriptive type. Do not validate
      # whole AppInfo/AppBranding/AppMetadata objects containing excluded state.
      metadata_schema = Map.put(node, "definitions", Map.take(definitions, ["AppScreenshot"]))
      assert :ok = Schema.validate(metadata_schema, value, max_depth: 64)
      {name, value}
    end)
  end

  defp assert_directory(ctx, count) do
    expected =
      for index <- 1..count do
        query =
          if rem(index, 2) == 1,
            do: %{"external_logos" => ["true"]},
            else: %{"external_logos" => ["true"], "token" => [@token]}

        %{"event" => "directory", "sequence" => index, "path" => @directory, "query" => query}
      end

    assert rows(ctx, "directory") === expected
    methods = Enum.map(rows(ctx, "mcp"), & &1["method"])
    assert "initialize" in methods and "tools/list" in methods
    assert length(methods) <= 32

    assert Enum.all?(
             methods,
             &(&1 in ["initialize", "notifications/initialized", "tools/list", "ping"])
           )
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
      snapshot(Path.join(ctx.root, "ordinary-catalog-metadata-journal.json")).bytes
      |> JSON.decode!()

    assert length(data["events"]) <= 256
    data
  end

  defp rows(ctx, type), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == type))

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
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_catalog_metadata", "version" => "0.1.0"}
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

  defp call(ctx, pid, method, params, id \\ request_id()) do
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
      ~w(initialize initialized server/diagnostics thread/loaded/list app/list app/list app/list app/list app/list app/list app/list thread/loaded/list)

    cold =
      ~w(initialize initialized server/diagnostics thread/loaded/list app/list thread/loaded/list)

    assert Enum.map(ledger.out, & &1.wire["method"]) === warm ++ cold

    list_ids =
      ledger.out
      |> Enum.filter(&(&1.wire["method"] === "app/list"))
      |> Enum.map(& &1.wire["id"])

    assert list_ids === [
             -1,
             1,
             "owned-list-page-zero",
             "owned-list-page-middle",
             "owned-list-page-final",
             "owned-list-page-terminal",
             "owned-list-force-refetch",
             "owned-list-cold-漢字🙂"
           ]

    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(ledger.in, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 16 and length(Enum.uniq(ids)) === 16
    assert length(replies) === 16
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
    assert 5 === Enum.count(ledger.in, &(&1.wire["method"] == "app/list/updated"))
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

  defp request_id, do: "owned-catalog-metadata-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
