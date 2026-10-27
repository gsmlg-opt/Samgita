defmodule SamgitaCodexDriver.NativeConfigWarningEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @model "owned-config-warning-model"
  @summary "Ignoring invalid `otel.span_attributes` config: configured span attribute key must not be empty"
  @params %{"summary" => @summary, "details" => nil}

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
      with {:ok, next} <- Stdio.send(state, encoded) do
        case record(next.capture, :out, encoded) do
          :ok -> {:ok, next}
          {:error, failure} -> {:error, failure, next}
        end
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          result = Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture))

          case result do
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

    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 65_536

        if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
          entry = %{direction: direction, encoded: encoded, index: ledger.count + 1}

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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert is_binary(System.find_executable("python3")), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-config-warning-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    profile = %{root: root, workspace: Path.join(root, "workspace"), binary: Path.expand(binary)}
    configure(profile)
    %{profile: profile, frozen: frozen_files(profile)}
  end

  test "native startup warning preserves the valid local catalog across reads and a fresh process",
       ctx do
    deadline = now() + 20_000

    observations =
      for index <- 1..2 do
        capture =
          start_supervised!(
            Supervisor.child_spec(
              {Agent, fn -> %{count: 0, bytes: 0, records: []} end},
              id: {:warning_capture, index}
            )
          )

        profile = Map.put(ctx.profile, :capture, capture)
        native = start_native(profile)
        profile = Map.put(profile, :generation, native.generation)
        events = collect(profile, native.pid, [], min(deadline, now() + 5_000))
        upper = System.system_time(:millisecond)
        assert [event] = events
        expected = assert_warning(profile, event, native.lower, upper)
        original = assert_original_warning(profile, expected)
        assert_initialization_cause(profile, native.initialize_id, original)

        expected_models = %{"data" => [expected_model()], "nextCursor" => nil}

        for _read <- 1..2,
            do: assert(call(profile, native.pid, "model/list", %{}) === expected_models)

        assert call(profile, native.pid, "thread/loaded/list", %{}) === %{
                 "data" => [],
                 "nextCursor" => nil
               }

        assert frozen_files(profile) === ctx.frozen
        assert File.ls!(profile.workspace) === []
        assert_ready(profile, native.pid)
        assert {:ok, final} = Session.drain(native.pid, 128)
        events = events ++ final
        assert_events(profile, events)
        assert events === [event]
        assert assert_original_warning(profile, expected) === original
        assert_finite_frames(profile)
        ledger = Agent.get(profile.capture, & &1)
        os_pid = :atomics.get(native.identity, 1)
        close_native(native)
        assert Agent.get(profile.capture, & &1) === ledger
        assert assert_original_warning(profile, expected) === original
        assert frozen_files(profile) === ctx.frozen
        assert File.ls!(profile.workspace) === []
        assert now() <= deadline
        %{os_pid: os_pid, params: event.wire["params"], models: expected_models}
      end

    assert [first, second] = observations
    refute first.os_pid === second.os_pid
    assert first.params === @params and second.params === @params
    assert first.models === second.models
  end

  defp assert_warning(profile, event, lower, upper) do
    emitted = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted) and lower <= emitted and emitted <= upper
    assert event.kind === :notification and event.generation === profile.generation
    assert is_integer(event.sequence) and event.sequence > 0
    expected = %{"method" => "configWarning", "params" => @params, "emittedAtMs" => emitted}
    assert event.wire === expected
    assert :ok = Schema.validate(schema("ServerNotification.json"), expected, max_depth: 32)
    expected
  end

  defp assert_original_warning(profile, expected) do
    [original] =
      Enum.filter(
        capture(profile),
        &(&1.direction == :in and &1.wire["method"] == "configWarning")
      )

    assert original.wire === expected
    assert JSON.decode!(original.encoded) === expected
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 32)
    assert decoded === expected
    original
  end

  defp assert_initialization_cause(profile, initialize_id, warning) do
    frames = capture(profile)
    [request, response] = Enum.filter(frames, &(&1.wire["id"] == initialize_id))
    assert request.direction === :out and response.direction === :in
    assert request.wire["method"] === "initialize"
    assert request.index < response.index and response.index < warning.index

    [initialized] =
      Enum.filter(frames, &(&1.direction == :out and &1.wire["method"] == "initialized"))

    assert initialized.wire === %{"method" => "initialized"}
    assert response.index < initialized.index
    # Native startup warnings follow initialize; the driver's initialized send
    # may race with incoming warning delivery, so their mutual order is not fixed.
  end

  defp assert_finite_frames(profile) do
    frames = capture(profile)
    assert length(frames) === 12
    indices = Enum.map(frames, & &1.index)
    assert indices === Enum.to_list(1..12)
    outgoing = Enum.filter(frames, &(&1.direction == :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics model/list model/list thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 5 and length(Enum.uniq(ids)) === 5

    assert Enum.filter(frames, &(&1.direction == :in and Map.has_key?(&1.wire, "method")))
           |> Enum.map(& &1.wire["method"]) === ["configWarning"]
  end

  defp collect(profile, pid, events, deadline) do
    assert now() < deadline, "Owned startup warning deadline"
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)

    if length(events) == 1 do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Owned startup warning event gap")
      after
        10 -> :ok
      end

      collect(profile, pid, events, deadline)
    end
  end

  defp assert_events(profile, events) do
    assert length(events) <= 1
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert Enum.all?(
             events,
             &(&1.kind === :notification and &1.generation === profile.generation and
                 &1.wire["method"] == "configWarning")
           )

    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
  end

  defp configure(profile) do
    catalog = Path.join(profile.root, "codex/models.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => @model,
            "display_name" => @model,
            "description" => nil,
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{"instructions_template" => "Owned local catalog metadata only."},
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    File.write!(Path.join(profile.root, "codex/config.toml"), """
    model = "#{@model}"
    model_provider = "fixture"
    model_catalog_json = #{JSON.encode!(catalog)}
    check_for_update_on_startup = false
    allow_login_shell = false
    web_search = "disabled"
    chatgpt_base_url = "http://127.0.0.1:9"
    openai_base_url = "http://127.0.0.1:9/v1"
    [analytics]
    enabled = false
    [feedback]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [otel.span_attributes]
    "" = "Owned inert metadata λ"
    [memories]
    generate_memories = false
    use_memories = false
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    remote_models = false
    remote_control = false
    shell_snapshot = false
    memories = false
    hooks = false
    [model_providers.fixture]
    name = "Owned local static catalog"
    base_url = "http://127.0.0.1:9/v1"
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)
  end

  defp expected_model,
    do: %{
      "id" => @model,
      "model" => @model,
      "displayName" => @model,
      "description" => "",
      "hidden" => false,
      "isDefault" => true,
      "defaultReasoningEffort" => "none",
      "supportedReasoningEfforts" => [],
      "inputModalities" => ["text", "image"],
      "supportsPersonality" => false,
      "multiAgentVersion" => nil,
      "modelSpecialty" => nil,
      "additionalSpeedTiers" => [],
      "serviceTiers" => [],
      "defaultServiceTier" => nil,
      "availableAccessPrograms" => nil,
      "availabilityNux" => nil,
      "upgrade" => nil,
      "upgradeInfo" => nil
    }

  defp start_native(profile) do
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
                    cwd: profile.workspace,
                    inherit_env: [],
                    env: environment(profile),
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity}
    on_exit(fn -> close_native(native) end)
    lower = System.system_time(:millisecond)
    info = %{"name" => "owned_config_warning", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

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

    os_pid = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(os_pid) and os_pid > 0
    :atomics.put(identity, 1, os_pid)
    assert hash(File.read!("/proc/#{os_pid}/exe")) === @binary_sha

    Map.merge(native, %{
      lower: lower,
      initialize_id: id,
      generation: Session.status(pid).generation
    })
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
    assert sent.direction === :out and received.direction === :in and sent.index < received.index
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
    assert :ok = Schema.validate(schema("ClientRequest.json"), wire, max_depth: 32)
  end

  defp assert_ready(profile, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === profile.generation
    assert Session.uncertain_operations(pid) === []
  end

  defp close_native(native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Stdio.close(native.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    os_pid = :atomics.get(native.identity, 1)
    if os_pid > 0, do: refute(File.exists?("/proc/#{os_pid}"))
  end

  defp environment(profile),
    do: %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }

  defp frozen_files(profile),
    do:
      Map.new(
        ~w(codex/config.toml codex/models.json bin/sh),
        &{&1, File.read!(Path.join(profile.root, &1))}
      )

  defp capture(profile),
    do:
      Agent.get(profile.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp schema(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)
      |> File.read!()
      |> JSON.decode!()

  defp request_id, do: "owned-config-warning-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
