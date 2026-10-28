defmodule SamgitaCodexDriver.NativeOrdinaryMcpNotStartedTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/ordinary_mcp_not_started_fixture.py", __DIR__)
  @provider_sha "45f6a1c723f8ca8eeb4d8558c8198c3e11104bbde9efb02ae79be0c3137417e7"
  @peer Path.expand("../../../scripts/codex/ordinary_mcp_not_started_peer.py", __DIR__)
  @peer_sha "6bd0eddefd7b8759df8dbe5ea5fbdf4c6979b6cc15bfdf56688d84dcc4207bfb"
  @base Path.expand("../../../scripts/codex/subagent_search_provenance_fixture.py", __DIR__)
  @base_sha "7ef1d60b7085696f92e83aa970da8e2dd08636d4a7c7f4414ce29e007ffe9bfb"
  @model Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @model_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @status_sha "00c56c0faacbd4950b7f446f20b11b8a95456c5108de2f1e7366a1b2e60db8c6"
  @not_started_sha "72e41c38bb91284167523b58c1765d474c64b1e10e58d026b4310c0feb2daa9f"
  @not_started_bytes """
  "notStarted"
  """
  @root "Owned source provenance root λ"
  @child "Owned source provenance child 🙂"
  @root_answer "Owned source provenance root done"
  @child_answer @child <> " done"
  @name "ordinary_dormant"

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
      Enum.reduce_while(events, :ok, fn
        {:message, encoded}, :ok ->
          case record(state, :in, encoded) do
            :ok -> {:cont, :ok}
            failure -> {:halt, failure}
          end

        _, :ok ->
          {:cont, :ok}
      end)
    end

    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if length(ledger.frames) < 256 and size <= 262_144 and ledger.bytes + size <= 4_194_304 do
          frame = %{direction: direction, encoded: encoded}
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

    for {path, sha} <- [
          {@provider, @provider_sha},
          {@peer, @peer_sha},
          {@base, @base_sha},
          {@model, @model_sha}
        ],
        do: assert(hash(File.read!(path)) === sha)

    assert hash(File.read!(schema_path())) === @status_sha
    suffix = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    root = Path.join(System.tmp_dir!(), "owned-ordinary-mcp-not-started-#{suffix}")
    File.mkdir!(root)
    resources = :atomics.new(2, [])

    on_exit(fn ->
      assert Enum.all?(1..2, &(:atomics.get(resources, &1) in [0, 2])),
             "Owned cleanup unconfirmed; retaining #{root}"

      File.rm_rf!(root)
    end)

    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    :atomics.put(resources, 1, 1)
    ctx = %{binary: Path.expand(binary), root: root, fixture: fixture, resources: resources}
    on_exit(fn -> assert :ok = close_provider(ctx) end)
    File.write!(fixture.requests, "[]")

    TurnFixture.configure_model(ctx, %{
      "multi_agent_version" => "v2",
      "default_reasoning_level" => "medium",
      "supported_reasoning_levels" => [
        %{"effort" => "medium", "description" => "Owned local medium effort"}
      ]
    })

    paths = [
      @provider,
      @peer,
      @base,
      @model,
      schema_path(),
      Path.join(ctx.fixture.codex_home, "config.toml"),
      Path.join(ctx.fixture.codex_home, "turn-models.json")
    ]

    Map.merge(ctx, %{
      inputs: Map.new(paths, &{&1, snapshot(&1)}),
      capture: start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    })
  end

  test "native child keeps a warm ordinary MCP connection unstarted through independent status discovery",
       ctx do
    native = start(ctx)

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    root =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(root) and root != ""

    # Native Ready follows publication of the genuine initial regular-tool cache.
    await(
      fn ->
        Enum.any?(frames(ctx, :in), fn frame ->
          frame.wire["method"] === "mcpServer/startupStatus/updated" and
            Map.take(frame.wire["params"], ~w(threadId name status)) ===
              %{"threadId" => root, "name" => @name, "status" => "ready"}
        end)
      end,
      now() + 5_000
    )

    assert_peer_inventory(ctx, 1)
    assert ModelFixture.requests(ctx.fixture) === []

    turn =
      call(ctx, native.pid, "turn/start", %{
        "threadId" => root,
        "input" => [%{"type" => "text", "text" => @root}],
        "effort" => "medium"
      })["turn"]["id"]

    await(
      fn ->
        Enum.any?(frames(ctx, :in), fn frame ->
          frame.wire["method"] === "turn/completed" and frame.wire["params"]["threadId"] === root and
            frame.wire["params"]["turn"]["id"] === turn
        end)
      end,
      now() + 20_000
    )

    # The provider's native wait result and the completed parent turn give a
    # causal child-completion barrier. The child never emits an MCP call.
    relation =
      call(ctx, native.pid, "thread/list", %{
        "parentThreadId" => root,
        "sourceKinds" => ["subAgentThreadSpawn"],
        "sortKey" => "created_at",
        "limit" => 100,
        "useStateDbOnly" => true
      })

    assert %{"data" => [child], "nextCursor" => nil} = relation
    child_id = child["id"]
    assert is_binary(child_id) and child_id != "" and child_id != root
    assert child["parentThreadId"] === root
    assert child["cwd"] === ctx.fixture.workspace
    assert get_in(child, ["source", "subAgent", "thread_spawn", "parent_thread_id"]) === root
    assert_answer(ctx, native.pid, root, @root_answer)
    assert_answer(ctx, native.pid, child_id, @child_answer)
    assert_provider(ctx, root, child_id)
    assert_peer_inventory(ctx, 1)

    params = %{"threadId" => child_id, "detail" => "toolsAndAuthOnly", "limit" => 1}
    refute Map.has_key?(params, "serverName")
    wire = %{"id" => 4225, "method" => "mcpServerStatus/list", "params" => params}
    result = call(ctx, native.pid, wire)
    assert %{"data" => [row], "nextCursor" => nil} = result
    assert row["name"] === @name

    assert Map.take(row["serverInfo"], ~w(name version)) ===
             %{"name" => "owned-ordinary-cached-peer", "version" => "1"}

    assert_not_started_binding(ctx, row)
    assert_peer_inventory(ctx, 2)

    # This public read used a separate eager temporary peer. The original child
    # has never started a peer, and no later action starts it in this scenario.
    assert %{"data" => loaded, "nextCursor" => nil} =
             call(ctx, native.pid, "thread/loaded/list", %{})

    assert MapSet.new(loaded) === MapSet.new([root, child_id])
    assert_provider(ctx, root, child_id)
    assert_peer_inventory(ctx, 2)

    startup =
      for frame <- frames(ctx, :in),
          frame.wire["method"] === "mcpServer/startupStatus/updated",
          do: Map.take(frame.wire["params"], ~w(threadId name status))

    assert startup === [
             %{"threadId" => root, "name" => @name, "status" => "starting"},
             %{"threadId" => root, "name" => @name, "status" => "ready"}
           ]

    assert_inventory(ctx)
    assert_controls(ctx)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(native.pid)

    close_native(native)

    for peer <- peer_journals(ctx), %{"event" => "started", "pid" => pid} <- peer do
      await(fn -> not File.exists?("/proc/#{pid}") end, now() + 5_000)
    end

    assert_peer_inventory(ctx, 2)
    assert_controls(ctx)
    assert :ok = close_provider(ctx)
    assert_controls(ctx)
  end

  defp assert_not_started_binding(ctx, row) do
    document = JSON.decode!(File.read!(schema_path()))
    definition = document["definitions"]["McpServerConnectionStatus"]
    assert Enum.fetch!(definition["enum"], 0) === "notStarted"
    assert hash(@not_started_bytes) === @not_started_sha
    assert JSON.decode!(@not_started_bytes) === Enum.fetch!(definition["enum"], 0)
    assert row["runtimeStatus"] === "notStarted"

    assert :ok =
             Schema.validate(
               Map.put(definition, "definitions", document["definitions"]),
               Map.fetch!(row, "runtimeStatus")
             )

    assert [reply] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === 4225))
    assert {:ok, original} = Wire.decode(reply.encoded, max_depth: 64)
    assert original === reply.wire
    assert original["result"]["data"] === [row]
  end

  defp assert_answer(ctx, pid, id, answer) do
    thread = call(ctx, pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert thread["id"] === id
    assert [%{"status" => "completed", "error" => nil, "items" => items}] = thread["turns"]
    assert [%{"text" => ^answer}] = Enum.filter(items, &(&1["type"] === "agentMessage"))
  end

  defp assert_provider(ctx, root, child) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) === 4

    assert Enum.frequencies_by(requests, fn request ->
             assert request["model"] === "mock-model"
             assert request["reasoning"]["effort"] === "medium"
             metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
             metadata["thread_id"]
           end) === %{root => 3, child => 1}

    observed = JSON.decode!(snapshot(Path.join(ctx.root, "provenance-observed.json")))
    assert observed === %{"root_requests" => 3, "child_requests" => 1, "errors" => []}
  end

  defp assert_peer_inventory(ctx, count) do
    await(
      fn ->
        peers = peer_journals(ctx)

        length(peers) === count and
          Enum.all?(peers, fn rows ->
            Enum.any?(rows, &(&1["event"] === "reply" and &1["method"] === "tools/list"))
          end)
      end,
      now() + 5_000
    )

    peers = peer_journals(ctx)
    assert length(peers) === count

    for rows <- peers do
      assert Enum.map(Enum.filter(rows, &(&1["event"] === "request")), & &1["method"]) ===
               ["initialize", "tools/list"]

      assert Enum.map(Enum.filter(rows, &(&1["event"] === "notification")), & &1["method"]) ===
               ["notifications/initialized"]

      assert Enum.map(Enum.filter(rows, &(&1["event"] === "reply")), & &1["method"]) ===
               ["initialize", "tools/list"]

      assert Enum.filter(rows, &(&1["event"] === "fatal")) === []

      assert [%{"event" => "started", "pid" => pid}] =
               Enum.filter(rows, &(&1["event"] === "started"))

      assert is_integer(pid) and pid > 0

      for request <- Enum.filter(rows, &(&1["event"] === "request")) do
        assert_peer_reply(rows, request)
      end
    end
  end

  defp assert_peer_reply(rows, request) do
    assert JSON.decode!(request["raw"]) === request["request"]

    assert [reply] =
             Enum.filter(
               rows,
               &(&1["event"] === "reply" and &1["method"] === request["method"])
             )

    original = JSON.decode!(reply["raw"])
    assert original["id"] === request["request"]["id"]

    if request["method"] === "tools/list" do
      assert original["result"] === %{
               "tools" => [
                 %{
                   "name" => "owned_lookup",
                   "description" => "Owned cached descriptor λ🙂",
                   "inputSchema" => %{
                     "type" => "object",
                     "properties" => %{"key" => %{"type" => "string"}}
                   }
                 }
               ]
             }
    end
  end

  defp peer_journals(ctx) do
    paths = Path.wildcard(Path.join(ctx.root, "ordinary-mcp-peers/peer-*.jsonl"))
    assert length(paths) <= 2

    Enum.map(paths, fn path ->
      assert File.stat!(path).size <= 131_072
      rows = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      assert length(rows) <= 16
      rows
    end)
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 4_194_304,
               max_message_bytes: 262_144,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1"
                    }
                  ]}
             )

    :atomics.put(ctx.resources, 2, 1)
    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
      assert_peers_stopped(ctx)
      :atomics.put(ctx.resources, 2, 2)
    end)

    id = request_id()
    info = %{"name" => "owned_ordinary_mcp_not_started", "version" => "1"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{
        "clientInfo" => info,
        "capabilities" => capabilities
      }
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = reply} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, reply)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, native: native, connection: connection, root: ctx.root, resources: ctx.resources}
  end

  defp call(ctx, pid, method, params),
    do: call(ctx, pid, %{"id" => request_id(), "method" => method, "params" => params})

  defp call(ctx, pid, wire) do
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result} = reply} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, reply)
    result
  end

  defp assert_exchange(ctx, wire, reply) do
    assert [sent] = Enum.filter(frames(ctx, :out), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(frames(ctx, :in), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === reply

    for frame <- [sent, received] do
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire
    end
  end

  defp assert_inventory(ctx) do
    outgoing = frames(ctx, :out)

    assert Enum.map(outgoing, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/start turn/start thread/list thread/read thread/read mcpServerStatus/list thread/loaded/list)

    requests = Enum.filter(outgoing, &Map.has_key?(&1.wire, "id"))
    replies = Enum.filter(frames(ctx, :in), &Map.has_key?(&1.wire, "id"))
    assert length(requests) === 10 and length(replies) === 10
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) === 10
    assert MapSet.new(Enum.map(replies, & &1.wire["id"])) === MapSet.new(ids)
  end

  defp assert_controls(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(snapshot(path) === bytes)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
    assert_peers_stopped(native)
    :atomics.put(native.resources, 2, 2)
    :ok
  end

  defp assert_peers_stopped(ctx) do
    for peer <- peer_journals(ctx), %{"event" => "started", "pid" => pid} <- peer do
      await(fn -> not File.exists?("/proc/#{pid}") end, now() + 5_000)
    end
  end

  defp close_provider(ctx) do
    path = Path.join(ctx.root, "ordinary-mcp-provider-lifecycle.json")

    try do
      unless Map.has_key?(JSON.decode!(snapshot(path)), "closed") do
        # A line is only the owned provider's existing shutdown control. It is
        # neither an app-server request nor a model Responses request.
        assert {:ok, _} = Stdio.send(ctx.fixture.transport, "{}")

        await(
          fn -> Map.has_key?(JSON.decode!(snapshot(path)), "closed") end,
          now() + 5_000
        )
      end
    after
      assert :ok = ModelFixture.close(ctx.fixture)
    end

    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    assert %{"started" => helper, "closed" => closed} = JSON.decode!(snapshot(path))
    assert is_integer(helper) and helper > 0 and helper === closed
    await(fn -> not File.exists?("/proc/#{helper}") end, now() + 5_000)
    :atomics.put(ctx.resources, 1, 2)
    :ok
  end

  defp frames(ctx, direction) do
    Agent.get(ctx.capture, &Enum.filter(&1.frames, fn row -> row.direction === direction end))
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp schema_path,
    do:
      Path.expand(
        "../../samgita_protocol_codex/priv/upstream/0.163.0/experimental/v2/ListMcpServerStatusResponse.json",
        __DIR__
      )

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    bytes
  end

  defp await(predicate, deadline) do
    unless predicate.() do
      assert now() < deadline, "Owned ordinary MCP not-started observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp request_id, do: "owned-mcp-not-started-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
