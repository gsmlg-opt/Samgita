defmodule SamgitaCodexDriver.NativeTurnPluginListTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Error, Schema, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, configure_model: 2, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @name "owned-turn-policy"
  @plugin "#{@name}@owned-local-market"
  @hint "Capabilities from the `#{@name}` plugin:"
  @skill_line "- Skills from this plugin are prefixed with `#{@name}:`."
  @skill "---\nname: inspect\ndescription: Owned inert inspection\n---\nOWNED_TURN_POLICY_SKILL\n"
  @cases %{
    enabled_omitted: {[], %{}, 1},
    disabled_omitted: {[@plugin], %{}, 0},
    null_preserves: {[@plugin], %{"disabledPluginIds" => nil}, 0},
    empty_clears: {[@plugin], %{"disabledPluginIds" => []}, 1},
    present_disables: {[], %{"disabledPluginIds" => [@plugin]}, 0}
  }
  @settings_snapshots %{
    enabled_omitted: [[@plugin], []],
    disabled_omitted: [[@plugin]],
    null_preserves: [[@plugin]],
    empty_clears: [[@plugin], []],
    present_disables: [[@plugin], [], [@plugin]]
  }
  @ordinary_summary ~w(id name source installed enabled interface keywords version localVersion)
  @ordinary_detail ~w(marketplaceName marketplacePath description skills onboardingSkill hooks apps appTemplates mcpServers scheduledTasks summary)

  # Bounded test-only capture of the actual successfully sent synthetic request.
  # Native replies pass through unchanged. Initialization/credentials are excluded.
  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)
      inbound = Keyword.fetch!(opts, :inbound)
      plugin_read = Keyword.fetch!(opts, :plugin_read)

      with {:ok, state} <- Stdio.open(Keyword.drop(opts, [:capture, :inbound, :plugin_read])),
           do:
             {:ok,
              Map.merge(state, %{capture: capture, inbound: inbound, plugin_read: plugin_read})}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      case wire["method"] do
        "turn/start" when is_map_key(wire, "id") ->
          capture_send(state, encoded, wire)

        "plugin/read" ->
          send_plugin_read(state, encoded, wire)

        _ ->
          Stdio.send(state, encoded)
      end
    end

    defp send_plugin_read(state, encoded, wire) do
      with {:ok, next} <- Stdio.send(state, encoded) do
        case record_plugin_read(next, :out, encoded, wire) do
          :ok -> {:ok, next}
          {:error, failure} -> {:error, failure, next}
        end
      end
    end

    defp capture_send(state, encoded, wire) do
      if Agent.get(state.capture, &length/1) < 4 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [%{encoded: encoded, wire: wire}]))
          {:ok, next}
        end
      else
        {:error, Error.new(:test_capture_overflow), state}
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

    defp record_event({:message, encoded} = event, :ok, state) do
      wire = JSON.decode!(encoded)
      id = Agent.get(state.plugin_read, & &1.id)

      if id != nil and wire["id"] === id do
        case record_plugin_read(state, :in, encoded, wire) do
          :ok -> record_inbound(event, :ok, state.inbound)
          failure -> {:halt, failure}
        end
      else
        record_inbound(event, :ok, state.inbound)
      end
    end

    defp record_event(event, :ok, state), do: record_inbound(event, :ok, state.inbound)

    # One complete synthetic plugin/read exchange, independent of the retained
    # turn-request and settings-notification captures and their original bounds.
    defp record_plugin_read(state, direction, encoded, wire) do
      Agent.get_and_update(state.plugin_read, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 4096, else: 65_536
        id = if direction == :out, do: wire["id"], else: ledger.id

        if length(ledger.records) < 2 and size <= limit and ledger.bytes + size <= 69_632 do
          entry = %{direction: direction, encoded: encoded, wire: wire}

          {:ok,
           %{ledger | id: id, records: ledger.records ++ [entry], bytes: ledger.bytes + size}}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    defp record_inbound({:message, encoded}, :ok, inbound) do
      if JSON.decode!(encoded)["method"] == "thread/settings/updated" do
        case Agent.get_and_update(inbound, &append_inbound(&1, encoded)) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      else
        {:cont, :ok}
      end
    end

    defp record_inbound(_event, :ok, _inbound), do: {:cont, :ok}

    defp append_inbound(ledger, encoded) do
      size = byte_size(encoded)

      if length(ledger.records) < 8 and size <= 65_536 and ledger.bytes + size <= 262_144 do
        {:ok, %{ledger | records: ledger.records ++ [encoded], bytes: ledger.bytes + size}}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  # Reuse the retained Responses fixture without changing it. Only its HTTP peer
  # gains a bounded audit; it never generates or edits app-server protocol frames.
  @audit_provider ~S"""
  import json, sys, threading
  from pathlib import Path
  sys.path.insert(0, sys.argv.pop(1))
  import model_fixture as upstream

  class AuditedFixture(upstream.ModelFixture):
      def __init__(self, *args, **kwargs):
          super().__init__(*args, **kwargs)
          fixture = self
          self.audit_lock = threading.Lock()
          self.audit = {"unexpected_http": [], "errors": []}
          self.audit_file = self.requests_file.with_name("provider-audit.json")
          self.persist_audit()
          base = self.server.RequestHandlerClass
          class Handler(base):
              def do_GET(self):
                  fixture.unexpected("GET", self.path)
                  super().do_GET()
              def do_POST(self):
                  size = int(self.headers.get("Content-Length", "0"))
                  if self.path != "/v1/responses" or not 0 < size <= 4_194_304:
                      fixture.unexpected("POST", self.path)
                  super().do_POST()
              def do_DELETE(self):
                  fixture.unexpected(self.command, self.path)
                  self.send_response(405)
                  self.end_headers()
              do_PUT = do_DELETE
              do_PATCH = do_DELETE
          self.server.RequestHandlerClass = Handler
      def persist_audit(self):
          pending = self.audit_file.with_suffix(".pending")
          pending.write_text(json.dumps(self.audit))
          pending.replace(self.audit_file)
      def unexpected(self, method, path):
          with self.audit_lock:
              assert len(self.audit["unexpected_http"]) < 16
              self.audit["unexpected_http"].append({"method": method, "path": path})
              self.persist_audit()
      def write_response(self, handler, index, request):
          try:
              assert request["model"] == "mock-model" and index in (1, 2)
              super().write_response(handler, index, request)
          except Exception as error:
              with self.audit_lock:
                  self.audit["errors"].append(type(error).__name__)
                  self.persist_audit()
              handler.send_response(500)
              handler.end_headers()

  upstream.ModelFixture = AuditedFixture
  upstream.main()
  """

  setup tags do
    binary = System.get_env("CODEX_BINARY")
    assert is_binary(binary) and File.regular?(binary)
    assert hash(File.read!(binary)) == @binary_sha
    root = Path.join(System.tmp_dir!(), "owned-turn-plugin-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    script = Path.join(root, "audited_provider.py")
    source = Path.expand("../../../scripts/codex", __DIR__)
    File.write!(script, String.replace(@audit_provider, "sys.argv.pop(1)", "#{inspect(source)}"))
    fixture = start_fixture(root, script)
    File.write!(fixture.requests, "[]")

    on_exit(fn ->
      monitor = Process.monitor(fixture.transport.owner.pid)
      assert :ok = ModelFixture.close(fixture)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
      assert :atomics.get(fixture.transport.owner.completion, 1) == 1
      assert Port.info(fixture.port) == nil
    end)

    ctx = %{root: root, binary: binary, fixture: fixture, scenario: tags.scenario}
    configure_model(ctx, %{})
    ctx = prepare_plugin(ctx)
    capture = start_supervised!({Agent, fn -> [] end})

    inbound =
      start_supervised!(
        Supervisor.child_spec({Agent, fn -> %{records: [], bytes: 0} end}, id: :settings_inbound)
      )

    plugin_read =
      start_supervised!(
        Supervisor.child_spec(
          {Agent, fn -> %{id: nil, records: [], bytes: 0} end},
          id: :plugin_read_capture
        )
      )

    Map.merge(ctx, %{capture: capture, inbound: inbound, plugin_read: plugin_read})
  end

  @tag scenario: :enabled_omitted
  test("omitted turn plugin list retains the enabled baseline", ctx, do: qualify(ctx))

  @tag scenario: :disabled_omitted
  test("omitted turn plugin list retains the disabled baseline", ctx, do: qualify(ctx))

  @tag scenario: :null_preserves
  test("null turn plugin list preserves the disabled baseline", ctx, do: qualify(ctx))

  @tag scenario: :empty_clears
  test("empty turn plugin list clears the disabled baseline for this and later turns", ctx,
    do: qualify(ctx)
  )

  @tag scenario: :present_disables
  test("present turn plugin list disables injection for this and later turns", ctx,
    do: qualify(ctx)
  )

  defp qualify(ctx) do
    {baseline, extra, expected_count} = Map.fetch!(@cases, ctx.scenario)
    pid = start_native(ctx)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {installed_skill, read_originals} = install_plugin(ctx, pid)
    files = snapshot([ctx.marketplace, ctx.manifest, ctx.skill, installed_skill])
    config_bytes = File.read!(Path.join(ctx.fixture.codex_home, "config.toml"))
    generation = Session.status(pid).generation
    lower = System.system_time(:millisecond)
    thread = new_thread(ctx, pid)
    assert ModelFixture.requests(ctx.fixture) == []
    baseline_events = apply_baseline(pid, thread, baseline)
    assert ModelFixture.requests(ctx.fixture) == []

    first = input(ctx, "FIRST")
    first_events = complete(ctx, pid, thread, first, extra, 0)
    assert_provider(ctx, [first], [expected_count])
    assert_settings(first_events, thread, extra, expected_count)
    followup = input(ctx, "FOLLOWUP")
    followup_events = complete(ctx, pid, thread, followup, %{}, 1)
    assert_provider(ctx, [first, followup], [expected_count, expected_count * 2])

    expected_list = if expected_count == 1, do: [], else: [@plugin]

    assert call(pid, "thread/resume", %{"threadId" => thread})["disabledPluginIds"] ===
             expected_list

    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert Agent.get(ctx.capture, &length/1) == 2
    assert Agent.get(ctx.plugin_read, & &1) === read_originals
    assert snapshot(Map.keys(files)) === files
    assert File.read!(Path.join(ctx.fixture.codex_home, "config.toml")) === config_bytes
    trailing = assert_idle(pid)
    assert :ok = Session.close(pid)
    upper = System.system_time(:millisecond)
    refute File.exists?("/proc/#{native}")
    assert snapshot(Map.keys(files)) === files
    assert_provider(ctx, [first, followup], [expected_count, expected_count * 2])
    assert Agent.get(ctx.plugin_read, & &1) === read_originals

    assert_settings_envelopes(
      ctx,
      baseline_events ++ first_events ++ followup_events ++ trailing,
      %{thread: thread, generation: generation, lower: lower, upper: upper}
    )
  end

  defp start_fixture(root, script) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", script)

    try do
      ModelFixture.start(root, "assistant")
    after
      if previous,
        do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
        else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
    end
  end

  defp prepare_plugin(ctx) do
    plugin = Path.join(ctx.fixture.workspace, @name)
    manifest = Path.join(plugin, ".codex-plugin/plugin.json")
    skill = Path.join(plugin, "skills/inspect/SKILL.md")
    marketplace = Path.join(ctx.fixture.workspace, ".agents/plugins/marketplace.json")
    for path <- [manifest, skill, marketplace], do: File.mkdir_p!(Path.dirname(path))
    File.mkdir_p!(Path.join(ctx.fixture.workspace, ".git"))
    File.write!(manifest, JSON.encode!(%{"name" => @name, "description" => "Owned inert skill"}))
    File.write!(skill, @skill)

    File.write!(
      marketplace,
      JSON.encode!(%{
        "name" => "owned-local-market",
        "plugins" => [
          %{"name" => @name, "source" => %{"source" => "local", "path" => "./#{@name}"}}
        ]
      })
    )

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\ncheck_for_update_on_startup = false\n" <>
        File.read!(config) <> "\n[features]\nplugins = true\nremote_plugin = false\n"
    )

    Map.merge(ctx, %{marketplace: marketplace, manifest: manifest, skill: skill})
  end

  defp start_native(ctx) do
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    NativeLaunchFixture.local_plugins_after_initialize(config, fn ->
      {:ok, pid} =
        Session.start_link(
          transport:
            {CaptureStdio,
             [
               capture: ctx.capture,
               inbound: ctx.inbound,
               plugin_read: ctx.plugin_read,
               executable: ctx.binary,
               args: [
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ],
               cwd: ctx.fixture.workspace,
               inherit_env: [],
               env: %{
                 "HOME" => ctx.fixture.home,
                 "CODEX_HOME" => ctx.fixture.codex_home,
                 "TMPDIR" => ctx.root,
                 "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                 "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                 "NO_COLOR" => "1",
                 "RUST_LOG" => "off"
               }
             ]}
        )

      connection = :sys.get_state(pid).connection

      on_exit(fn ->
        monitor = Process.monitor(connection.owner.pid)
        StdioSessionFixture.close(pid, connection)
        assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
        assert :atomics.get(connection.owner.completion, 1) == 1
        assert Port.info(connection.port) == nil
      end)

      assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
               Session.initialize(
                 pid,
                 %{"name" => "owned_turn_plugin_list", "version" => "0.1.0"},
                 %{"experimentalApi" => true}
               )

      pid
    end)
  end

  defp install_plugin(ctx, pid) do
    assert call(pid, "config/read", %{})["config"]["features"]["plugins"] == true
    params = %{"marketplacePath" => ctx.marketplace, "pluginName" => @name}

    listing =
      call(pid, "plugin/list", %{
        "cwds" => [ctx.fixture.workspace],
        "marketplaceKinds" => ["local"]
      })

    assert listing["marketplaceLoadErrors"] == []
    call(pid, "plugin/install", params)
    {detail, read_originals} = read_plugin(ctx, pid, params)
    assert %{"installed" => true, "enabled" => true, "id" => @plugin} = detail["summary"]
    assert [%{"enabled" => true}] = detail["skills"]

    [skill] =
      call(pid, "skills/list", %{"cwds" => [ctx.fixture.workspace], "forceReload" => true})[
        "data"
      ]
      |> Enum.flat_map(& &1["skills"])
      |> Enum.filter(&(&1["name"] == @name <> ":inspect"))

    assert skill["enabled"] == true and File.regular?(skill["path"])
    assert File.read!(skill["path"]) == @skill
    {skill["path"], read_originals}
  end

  defp read_plugin(ctx, pid, params) do
    id = "owned-plugin-read-#{ctx.scenario}"
    wire = %{"id" => id, "method" => "plugin/read", "params" => params}
    expected = expected_ordinary_plugin(ctx)

    assert {:ok, %{"id" => ^id, "result" => %{"plugin" => detail}} = response} =
             Session.request_native(pid, wire, timeout_ms: 5000)

    original = Agent.get(ctx.plugin_read, & &1)
    assert original.id === id
    assert [sent, received] = original.records
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded === response
    assert {:ok, encoded} = Wire.encode(decoded, max_depth: 32)
    assert JSON.decode!(encoded) === response
    assert :ok = Schema.validate(protocol_schema("ClientRequest.json"), wire)
    assert :ok = Schema.validate(protocol_schema("JSONRPCResponse.json"), response)
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
    assert original.bytes === byte_size(sent.encoded) + byte_size(received.encoded)

    # Full original response bytes are preserved for losslessness/correlation.
    # Only this independently specified ordinary metadata projection is qualified.
    ordinary =
      detail
      |> Map.take(@ordinary_detail)
      |> Map.update!("summary", &Map.take(&1, @ordinary_summary))

    assert ordinary === expected
    {detail, original}
  end

  defp expected_ordinary_plugin(ctx) do
    %{
      "marketplaceName" => "owned-local-market",
      "marketplacePath" => ctx.marketplace,
      "description" => "Owned inert skill",
      "summary" => %{
        "id" => @plugin,
        "name" => @name,
        "source" => %{"type" => "local", "path" => Path.join(ctx.fixture.workspace, @name)},
        "installed" => true,
        "enabled" => true,
        "interface" => nil,
        "keywords" => [],
        "version" => nil,
        "localVersion" => nil
      },
      "skills" => [
        %{
          "name" => @name <> ":inspect",
          "description" => "Owned inert inspection",
          "shortDescription" => nil,
          "interface" => nil,
          "path" => ctx.skill,
          "enabled" => true
        }
      ],
      "onboardingSkill" => nil,
      "hooks" => [],
      "apps" => [],
      "appTemplates" => [],
      "mcpServers" => [],
      "scheduledTasks" => nil
    }
  end

  defp protocol_schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp new_thread(ctx, pid) do
    response =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    assert response["disabledPluginIds"] === []
    assert response["thread"]["turns"] === []
    id = response["thread"]["id"]
    # Before first input the lazy rollout has no durable metadata for paginated
    # reads. Creation and the live catalog provide the fresh-thread baseline.
    assert call(pid, "thread/loaded/list", %{})["data"] === [id]

    id
  end

  defp apply_baseline(pid, thread, baseline) do
    # A fresh thread already has []; equal snapshots emit no settings notice.
    # Establish each transition through an actual change and its exact notice.
    initial = if baseline == [], do: update_settings(pid, thread, [@plugin]), else: []
    initial ++ update_settings(pid, thread, baseline)
  end

  defp update_settings(pid, thread, baseline) do
    assert call(pid, "thread/settings/update", %{
             "threadId" => thread,
             "disabledPluginIds" => baseline
           }) == %{}

    events = await_settings(pid, thread, [], System.monotonic_time(:millisecond) + 5000)
    settings = notification(events, "thread/settings/updated", &(&1["threadId"] == thread))
    assert settings["threadSettings"]["disabledPluginIds"] === baseline
    assert_functional_events(events)
    events
  end

  defp await_settings(pid, thread, events, deadline) do
    assert {:ok, next} = Session.drain(pid)
    events = events ++ next
    assert length(events) <= 128

    if notification(events, "thread/settings/updated", &(&1["threadId"] == thread)) do
      events
    else
      assert System.monotonic_time(:millisecond) < deadline, "Native baseline settings deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected baseline event gap")
      after
        20 -> :ok
      end

      await_settings(pid, thread, events, deadline)
    end
  end

  defp complete(ctx, pid, thread, input, extra, before) do
    params = Map.merge(%{"threadId" => thread, "input" => input}, extra)
    id = "owned-#{ctx.scenario}-#{before}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, "turn/start", params, id: id)

    assert [capture] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert capture.wire === %{"id" => id, "method" => "turn/start", "params" => params}
    assert JSON.decode!(capture.encoded) === capture.wire
    turn = result["turn"]["id"]
    events = await_turn(pid, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert_functional_events(events)

    for method <- ["item/started", "item/completed"] do
      user =
        notification(
          events,
          method,
          &(&1["turnId"] == turn and &1["item"]["type"] == "userMessage")
        )

      assert user["threadId"] == thread
      assert user["item"]["content"] === input
    end

    events
  end

  # Keep completion collection local: the retained finish_turn helper also runs
  # an approval assertion, which is outside this functional qualification scope.
  defp await_turn(pid, turn, events, deadline) do
    assert {:ok, next} = Session.drain(pid)
    events = events ++ next

    cond do
      notification(events, "turn/completed", &(&1["turn"]["id"] == turn)) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Real turn event deadline: #{inspect(Session.status(pid))}")

      true ->
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during real turn")
        after
          20 -> :ok
        end

        await_turn(pid, turn, events, deadline)
    end
  end

  defp assert_settings(events, thread, extra, count) do
    if Map.has_key?(extra, "disabledPluginIds") and extra["disabledPluginIds"] != nil do
      settings = notification(events, "thread/settings/updated", &(&1["threadId"] == thread))

      assert settings["threadSettings"]["disabledPluginIds"] ===
               if(count == 1, do: [], else: [@plugin])
    end
  end

  defp assert_settings_envelopes(ctx, events, scope) do
    selected = Enum.filter(events, &(&1.wire["method"] == "thread/settings/updated"))
    expected = Map.fetch!(@settings_snapshots, ctx.scenario)

    assert Enum.map(selected, &get_in(&1.wire, ["params", "threadSettings", "disabledPluginIds"])) ===
             expected

    originals = Agent.get(ctx.inbound, & &1.records)
    assert length(originals) === length(expected)
    assert Enum.map(originals, &JSON.decode!/1) === Enum.map(selected, & &1.wire)
    sequences = Enum.map(selected, & &1.sequence)
    assert Enum.all?(sequences, &(is_integer(&1) and &1 > 0))
    assert sequences === Enum.sort(Enum.uniq(sequences))

    for event <- selected do
      emitted = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted) and scope.lower <= emitted and emitted <= scope.upper
      assert event.kind === :notification and event.generation === scope.generation
      params = Map.fetch!(event.wire, "params")
      assert Enum.sort(Map.keys(params)) === ~w(threadId threadSettings)
      assert Map.fetch!(params, "threadId") === scope.thread
      assert is_map(Map.fetch!(params, "threadSettings"))

      assert event.wire === %{
               "method" => "thread/settings/updated",
               "params" => params,
               "emittedAtMs" => emitted
             }
    end
  end

  defp input(ctx, suffix),
    do: [
      %{"type" => "text", "text" => "OWNED_#{ctx.scenario}_#{suffix}", "text_elements" => []},
      %{"type" => "mention", "name" => "Unrelated display name", "path" => "plugin://#{@plugin}"}
    ]

  defp assert_provider(ctx, inputs, counts) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == length(inputs)

    for {input, count} <- Enum.zip(inputs, counts) do
      marker = hd(input)["text"]
      assert [request] = Enum.filter(requests, &latest_user_marker?(&1, marker))
      assert request["model"] == "mock-model"
      assert messages(request, "developer", @hint) == count
      assert messages(request, "developer", @skill_line) == count
      refute JSON.encode!(request["input"]) =~ "MCP servers from this plugin"
      refute JSON.encode!(request["input"]) =~ "Apps from this plugin"

      refute Enum.any?(
               request["input"],
               &(&1["type"] in ["function_call", "function_call_output"])
             )
    end

    assert ctx.fixture.requests
           |> Path.dirname()
           |> Path.join("provider-audit.json")
           |> File.read!()
           |> JSON.decode!() == %{"unexpected_http" => [], "errors" => []}
  end

  defp messages(request, role, text),
    do:
      Enum.count(request["input"], fn item ->
        item["role"] == role and
          Enum.any?(
            Map.get(item, "content", []),
            &String.contains?(Map.get(&1, "text", ""), text)
          )
      end)

  defp latest_user_marker?(request, marker) do
    latest = request["input"] |> Enum.filter(&(&1["role"] == "user")) |> List.last()
    assert is_map(latest)
    Enum.any?(Map.get(latest, "content", []), &String.contains?(Map.get(&1, "text", ""), marker))
  end

  defp assert_functional_events(events) do
    refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    types = for event <- events, item = get_in(event.wire, ["params", "item"]), do: item["type"]
    assert Enum.all?(types, &(&1 in ["userMessage", "agentMessage"]))
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert {:ok, events} = Session.drain(pid)
    assert_functional_events(events)
    events
  end

  defp snapshot(paths),
    do:
      Map.new(paths, fn path ->
        assert File.lstat!(path).type == :regular
        {path, File.read!(path)}
      end)

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
