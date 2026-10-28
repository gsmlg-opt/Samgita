defmodule SamgitaCodexDriver.NativeOrdinaryRawEnvelopesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_raw_envelope_fixture.py", __DIR__)
  @script_sha "de78fc6ce406337f15159b67c892f06d14912039adb5f4f61877ca925dab5f86"
  @encoder Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @encoder_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @cleanup Path.join(__DIR__, "support/stdio_session_fixture.ex")
  @cleanup_sha "a164a57adff4cba26360a7e2788b8c3e9e6829a0a5e77eae28e857c29dc201a0"
  @root_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  @supplement_sha "ecee759716e9ec50e342e033cfeab5a650f51e480cfa2180d29b127b23792757"
  @marker "Owned ordinary raw envelope λ🙂"
  @answer "Owned ordinary raw envelope answer β🙂"
  @item "owned-ordinary-raw-item-3234"
  @response "fixture-response-1"
  @raw_item "rawResponseItem/completed"
  @raw_response "rawResponse/completed"
  @item_variant """
  {
    "properties": {
      "method": {
        "enum": [
          "rawResponseItem/completed"
        ],
        "type": "string"
      },
      "params": {
        "$ref": "#/definitions/RawResponseItemCompletedNotification"
      }
    },
    "required": [
      "method",
      "params"
    ],
    "title": "RawResponseItemCompletedNotification",
    "type": "object"
  }
  """
  @response_variant """
  {
    "properties": {
      "method": {
        "enum": [
          "rawResponse/completed"
        ],
        "type": "string"
      },
      "params": {
        "$ref": "#/definitions/RawResponseCompletedNotification"
      }
    },
    "required": [
      "method",
      "params"
    ],
    "title": "RawResponseCompletedNotification",
    "type": "object"
  }
  """
  @contracts [
    {3234, @item_variant, "4cf2e98d8e68b7f6b9d43c5606043412776364896afb6ea49527e47ab64c9c70"},
    {3235,
     """
     {
       "enum": [
         "rawResponseItem/completed"
       ],
       "type": "string"
     }
     """, "85d2b5f928705608b1ccf36ecf0066f42d807029a4cba21acfd6ea303444c327"},
    {3236,
     """
     "rawResponseItem/completed"
     """, "80b22e70682da414f06b140b15f2789d0c3e41df0e84baae0828c5d324e66f10"},
    {3237,
     """
     {
       "$ref": "#/definitions/RawResponseItemCompletedNotification"
     }
     """, "1363057c6971b6e567f73ef4c5cbf6d4dfa4c2ce54d35050f0c3de5e90d302e8"},
    {3238, @response_variant, "cce7e29258ec11edc7aff86fb88d4d9ec91c940f1f3f34ab78a9faa6a4c6882e"},
    {3239,
     """
     {
       "enum": [
         "rawResponse/completed"
       ],
       "type": "string"
     }
     """, "10b145d3d428e9934ea366c44a0842bdcec0d22ed2a7fb78f9c8a16e8aff618d"},
    {3240,
     """
     "rawResponse/completed"
     """, "90cebfcf1da8475922c715c2c811e85f49eab515c495850d3dd5fd2cf2969eb7"},
    {3241,
     """
     {
       "$ref": "#/definitions/RawResponseCompletedNotification"
     }
     """, "f80f01b8192771f952d4e42fc64d3709345cad9d983b52cf27c6993783341aee"},
    {3242,
     """
     {
       "description": "Unix timestamp (in milliseconds) when app-server emitted this notification.",
       "format": "int64",
       "type": "integer"
     }
     """, "180584a60ba9408fcbc37a3edcf90a1cca0687ab1ef8f32b660a588a10671ab2"}
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
    def send(state, bytes) do
      case Stdio.send(state, bytes) do
        {:ok, next} ->
          case record(next, :out, bytes) do
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
        {:message, bytes}, :ok ->
          case record(state, :in, bytes) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, bytes) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(bytes)
        limit = if direction == :out, do: 8192, else: 131_072

        if length(ledger.frames) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
          frame = %{direction: direction, encoded: bytes, wire: JSON.decode!(bytes)}
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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha

    for {path, sha} <- [
          {@script, @script_sha},
          {@encoder, @encoder_sha},
          {@cleanup, @cleanup_sha},
          {schema_path("experimental/ClientRequest.json"), @root_sha},
          {schema_path("supplemental/ServerNotification.json"), @supplement_sha}
        ],
        do: assert(hash(File.read!(path)) === sha)

    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-raw-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining raw envelope fixture #{root}"

      File.rm_rf!(root)
    end)

    for child <- ~w(home codex workspace bin tmp), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      home: Path.join(root, "home"),
      codex: Path.join(root, "codex"),
      workspace: Path.join(root, "workspace"),
      bin: Path.join(root, "bin"),
      requests: Path.join(root, "requests.json"),
      resources: resources,
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    }

    peer = start_peer(ctx)

    paths = [
      @script,
      @encoder,
      @cleanup,
      Path.join(ctx.codex, "config.toml"),
      Path.join(ctx.codex, "models.json"),
      Path.join(ctx.bin, "sh"),
      schema_path("experimental/ClientRequest.json"),
      schema_path("supplemental/ServerNotification.json")
    ]

    Map.merge(ctx, %{peer: peer, inputs: Map.new(paths, &{&1, snapshot(&1)})})
  end

  test "actual native raw item and response bytes bind nine supplemental envelope nodes", ctx do
    native = start_native(ctx)
    assert_empty_loaded(ctx, native.pid)

    result =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "ephemeral" => true,
        "experimentalRawEvents" => true
      })

    thread = result["thread"]["id"]
    assert is_binary(thread) and byte_size(thread) > 0
    assert_setup(ctx)
    assert snapshot(ctx.requests).bytes |> JSON.decode!() === []
    before_ms = System.system_time(:millisecond)

    started =
      call(ctx, native.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })

    turn = started["turn"]["id"]
    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(ctx, native.pid, thread, turn, [], now() + 20_000)
    after_ms = System.system_time(:millisecond)
    assert_completed(events, thread, turn)
    item_frame = raw_frame(ctx, @raw_item, &(&1["item"]["id"] === @item))
    response_frame = raw_frame(ctx, @raw_response, &(&1["responseId"] === @response))
    assert Enum.any?(events, &(&1.wire === item_frame.wire))
    assert Enum.any?(events, &(&1.wire === response_frame.wire))

    assert Map.take(item_frame.wire["params"], ["threadId", "turnId"]) === %{
             "threadId" => thread,
             "turnId" => turn
           }

    assert Map.take(item_frame.wire["params"]["item"], ["type", "id", "role", "content"]) === %{
             "type" => "message",
             "id" => @item,
             "role" => "assistant",
             "content" => [%{"type" => "output_text", "text" => @answer}]
           }

    assert Map.take(response_frame.wire["params"], ["threadId", "turnId", "responseId"]) === %{
             "threadId" => thread,
             "turnId" => turn,
             "responseId" => @response
           }

    assert_physical(ctx, item_frame, response_frame, before_ms, after_ms)
    assert_provider(ctx, thread, turn)
    assert_setup(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    assert Session.uncertain_operations(native.pid) === []
    assert_inventory(ctx)
    close_native(native)
    requests_before = snapshot(ctx.requests)
    close_peer(ctx.peer)
    assert snapshot(ctx.requests) === requests_before
    assert_setup(ctx)

    assert rows(ctx, "fixture_closed") === [
             %{"event" => "fixture_closed", "pid" => ctx.peer.native}
           ]
  end

  defp assert_physical(_ctx, item_frame, response_frame, before_ms, after_ms) do
    root = schema("supplemental/ServerNotification.json")
    variants = Map.fetch!(root, "oneOf")
    definitions = Map.fetch!(root, "definitions")
    assert length(variants) === 2

    nodes = %{
      3234 => Enum.at(variants, 0),
      3235 => get_in(Enum.at(variants, 0), ["properties", "method"]),
      3236 => get_in(Enum.at(variants, 0), ["properties", "method", "enum"]) |> Enum.at(0),
      3237 => get_in(Enum.at(variants, 0), ["properties", "params"]),
      3238 => Enum.at(variants, 1),
      3239 => get_in(Enum.at(variants, 1), ["properties", "method"]),
      3240 => get_in(Enum.at(variants, 1), ["properties", "method", "enum"]) |> Enum.at(0),
      3241 => get_in(Enum.at(variants, 1), ["properties", "params"]),
      3242 => get_in(root, ["properties", "emittedAtMs"])
    }

    for {owner, bytes, sha} <- @contracts do
      assert hash(bytes) === sha
      assert JSON.decode!(bytes) === Map.fetch!(nodes, owner)
    end

    for {frame, method, index} <- [{item_frame, @raw_item, 0}, {response_frame, @raw_response, 1}] do
      assert [selected] =
               Enum.filter(
                 variants,
                 &(get_in(&1, ["properties", "method", "enum"]) === [method])
               )

      assert selected === Enum.at(variants, index)
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)

      assert :ok =
               Schema.validate(Map.put(selected, "definitions", definitions), frame.wire,
                 max_depth: 64
               )

      assert :ok =
               Schema.validate(get_in(selected, ["properties", "method"]), frame.wire["method"])

      assert :ok =
               Schema.validate(
                 Map.put(get_in(selected, ["properties", "params"]), "definitions", definitions),
                 frame.wire["params"],
                 max_depth: 64
               )

      emitted = Map.fetch!(frame.wire, "emittedAtMs")
      assert :ok = Schema.validate(nodes[3242], emitted)
      assert is_integer(emitted) and emitted > 0 and emitted >= before_ms and emitted <= after_ms
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire and JSON.decode!(frame.encoded) === frame.wire
    end
  end

  defp assert_completed(events, thread, turn) do
    assert [complete] = Enum.filter(events, &(&1.wire["method"] === "turn/completed"))

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             complete.wire["params"]

    messages =
      Enum.filter(
        events,
        &(&1.wire["method"] === "item/completed" and
            &1.wire["params"]["item"]["type"] === "agentMessage")
      )

    assert [message] = messages

    assert %{"threadId" => ^thread, "turnId" => ^turn, "item" => %{"text" => @answer}} =
             message.wire["params"]
  end

  defp collect(ctx, pid, thread, turn, accumulated, deadline) do
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = accumulated ++ fresh
    assert length(events) <= 128

    complete? =
      Enum.any?(
        events,
        &(&1.wire["method"] === "turn/completed" and
            &1.wire["params"]["threadId"] === thread and &1.wire["params"]["turn"]["id"] === turn)
      )

    item? =
      Enum.any?(
        events,
        &(&1.wire["method"] === @raw_item and &1.wire["params"]["item"]["id"] === @item)
      )

    response? =
      Enum.any?(
        events,
        &(&1.wire["method"] === @raw_response and &1.wire["params"]["responseId"] === @response)
      )

    if complete? and item? and response? do
      events
    else
      remaining = deadline - now()
      assert remaining > 0, "Owned ordinary raw event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(ctx, pid, thread, turn, events, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Owned ordinary raw event gap")
      after
        remaining -> flunk("Owned ordinary raw event deadline")
      end
    end
  end

  defp assert_provider(ctx, thread, turn) do
    assert rows(ctx, "provider_request") === [
             %{
               "event" => "provider_request",
               "method" => "POST",
               "path" => "/v1/responses",
               "query" => "",
               "status" => 200,
               "sequence" => 1
             }
           ]

    assert [request] = snapshot(ctx.requests).bytes |> JSON.decode!()
    assert request["model"] === "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ["thread_id", "turn_id"]) === %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    markers =
      for item <- request["input"],
          item["role"] === "user",
          part <- Map.get(item, "content", []),
          is_map(part),
          part["type"] === "input_text",
          do: part["text"]

    assert Enum.count(markers, &(&1 === @marker)) === 1
  end

  defp assert_inventory(ctx) do
    outgoing = Enum.filter(frames(ctx), &(&1.direction === :out))

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics
      thread/loaded/list thread/start turn/start thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 6 and length(Enum.uniq(ids)) === 6
    replies = Enum.filter(frames(ctx), &(&1.direction === :in and Map.has_key?(&1.wire, "id")))
    assert length(replies) === 6
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp start_peer(ctx) do
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
                 ctx.requests
               ],
               cwd: ctx.workspace,
               inherit_env: [],
               max_message_bytes: 8192,
               env: %{
                 "HOME" => ctx.home,
                 "CODEX_HOME" => ctx.codex,
                 "TMPDIR" => Path.join(ctx.root, "tmp"),
                 "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
                 "PYTHONDONTWRITEBYTECODE" => "1"
               }
             )

    :atomics.put(ctx.resources, 1, 1)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity, ctx.resources, 1) end)
    startup = peer_startup(transport.port, <<>>, now() + 5_000)
    native = startup["pid"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === hash(File.read!(ctx.python))
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    %{transport: transport, identity: identity, native: native, resources: ctx.resources}
  end

  defp peer_startup(port, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0 and byte_size(bytes) <= 8192, "Owned raw peer startup bound"

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected owned raw peer startup output")

      [_partial] ->
        receive do
          {^port, {:data, chunk}} -> peer_startup(port, bytes <> chunk, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned raw peer exited #{status}")
        after
          remaining -> flunk("Owned raw peer startup deadline")
        end
    end
  end

  defp start_native(ctx) do
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
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
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
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    :atomics.put(ctx.resources, 2, 1)
    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity, resources: ctx.resources}
    on_exit(fn -> close_native(native) end)
    id = request_id()
    info = %{"name" => "owned_ordinary_raw_envelopes", "version" => "1"}
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
    native
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}
    assert :ok = Schema.validate(schema("experimental/ClientRequest.json"), wire, max_depth: 64)
    reply = Session.request_native(pid, wire, timeout_ms: 5_000)
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []
    assert {:ok, %{"id" => ^id, "result" => result} = response} = reply
    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    assert [sent] =
             Enum.filter(frames(ctx), &(&1.direction === :out and &1.wire["id"] === wire["id"]))

    assert [received] =
             Enum.filter(frames(ctx), &(&1.direction === :in and &1.wire["id"] === wire["id"]))

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response and Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp raw_frame(ctx, method, predicate) do
    assert [frame] =
             Enum.filter(
               frames(ctx),
               &(&1.direction === :in and
                   &1.wire["method"] === method and predicate.(&1.wire["params"]))
             )

    frame
  end

  defp assert_setup(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.ls!(ctx.workspace) === []
    assert rows(ctx, "fixture_error") === [] and rows(ctx, "unexpected_http") === []

    assert Enum.all?(
             journal(ctx),
             &(&1["event"] in ~w(fixture_started fixture_closed provider_request))
           )
  end

  defp frames(ctx), do: Agent.get(ctx.capture, & &1.frames)

  defp journal(ctx) do
    events =
      snapshot(Path.join(ctx.root, "ordinary-raw-envelope-journal.json")).bytes
      |> JSON.decode!()
      |> Map.fetch!("events")

    assert length(events) <= 32
    events
  end

  defp rows(ctx, event), do: Enum.filter(journal(ctx), &(&1["event"] === event))

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(native.connection, native.identity)
    :atomics.put(native.resources, 2, 2)
  end

  defp close_peer(peer), do: close_transport(peer.transport, peer.identity, peer.resources, 1)

  defp close_transport(connection, identity, resources, slot) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert_closed(connection, identity)
    :atomics.put(resources, slot, 2)
  end

  defp assert_closed(connection, identity) do
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp snapshot(path) do
    limit =
      if Path.basename(path) === "sh" and Path.basename(Path.dirname(path)) === "bin",
        do: File.stat!("/bin/sh").size,
        else: 1_048_576

    assert File.stat!(path).size <= limit
    bytes = File.read!(path)
    assert byte_size(bytes) <= limit
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(path), do: schema_path(path) |> File.read!() |> JSON.decode!()

  defp schema_path(path),
    do: :samgita_protocol_codex |> :code.priv_dir() |> Path.join("upstream/0.163.0/" <> path)

  defp request_id, do: "owned-ordinary-raw-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
