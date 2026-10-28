defmodule SamgitaCodexDriver.NativeOrdinaryPluginSkillReadTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_plugin_skill_read_fixture.py", __DIR__)
  @script_sha "53d0a0812d44198b11edefe8faf4524e24a50136c3942e1d0ca05e7e51acb2d2"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schemas %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "v2/PluginSkillReadParams.json" =>
      "8850a9a45b9cf6e8b016f014c7c65f7062937be896d4fa0eafdaccc816909a56",
    "v2/PluginSkillReadResponse.json" =>
      "dedaf95c4a8f70c022f5cac6fe3882603ed2b27d5efef710b52ae370869956cc"
  }
  @remote "plugins~Plugin_owned_skill"
  @params %{
    "remoteMarketplaceName" => "openai-curated-remote",
    "remotePluginId" => @remote,
    "skillName" => "notes"
  }
  @contents "---\nname: notes\ndescription: Owned ordinary remote notes\n---\n# Ordinary skill λ🙂\nRecord project facts β, preserve 漢字.\n"
  @ids [-1, "-1"]

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

    defp record_event({:message, encoded}, :ok, state) do
      case record(state, :in, encoded) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end

    defp record_event(_, :ok, _), do: {:cont, :ok}

    defp record(state, direction, encoded) do
      wire = JSON.decode!(encoded)

      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: encoded, wire: wire}
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
    for {name, expected} <- @schemas, do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-skill-read-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-plugin-skill-read")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    config = Path.join(fixture.codex_home, "config.toml")
    disabled = File.read!(config)
    assert length(:binary.matches(disabled, "\nplugins = false\n")) === 1
    enabled = String.replace(disabled, "\nplugins = false\n", "\nplugins = true\n", global: false)
    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    paths = [
      @script,
      @base,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json"),
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
      | Enum.map(Map.keys(@schemas), &schema_path/1)
    ]

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      config: config,
      disabled: disabled,
      enabled: enabled,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native plugin skill reads preserve Unicode contents and explicit null through two direct fetches",
       ctx do
    native = start(ctx)
    assert_empty_loaded(ctx, native.pid)
    assert rows(ctx, "skill") === []
    enable_plugins(ctx)
    assert read_skill(ctx, native.pid, Enum.at(@ids, 0)) === %{"contents" => @contents}
    assert_fetches(ctx, [@contents])
    assert_controls(ctx)
    assert read_skill(ctx, native.pid, Enum.at(@ids, 1)) === %{"contents" => nil}
    assert_fetches(ctx, [@contents, nil])
    assert_empty_loaded(ctx, native.pid)
    assert_controls(ctx)
    assert_idle(native.pid)
    close(native)
    assert_inventory(ctx)
    assert_controls(ctx)
    close_provider(ctx)
    assert_controls(ctx)
    assert_fetches(ctx, [@contents, nil])
  end

  defp read_skill(ctx, pid, id) do
    assert :ok = Schema.validate(schema("v2/PluginSkillReadParams.json"), @params, max_depth: 8)
    wire = %{"id" => id, "method" => "plugin/skill/read", "params" => @params}
    assert_request(wire)
    result = call(ctx, pid, wire)
    assert :ok = Schema.validate(schema("v2/PluginSkillReadResponse.json"), result, max_depth: 8)
    result
  end

  defp assert_request(wire) do
    document = schema("ClientRequest.json")
    owner = Enum.at(document["oneOf"], 77)

    assert owner === %{
             "properties" => %{
               "id" => %{"$ref" => "#/definitions/RequestId"},
               "method" => %{
                 "enum" => ["plugin/skill/read"],
                 "title" => "Plugin/skill/readRequestMethod",
                 "type" => "string"
               },
               "params" => %{"$ref" => "#/definitions/PluginSkillReadParams"}
             },
             "required" => ["id", "method", "params"],
             "title" => "Plugin/skill/readRequest",
             "type" => "object"
           }

    selected =
      Map.put(
        owner,
        "definitions",
        Map.take(document["definitions"], ["RequestId", "PluginSkillReadParams"])
      )

    assert :ok = Schema.validate(selected, wire, max_depth: 16)
  end

  defp assert_fetches(ctx, values) do
    fetches = rows(ctx, "skill")
    assert length(fetches) === length(values)

    Enum.zip(fetches, Enum.with_index(values, 1))
    |> Enum.each(fn {fetch, {contents, sequence}} ->
      body = %{"plugin_id" => @remote, "name" => "notes", "skill_md_contents" => contents}
      assert fetch["event"] === "skill"
      assert fetch["sequence"] === sequence
      assert fetch["path"] === "/backend-api/ps/plugins/#{@remote}/skills/notes"
      assert fetch["query"] === ""
      assert fetch["response"] === body
      raw = Map.fetch!(fetch, "raw")
      assert is_binary(raw) and 0 < byte_size(raw) and byte_size(raw) <= 65_536
      assert Map.fetch!(fetch, "size") === byte_size(raw)
      assert JSON.decode!(raw) === body
    end)
  end

  defp enable_plugins(ctx) do
    assert File.read!(ctx.config) === ctx.disabled
    path = ctx.config <> ".ordinary-pending"
    File.write!(path, ctx.enabled, [:exclusive])
    File.rename!(path, ctx.config)
    assert File.read!(ctx.config) === ctx.enabled
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === ctx.enabled
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp rows(ctx, kind) do
    journal =
      snapshot(Path.join(ctx.root, "ordinary-plugin-skill-read-journal.json")).bytes
      |> JSON.decode!()

    assert length(journal["events"]) <= 128
    Enum.filter(journal["events"], &(&1["event"] === kind))
  end

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp start(ctx) do
    assert File.read!(ctx.config) === ctx.disabled
    # Keep TOML feature setup reloadable instead of a persistent CLI false override.
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
    info = %{"name" => "owned_ordinary_plugin_skill_read", "version" => "0.1.0"}
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
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    expected =
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/skill/read plugin/skill/read thread/loaded/list)

    assert Enum.map(outgoing, & &1.wire["method"]) === expected
    skills = Enum.filter(outgoing, &(&1.wire["method"] === "plugin/skill/read"))
    assert Enum.map(skills, & &1.wire["id"]) === @ids
    assert Enum.map(skills, & &1.wire["params"]) === [@params, @params]
    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 6 and length(Enum.uniq(ids)) === 6
    assert length(replies) === 6
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    refute Enum.any?(events, &(&1.kind === :server_request))

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ~w(turn/started turn/completed item/started item/completed))
           )

    assert {:ok, []} = Session.drain(pid, 128)
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

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: name |> schema_path() |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-plugin-skill-read-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
