defmodule SamgitaCodexDriver.NativeOrdinaryPluginShareSaveTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.Wire

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_plugin_share_save_fixture.py", __DIR__)
  @script_sha "939317eee012ed7d1ef3c84e42c088e2322236cf52454d35b280a4cbfe289376"
  @base Path.expand("../../../scripts/codex/ordinary_app_context_fixture.py", __DIR__)
  @base_sha "2f25436a2b5694390d64305b9566ce3859eea5cb81f8b212c125eb05db4126e1"
  @schema_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  @remote "plugins~Plugin_owned_ordinary_save"
  @manifest ~s({"name":"owned-ordinary-save"})
  @marker "Owned ordinary share source marker λ🙂\n"
  @skill "---\nname: notes\ndescription: Owned ordinary shared notes\n---\nRecord ordinary project notes β🙂.\n"
  @edited_skill "---\nname: notes\ndescription: Owned ordinary shared notes\n---\nRecord explicitly updated project notes γ🙂.\n"
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
    assert hash(File.read!(schema_path())) === @schema_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-plugin-share-save-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "ordinary-plugin-share-save")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    source = Path.join(fixture.home, "plugins/ordinary-source")
    File.mkdir_p!(Path.join(source, ".codex-plugin"))
    File.mkdir_p!(Path.join(source, "skills/notes"))
    File.write!(Path.join(source, ".codex-plugin/plugin.json"), @manifest, [:exclusive])
    File.write!(Path.join(source, "marker.txt"), @marker, [:exclusive])
    File.write!(Path.join(source, "skills/notes/SKILL.md"), @skill, [:exclusive])
    config = Path.join(fixture.codex_home, "config.toml")
    disabled = File.read!(config)

    enabled =
      Enum.reduce(["plugins", "plugin_sharing"], disabled, fn feature, text ->
        fragment = "\n#{feature} = false\n"
        assert length(:binary.matches(text, fragment)) === 1
        String.replace(text, fragment, "\n#{feature} = true\n", global: false)
      end)

    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})

    paths = [
      @script,
      @base,
      fixture.requests,
      Path.join(fixture.codex_home, "models.json"),
      schema_path()
    ]

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      source: source,
      config: config,
      disabled: disabled,
      enabled: enabled,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native share save uploads real skill content and explicit cold update preserves its local source",
       ctx do
    initial = source_snapshot(ctx)
    assert_source(ctx, @skill)
    warm = start(ctx)
    assert uploads(ctx) === []
    set_features(ctx, true)

    first = save(ctx, warm.pid, %{"pluginPath" => ctx.source}, Enum.at(@ids, 0))
    assert first["remotePluginId"] === @remote
    assert first["shareUrl"] === "https://synthetic.invalid/share/ordinary-v1"
    assert mapping(ctx) === %{@remote => ctx.source}
    assert_source(ctx, @skill)
    assert source_snapshot(ctx) === initial
    assert_uploads(ctx, [@skill])
    assert_empty_loaded(ctx, warm.pid)
    assert_idle(warm.pid)
    close(warm)
    prefix = Agent.get(ctx.capture, & &1.frames)
    assert_controls(ctx, true)

    File.write!(Path.join(ctx.source, "skills/notes/SKILL.md"), @edited_skill)
    assert_source(ctx, @edited_skill)
    edited = source_snapshot(ctx)
    assert edited[".codex-plugin/plugin.json"] === initial[".codex-plugin/plugin.json"]
    assert edited["marker.txt"] === initial["marker.txt"]
    refute edited["skills/notes/SKILL.md"] === initial["skills/notes/SKILL.md"]
    set_features(ctx, false)
    cold = start(ctx)
    refute cold.native === warm.native
    refute cold.instance === warm.instance
    assert_uploads(ctx, [@skill])
    assert mapping(ctx) === %{@remote => ctx.source}
    assert source_snapshot(ctx) === edited
    set_features(ctx, true)

    second =
      save(
        ctx,
        cold.pid,
        %{"pluginPath" => ctx.source, "remotePluginId" => first["remotePluginId"]},
        Enum.at(@ids, 1)
      )

    assert second["remotePluginId"] === @remote
    assert second["shareUrl"] === "https://synthetic.invalid/share/ordinary-v2"
    assert mapping(ctx) === %{@remote => ctx.source}
    assert_source(ctx, @edited_skill)
    assert source_snapshot(ctx) === edited
    assert_uploads(ctx, [@skill, @edited_skill])
    assert_empty_loaded(ctx, cold.pid)
    assert_idle(cold.pid)
    close(cold)
    frames = Agent.get(ctx.capture, & &1.frames)
    assert Enum.take(frames, length(prefix)) === prefix
    assert_inventory(frames, ctx.source)
    assert_controls(ctx, true)
    close_provider(ctx)
    assert_controls(ctx, true)
    assert_uploads(ctx, [@skill, @edited_skill])
  end

  defp save(ctx, pid, params, id) do
    wire = %{"id" => id, "method" => "plugin/share/save", "params" => params}
    assert_request(wire)
    # Only content/result identity is qualified; the remaining result is opaque.
    call(ctx, pid, wire)
  end

  defp assert_request(wire) do
    document = schema_path() |> File.read!() |> JSON.decode!()

    assert Enum.at(document["oneOf"], 78) === %{
             "properties" => %{
               "id" => %{"$ref" => "#/definitions/RequestId"},
               "method" => %{
                 "enum" => ["plugin/share/save"],
                 "title" => "Plugin/share/saveRequestMethod",
                 "type" => "string"
               },
               "params" => %{"$ref" => "#/definitions/PluginShareSaveParams"}
             },
             "required" => ["id", "method", "params"],
             "title" => "Plugin/share/saveRequest",
             "type" => "object"
           }

    assert Enum.sort(Map.keys(wire)) === ["id", "method", "params"]
    assert wire["method"] === "plugin/share/save"
    assert is_binary(wire["params"]["pluginPath"])
    assert Path.type(wire["params"]["pluginPath"]) === :absolute
  end

  defp assert_source(ctx, skill) do
    assert File.read!(Path.join(ctx.source, ".codex-plugin/plugin.json")) === @manifest
    assert File.read!(Path.join(ctx.source, "marker.txt")) === @marker
    assert File.read!(Path.join(ctx.source, "skills/notes/SKILL.md")) === skill
    assert Enum.sort(File.ls!(ctx.source)) === [".codex-plugin", "marker.txt", "skills"]
    assert File.ls!(Path.join(ctx.source, ".codex-plugin")) === ["plugin.json"]
    assert File.ls!(Path.join(ctx.source, "skills")) === ["notes"]
    assert File.ls!(Path.join(ctx.source, "skills/notes")) === ["SKILL.md"]
  end

  defp source_snapshot(ctx),
    do:
      Map.new(~w(.codex-plugin/plugin.json marker.txt skills/notes/SKILL.md), fn name ->
        {name, snapshot(Path.join(ctx.source, name))}
      end)

  defp assert_uploads(ctx, skills) do
    count = length(skills)
    assert length(rows(ctx, "upload_url")) === count
    assert length(uploads(ctx)) === count
    assert length(rows(ctx, "finalize")) === count

    Enum.with_index(skills, 1)
    |> Enum.each(fn {skill, sequence} ->
      upload = Enum.at(rows(ctx, "upload_url"), sequence - 1)
      blob = Enum.at(uploads(ctx), sequence - 1)
      finalize = Enum.at(rows(ctx, "finalize"), sequence - 1)
      path = "/backend-api/public/plugins/workspace"
      archive = snapshot(Path.join(ctx.root, "ordinary-share-upload-#{sequence}.tar.gz"))
      assert 0 < byte_size(archive.bytes) and byte_size(archive.bytes) <= 131_072

      assert upload === %{
               "event" => "upload_url",
               "sequence" => sequence,
               "path" => path <> "/upload-url",
               "filename" => "ordinary-source.tar.gz",
               "mime_type" => "application/gzip",
               "size" => byte_size(archive.bytes),
               "plugin_id" => if(sequence === 1, do: nil, else: @remote),
               "file_id" => "file_ordinary_save_#{sequence}",
               "etag" => ~s("upload_url_ordinary_#{sequence}")
             }

      assert blob === %{
               "event" => "blob_upload",
               "sequence" => sequence,
               "path" => "/upload/ordinary/#{sequence}",
               "size" => byte_size(archive.bytes),
               "archive" => "ordinary-share-upload-#{sequence}.tar.gz",
               "sha256" => archive.sha256,
               "files" => %{
                 ".codex-plugin/plugin.json" => @manifest,
                 "marker.txt" => @marker,
                 "skills/notes/SKILL.md" => skill
               }
             }

      assert finalize === %{
               "event" => "finalize",
               "sequence" => sequence,
               "path" => if(sequence === 1, do: path, else: path <> "/" <> @remote),
               "file_id" => upload["file_id"],
               "etag" => upload["etag"]
             }
    end)

    expected_events = List.duplicate(~w(upload_url blob_upload finalize), count) |> List.flatten()
    assert Enum.map(content_events(ctx), & &1["event"]) === expected_events

    if count === 2 do
      [first, second] = uploads(ctx)
      refute first["sha256"] === second["sha256"]
    end
  end

  defp set_features(ctx, enabled) do
    before = if enabled, do: ctx.disabled, else: ctx.enabled
    after_value = if enabled, do: ctx.enabled, else: ctx.disabled
    assert File.read!(ctx.config) === before
    path = ctx.config <> ".ordinary-pending"
    File.write!(path, after_value, [:exclusive])
    File.rename!(path, ctx.config)
    assert File.read!(ctx.config) === after_value
  end

  defp mapping(ctx) do
    path = Path.join(ctx.fixture.codex_home, ".tmp/plugin-share-local-paths-v1.json")
    snapshot(path).bytes |> JSON.decode!() |> Map.fetch!("localPluginPathsByRemotePluginId")
  end

  defp assert_controls(ctx, enabled) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.read!(ctx.config) === if(enabled, do: ctx.enabled, else: ctx.disabled)
    assert ModelFixture.requests(ctx.fixture) === []
    assert File.ls!(ctx.fixture.workspace) === []
    assert rows(ctx, "fatal") === []
    assert rows(ctx, "unexpected_http") === []
  end

  defp rows(ctx, kind) do
    journal =
      snapshot(Path.join(ctx.root, "ordinary-share-save-journal.json")).bytes |> JSON.decode!()

    assert length(journal["events"]) <= 128
    Enum.filter(journal["events"], &(&1["event"] === kind))
  end

  defp uploads(ctx), do: rows(ctx, "blob_upload")

  defp content_events(ctx) do
    journal =
      snapshot(Path.join(ctx.root, "ordinary-share-save-journal.json")).bytes |> JSON.decode!()

    Enum.filter(journal["events"], &(&1["event"] in ~w(upload_url blob_upload finalize)))
  end

  defp start(ctx) do
    assert File.read!(ctx.config) === ctx.disabled
    # Plugin feature setup belongs to the owned TOML refreshed after initialization.
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
    info = %{"name" => "owned_ordinary_plugin_share_save", "version" => "0.1.0"}
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
    assert_empty_loaded(ctx, pid)
    %{pid: pid, connection: connection, native: native, instance: Session.status(pid).instance_id}
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
    frames = Agent.get(ctx.capture, & &1.frames)
    assert [sent, received] = Enum.filter(frames, &(&1.wire["id"] === wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded_request} = Wire.decode(sent.encoded, max_depth: 32)
    assert decoded_request === wire
    assert {:ok, decoded_response} = Wire.decode(received.encoded, max_depth: 32)
    assert decoded_response === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_inventory(frames, source) do
    outgoing = Enum.filter(frames, &(&1.direction === :out))

    expected =
      ~w(initialize initialized server/diagnostics thread/loaded/list plugin/share/save thread/loaded/list)

    assert Enum.map(outgoing, & &1.wire["method"]) === expected ++ expected
    saves = Enum.filter(outgoing, &(&1.wire["method"] === "plugin/share/save"))
    assert Enum.map(saves, & &1.wire["id"]) === @ids

    assert Enum.map(saves, & &1.wire["params"]) === [
             %{"pluginPath" => source},
             %{"pluginPath" => source, "remotePluginId" => @remote}
           ]

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames, &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 10 and length(Enum.uniq(ids)) === 10
    assert length(replies) === 10
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

  defp schema_path,
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/ClientRequest.json")

  defp request_id, do: "owned-share-save-#{System.unique_integer([:positive, :monotonic])}"
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
