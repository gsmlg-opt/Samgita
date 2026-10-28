defmodule SamgitaCodexDriver.NativeOrdinaryInstalledAppsTest do
  @moduledoc false
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_installed_apps_fixture.py", __DIR__)
  @script_sha "e20306dd396d517a2f4f9bf75356052c442490b15f39c75d98a9e714ab19a706"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema_shas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/AppsInstalledParams.json" =>
      "c2027510d5d041c2205349036f9c2bea10b20df309de5330beab9de8a9e50bdb",
    "v2/AppsInstalledResponse.json" =>
      "d8ef8dd14dcba8aaaaaf2b0b80db90d66edf8f4ff422589b844ae2b0edcb46d4",
    "v2/AppsListResponse.json" =>
      "5811fda68d6274decfc11744ad72bbe93e601d8514549e94f361ba3131d1adeb",
    "v2/AppListUpdatedNotification.json" =>
      "2c67a3bc676309afdd0d6952ad454c2a040a3d4c09d38c8f63ca7fb632034cce"
  }
  @alpha "owned-installed-alpha"
  @beta "owned-installed-beta"
  @gamma "owned-installed-gamma"
  @delta "owned-directory-delta"
  @one [
    %{"id" => @alpha, "runtimeName" => "Owned Alpha λ🙂"},
    %{"id" => @beta, "runtimeName" => nil}
  ]
  @two [
    %{"id" => @alpha, "runtimeName" => "Owned Alpha refreshed β🙂"},
    %{"id" => @gamma, "runtimeName" => nil}
  ]
  @listed [
    %{
      "id" => @delta,
      "name" => "Owned directory Delta δ",
      "description" => "Owned directory-only description λ",
      "logoUrl" => "https://synthetic.invalid/ordinary-delta.svg",
      "logoUrlDark" => nil
    },
    %{
      "id" => @alpha,
      "name" => "Owned canonical Alpha λ🙂",
      "description" => "Owned directory Alpha description β",
      "logoUrl" => "https://synthetic.invalid/ordinary-alpha.svg",
      "logoUrlDark" => "https://synthetic.invalid/ordinary-alpha-dark.svg"
    },
    %{
      "id" => @gamma,
      "name" => "Owned canonical Gamma γ",
      "description" => "Owned directory Gamma description 🙂",
      "logoUrl" => nil,
      "logoUrlDark" => nil
    }
  ]

  # Owner2991 only: physical envelope; existing descriptive/structural scope stays.
  @app_list_wrapper_root_sha "8e719512bc26bb3871fcf7b378b79abf912d82787609c0ad418b71f179d0883f"
  @app_list_wrapper_node_sha "1b06eb2817f9e8cd55c79a0d124bb34dacd1344c10070627360ef34ca96605b7"
  @app_list_wrapper_node_bytes """
  {
    "properties": {
      "method": {
        "enum": [
          "app/list/updated"
        ],
        "title": "App/list/updatedNotificationMethod",
        "type": "string"
      },
      "params": {
        "$ref": "#/definitions/AppListUpdatedNotification"
      }
    },
    "required": [
      "method",
      "params"
    ],
    "title": "App/list/updatedNotification",
    "type": "object"
  }
  """

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

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@base)) === @base_sha
    for {name, sha} <- @schema_shas, do: assert(hash(File.read!(schema_path(name))) === sha)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-installed-apps-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-installed-apps")
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

    paths =
      [
        @script,
        @base,
        fixture.requests,
        Path.join(fixture.codex_home, "config.toml"),
        Path.join(fixture.codex_home, "models.json"),
        Path.join(root, "ordinary-installed-apps-inputs.json"),
        Path.join(__DIR__, "support/model_fixture.ex"),
        Path.join(__DIR__, "support/stdio_session_fixture.ex")
      ] ++
        Enum.map(Map.keys(@schema_shas), &schema_path/1)

    Map.put(ctx, :inputs, Map.new(paths, &{&1, snapshot(&1)}))
  end

  test "ordinary native installed snapshots refresh metadata and list separate populated wire arrays",
       ctx do
    native = start(ctx)
    # Only identity and descriptive runtime-name fields are projected. Other
    # native computed fields stay outside all outcome assertions and owner credit.
    assert installed(ctx, native.pid, %{}, 3318) === []
    assert_discovery(ctx, [])
    assert installed(ctx, native.pid, %{"forceRefresh" => true}, "3318") === @one
    assert_discovery(ctx, [1])
    control(ctx, %{"action" => "generation", "generation" => 2})

    await(
      fn ->
        rows(ctx, "generation_changed") === [
          %{"event" => "generation_changed", "generation" => 2}
        ]
      end,
      now() + 5_000
    )

    assert installed(ctx, native.pid, %{"forceRefresh" => false}, "owned-installed-cached-one") ===
             @one

    assert_discovery(ctx, [1])

    assert installed(ctx, native.pid, %{"forceRefresh" => true}, "owned-installed-refresh-two") ===
             @two

    assert_discovery(ctx, [1, 2])

    assert installed(ctx, native.pid, %{"forceRefresh" => false}, "owned-installed-cached-two") ===
             @two

    assert_discovery(ctx, [1, 2])

    # These distinct native response and notification arrays each retain their
    # own schema/byte evidence. A notification is never fabricated from a reply.
    before = length(notifications(ctx))
    assert list(ctx, native.pid, true, "owned-app-list-populated") === @listed
    assert_list_notifications(ctx, before, 1..2)
    assert_discovery(ctx, [1, 2, 2, 2])
    assert_directory(ctx)
    before = length(notifications(ctx))
    assert list(ctx, native.pid, false, "owned-app-list-cached") === @listed
    assert_list_notifications(ctx, before, 1..1)
    assert_discovery(ctx, [1, 2, 2, 2])
    assert_directory(ctx)
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
    assert_controls(ctx)
    close_provider(ctx)
    assert_discovery(ctx, [1, 2, 2, 2])
    assert_directory(ctx)
    assert_controls(ctx)
  end

  defp installed(ctx, pid, params, id) do
    document = schema("v2/AppsInstalledParams.json")
    refute Map.has_key?(params, "threadId")
    assert :ok = Schema.validate(document, params, max_depth: 16)

    if Map.has_key?(params, "forceRefresh") do
      assert :ok = Schema.validate(document["properties"]["forceRefresh"], params["forceRefresh"])
    end

    result = call(ctx, pid, %{"id" => id, "method" => "app/installed", "params" => params})
    result_schema = schema("v2/AppsInstalledResponse.json")
    assert :ok = Schema.validate(result_schema, result, max_depth: 32)

    assert :ok =
             Schema.validate(
               with_definitions(result_schema, result_schema["properties"]["apps"]),
               result["apps"]
             )

    properties = result_schema["definitions"]["InstalledApp"]["properties"]

    for app <- result["apps"] do
      assert :ok = Schema.validate(properties["id"], Map.fetch!(app, "id"))
      assert :ok = Schema.validate(properties["runtimeName"], Map.fetch!(app, "runtimeName"))
    end

    Enum.map(result["apps"], &Map.take(&1, ~w(id runtimeName)))
  end

  defp list(ctx, pid, refresh, id) do
    result =
      call(ctx, pid, %{
        "id" => id,
        "method" => "app/list",
        "params" => %{"forceRefetch" => refresh}
      })

    document = schema("v2/AppsListResponse.json")
    assert :ok = Schema.validate(document, result, max_depth: 64)

    assert :ok =
             Schema.validate(
               with_definitions(document, document["properties"]["data"]),
               result["data"],
               max_depth: 64
             )

    assert result["nextCursor"] === nil
    descriptive(result["data"])
  end

  defp assert_list_notifications(ctx, before, count_range) do
    selected = Enum.drop(notifications(ctx), before)
    assert length(selected) in count_range
    projected = Enum.map(selected, &validate_notification/1)
    assert @listed in projected

    for projection <- projected do
      assert projection != [] and length(projection) <= 3
      assert Enum.all?(projection, &(&1["id"] in [@alpha, @gamma, @delta]))
    end
  end

  defp validate_notification(frame) do
    assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
    emitted = Map.fetch!(frame.wire, "emittedAtMs")
    assert is_integer(emitted) and emitted > 0
    assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
    assert decoded === frame.wire
    document = schema("v2/AppListUpdatedNotification.json")
    params = frame.wire["params"]
    assert :ok = Schema.validate(document, params, max_depth: 64)

    assert :ok =
             Schema.validate(
               with_definitions(document, document["properties"]["data"]),
               params["data"],
               max_depth: 64
             )

    assert_app_list_wrapper_binding(decoded)

    descriptive(params["data"])
  end

  defp assert_app_list_wrapper_binding(original) do
    bytes =
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/stable/ServerNotification.json")
      |> File.read!()

    assert hash(bytes) === @app_list_wrapper_root_sha
    document = JSON.decode!(bytes)
    node = document |> Map.fetch!("oneOf") |> Enum.fetch!(50)
    assert hash(@app_list_wrapper_node_bytes) === @app_list_wrapper_node_sha
    assert JSON.decode!(@app_list_wrapper_node_bytes) === node

    # Existing standalone params/data shape checks and descriptive oracles stay
    # unchanged. Do not inspect or assert any eligibility or permission outcome.
    assert :ok =
             Schema.validate(
               Map.put(node, "definitions", Map.fetch!(document, "definitions")),
               original,
               max_depth: 64
             )
  end

  defp descriptive(apps) do
    assert is_list(apps) and length(apps) <= 3

    apps
    |> Enum.map(&Map.take(&1, ~w(id name description logoUrl logoUrlDark)))
    |> Enum.sort_by(& &1["id"])
  end

  defp with_definitions(document, node),
    do: Map.put(node, "definitions", Map.fetch!(document, "definitions"))

  defp notifications(ctx),
    do: Enum.filter(frames(ctx, :in), &(&1.wire["method"] === "app/list/updated"))

  defp assert_discovery(ctx, generations) do
    observed = rows(ctx, "tools_list")
    assert Enum.map(observed, & &1["generation"]) === generations
    assert Enum.map(observed, & &1["sequence"]) === sequence(length(generations))

    await(
      fn -> length(rows(ctx, "tools_list_response_sent")) === length(generations) end,
      now() + 5_000
    )

    sent = rows(ctx, "tools_list_response_sent")

    for {row, response} <- Enum.zip(observed, sent) do
      assert JSON.decode!(row["raw_request"]) === row["request"]
      assert row["request"]["method"] === "tools/list"
      assert response["sequence"] === row["sequence"]
      assert hash(response["raw"]) === response["sha256"]

      assert JSON.decode!(response["raw"]) === %{
               "jsonrpc" => "2.0",
               "id" => row["request"]["id"],
               "result" => row["result"]
             }

      projected = Enum.map(row["result"]["tools"], &Map.take(&1, ~w(name _meta)))
      assert projected === expected_tools(row["generation"])
    end
  end

  defp expected_tools(1),
    do: [
      %{
        "name" => "owned_alpha_lookup",
        "_meta" => %{"connector_id" => @alpha, "connector_name" => "  Owned Alpha λ🙂  "}
      },
      %{
        "name" => "owned_alpha_notes",
        "_meta" => %{"connector_id" => @alpha, "connector_name" => "  Owned Alpha λ🙂  "}
      },
      %{"name" => "owned_beta_lookup", "_meta" => %{"connector_id" => @beta}}
    ]

  defp expected_tools(2),
    do: [
      %{
        "name" => "owned_alpha_lookup",
        "_meta" => %{"connector_id" => @alpha, "connector_name" => "Owned Alpha refreshed β🙂"}
      },
      %{"name" => "owned_gamma_lookup", "_meta" => %{"connector_id" => @gamma}}
    ]

  defp assert_directory(ctx) do
    assert [
             %{
               "sequence" => 1,
               "path" => "/backend-api/connectors/directory/list",
               "query" => %{"external_logos" => ["true"]},
               "rows" => apps
             }
           ] = rows(ctx, "directory")

    projected =
      Enum.map(apps, fn app ->
        %{
          "id" => app["id"],
          "name" => app["name"],
          "description" => app["description"],
          "logoUrl" => app["logo_url"],
          "logoUrlDark" => app["logo_url_dark"]
        }
      end)
      |> Enum.sort_by(& &1["id"])

    assert projected === @listed
    await(fn -> length(rows(ctx, "directory_response_sent")) === 1 end, now() + 5_000)

    assert [%{"sequence" => 1, "raw" => raw, "sha256" => sha}] =
             rows(ctx, "directory_response_sent")

    assert hash(raw) === sha
    assert JSON.decode!(raw) === %{"apps" => apps, "next_token" => nil}
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
    assert rows(ctx, "unexpected_http") === [] and rows(ctx, "unexpected_mcp") === []
    assert rows(ctx, "fixture_error") === []
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
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_installed_apps", "version" => "1"}
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
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)

    if sent.wire["method"] === "app/installed" do
      document = schema("ClientRequest.json")
      variants = Map.fetch!(document, "oneOf")

      selected =
        Enum.filter(
          variants,
          &(get_in(&1, ["properties", "method", "enum"]) === ["app/installed"])
        )

      assert [variant] = selected
      assert variant === Enum.at(variants, 85)
      node = variant |> Map.fetch!("properties") |> Map.fetch!("id")
      assert node === %{"$ref" => "#/definitions/RequestId"}

      assert :ok =
               Schema.validate(with_definitions(document, node), Map.fetch!(sent.wire, "id"),
                 max_depth: 8
               )
    end
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics app/installed app/installed app/installed app/installed app/installed app/list app/list thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        frames(ctx, :in),
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    assert length(requests) === 10 and length(responses) === 10
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 10
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    methods =
      frames(ctx, :in)
      |> Enum.filter(&Map.has_key?(&1.wire, "method"))
      |> Enum.map(& &1.wire["method"])

    # The native initialized path emits one separate startup notification.
    # Its status/policy fields are outside this metadata profile's assertions.
    assert Enum.count(methods, &(&1 === "remoteControl/status/changed")) === 1
    assert Enum.count(methods, &(&1 === "app/list/updated")) in 2..3
    assert Enum.all?(methods, &(&1 in ~w(remoteControl/status/changed app/list/updated)))
    assert length(rows(ctx, "mcp_initialize")) === 3
    assert length(rows(ctx, "mcp_initialized")) === 3
  end

  defp control(ctx, command) do
    path = Path.join(ctx.root, "ordinary-installed-apps-control.json")
    refute File.exists?(path)
    pending = path <> ".pending"
    File.write!(pending, JSON.encode!(command), [:exclusive])
    File.rename!(pending, path)
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
        control(ctx, %{"action" => "close"})
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

  defp rows(ctx, event) do
    path = Path.join(ctx.root, "ordinary-installed-apps-journal.json")

    if File.exists?(path) do
      rows = snapshot(path).bytes |> JSON.decode!() |> Map.fetch!("events")
      assert length(rows) <= 64
      Enum.filter(rows, &(&1["event"] === event))
    else
      []
    end
  end

  defp await(predicate, until) do
    unless predicate.() do
      assert now() < until, "ordinary installed metadata observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, until)
    end
  end

  defp sequence(0), do: []
  defp sequence(count), do: Enum.to_list(1..count)
  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      Path.expand(
        "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/" <> name,
        __DIR__
      )

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id, do: "ordinary-installed-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
