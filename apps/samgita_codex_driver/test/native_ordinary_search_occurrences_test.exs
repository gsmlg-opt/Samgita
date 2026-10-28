defmodule SamgitaCodexDriver.NativeOrdinarySearchOccurrencesTest do
  @moduledoc """
  One physical request-ID owner over genuine native paginated history. This does
  not exercise thread/search or its separate timestamp-cursor defect.
  """
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaProtocolCodex.{Error, Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @schema_hashes %{
    "ClientRequest.json" => "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352",
    "ServerNotification.json" =>
      "c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1",
    "v2/ThreadSearchOccurrencesParams.json" =>
      "c941938fd6e89675f6a6d2a475ac4433aad64614c3954515b13bf248e1c13525",
    "v2/ThreadSearchOccurrencesResponse.json" =>
      "193e1f78e427a93f5a6471b7b69ea3f6d980c924ca26e20845992bc5b33d9dd9"
  }
  @id_node_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_node_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @method "thread/searchOccurrences"
  @text "😀 Needle needle NEEDLE"
  @answer "Deterministic local fixture answer"
  @ranges [
    %{"start" => 3, "end" => 9},
    %{"start" => 10, "end" => 16},
    %{"start" => 17, "end" => 23}
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
        limit = if direction == :out, do: 8192, else: 131_072
        size = byte_size(encoded)

        if length(ledger.frames) < 128 and size <= limit and ledger.bytes + size <= 1_048_576 do
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

    for {name, expected} <- @schema_hashes,
        do: assert(hash(File.read!(schema_path(name))) === expected)

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-search-occurrences-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]", [:exclusive])
    fixture_pids = owned_process_tree(fixture.port)
    catalog = Path.join(fixture.codex_home, "ordinary-models.json")

    File.write!(
      catalog,
      JSON.encode!(%{
        "models" => [
          %{
            "slug" => "mock-model",
            "display_name" => "Owned ordinary occurrence input",
            "supported_reasoning_levels" => [],
            "shell_type" => "unified_exec",
            "visibility" => "list",
            "supported_in_api" => true,
            "priority" => 1,
            "model_messages" => %{
              "instructions_template" => "Owned deterministic local fixture only."
            },
            "support_verbosity" => false,
            "truncation_policy" => %{"mode" => "bytes", "limit" => 10_000},
            "experimental_supported_tools" => []
          }
        ]
      })
    )

    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(config, """
    model = "mock-model"
    model_provider = "fixture"
    model_catalog_json = #{JSON.encode!(catalog)}
    approval_policy = "never"
    sandbox_mode = "danger-full-access"
    cli_auth_credentials_store = "ephemeral"
    check_for_update_on_startup = false
    allow_login_shell = false
    web_search = "disabled"
    chatgpt_base_url = #{JSON.encode!(fixture.url)}
    openai_base_url = #{JSON.encode!(fixture.url <> "/v1")}
    [features]
    apps = false
    plugins = false
    remote_plugin = false
    recommended_plugins = false
    codex_hooks = false
    shell_snapshot = false
    memories = false
    [memories]
    generate_memories = false
    use_memories = false
    [analytics]
    enabled = false
    [otel]
    exporter = "none"
    trace_exporter = "none"
    metrics_exporter = "none"
    [model_providers.fixture]
    name = "Owned ordinary deterministic local provider"
    base_url = #{JSON.encode!(fixture.url <> "/v1")}
    wire_api = "responses"
    requires_openai_auth = false
    supports_websockets = false
    request_max_retries = 0
    stream_max_retries = 0
    """)

    capture = start_supervised!({Agent, fn -> %{frames: [], bytes: 0} end})
    paths = [@script, catalog, config] ++ Enum.map(Map.keys(@schema_hashes), &schema_path/1)

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      fixture_pids: fixture_pids,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native occurrence search preserves physical request id and paginated Unicode history across cold reads",
       ctx do
    warm = start(ctx)
    assert_empty_loaded(ctx, warm.pid)
    assert ModelFixture.requests(ctx.fixture) === []

    started =
      call(ctx, warm.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    thread = Map.fetch!(started["thread"], "id")
    assert is_binary(thread) and byte_size(thread) in 1..128

    turn =
      call(ctx, warm.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @text}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) in 1..128

    complete =
      await_notification(
        warm.pid,
        "turn/completed",
        fn params ->
          params["threadId"] === thread and params["turn"]["id"] === turn
        end,
        deadline(15_000)
      )

    assert complete["turn"]["status"] === "completed"

    # The real paginated includeTurns path persists/projects before returning.
    # Do not poll the search until an expected row happens to appear.
    saved =
      call(ctx, warm.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]

    assert saved["id"] === thread
    assert [history] = Map.fetch!(saved, "turns")
    assert history["id"] === turn and history["status"] === "completed"
    items = Map.fetch!(history, "items")
    assert length(items) === 2
    assert [user] = Enum.filter(items, &(&1["type"] === "userMessage"))
    assert [assistant] = Enum.filter(items, &(&1["type"] === "agentMessage"))

    assert Enum.map(user["content"], &Map.take(&1, ~w(type text))) === [
             %{"type" => "text", "text" => @text}
           ]

    assert assistant["text"] === @answer
    user_id = Map.fetch!(user, "id")
    assert is_binary(user_id) and byte_size(user_id) in 1..256
    assert_user_notification(ctx, thread, turn, user_id)
    path = Map.fetch!(saved, "path")
    assert is_binary(path) and Path.type(path) === :absolute
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    rollout = snapshot(path)
    assert String.contains?(rollout.bytes, @text) and String.contains?(rollout.bytes, @answer)
    assert_one_model_request(ctx)
    provider = snapshot(ctx.fixture.requests)
    params = %{"threadId" => thread, "searchTerm" => "needle", "limit" => 1}

    first = search(ctx, warm.pid, -1379, params)
    first_item = assert_page(first, 0, turn, user_id, :next)
    cursor_one = Map.fetch!(first, "nextCursor")
    second_params = Map.put(params, "cursor", cursor_one)
    second = search(ctx, warm.pid, "-1379", second_params)
    second_item = assert_page(second, 1, turn, user_id, :next)
    cursor_two = Map.fetch!(second, "nextCursor")
    refute cursor_two === cursor_one
    third_params = Map.put(params, "cursor", cursor_two)
    third = search(ctx, warm.pid, "owned-search-final-1379", third_params)
    third_item = assert_page(third, 2, turn, user_id, :last)
    assert Enum.map([first_item, second_item, third_item], & &1["snippetMatchRange"]) === @ranges

    assert Enum.uniq(Enum.map([first_item, second_item, third_item], & &1["turnCursor"])) === [
             first_item["turnCursor"]
           ]

    anchor =
      call(ctx, warm.pid, "thread/turns/list", %{
        "threadId" => thread,
        "cursor" => first_item["turnCursor"],
        "limit" => 1,
        "sortDirection" => "asc",
        "itemsView" => "full"
      })

    assert [%{"id" => ^turn, "items" => anchored}] = Map.fetch!(anchor, "data")
    assert Enum.any?(anchored, &(&1["id"] === user_id and &1["type"] === "userMessage"))

    assert call(ctx, warm.pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert snapshot(ctx.fixture.requests) === provider
    assert_controls(ctx)
    assert_idle(warm.pid)
    close_native(warm)
    persisted = snapshot(path)
    assert String.contains?(persisted.bytes, @text) and String.contains?(persisted.bytes, @answer)

    # The cold reader searches persisted history before any read/resume/turn can
    # prime it, reusing the opaque native cursors without decoding or rewriting.
    cold = start(ctx)
    refute cold.native === warm.native
    assert_empty_loaded(ctx, cold.pid)
    cold_second = search(ctx, cold.pid, "owned-search-cold-second-1379", second_params)
    assert cold_second === second
    assert_page(cold_second, 1, turn, user_id, :next)
    cold_third = search(ctx, cold.pid, "owned-search-cold-third-1379", third_params)
    assert cold_third === third
    assert_page(cold_third, 2, turn, user_id, :last)
    assert_empty_loaded(ctx, cold.pid)
    assert snapshot(path) === persisted
    assert snapshot(ctx.fixture.requests) === provider
    assert_one_model_request(ctx)
    assert_controls(ctx)
    assert_idle(cold.pid)
    close_native(cold)
    assert snapshot(path) === persisted
    assert_inventory(ctx)
    close_provider(ctx)
    assert snapshot(path) === persisted
    assert snapshot(ctx.fixture.requests) === provider
    assert_one_model_request(ctx)
    assert_controls(ctx)
  end

  defp assert_page(page, index, turn, user, continuation) do
    assert Enum.sort(Map.keys(page)) === ~w(data nextCursor)
    assert [item] = Map.fetch!(page, "data")
    cursor = Map.fetch!(item, "turnCursor")
    assert is_binary(cursor) and byte_size(cursor) in 1..4096

    assert item === %{
             "turnId" => turn,
             "itemId" => user,
             "snippet" => @text,
             "snippetMatchRange" => Enum.at(@ranges, index),
             "turnCursor" => cursor
           }

    if continuation === :next do
      next = Map.fetch!(page, "nextCursor")
      assert is_binary(next) and byte_size(next) in 1..4096
    else
      assert Map.fetch!(page, "nextCursor") === nil
    end

    item
  end

  defp search(ctx, pid, id, params) do
    wire = %{"id" => id, "method" => @method, "params" => params}
    assert :ok = Schema.validate(schema("v2/ThreadSearchOccurrencesParams.json"), params)
    result = call(ctx, pid, wire)

    assert :ok =
             Schema.validate(schema("v2/ThreadSearchOccurrencesResponse.json"), result,
               max_depth: 64
             )

    assert_target_owner(ctx, wire)
    result
  end

  defp assert_target_owner(ctx, wire) do
    assert [sent] = Enum.filter(outgoing(ctx), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and byte_size(sent.encoded) <= 4096
    document = schema("ClientRequest.json")
    variants = Map.fetch!(document, "oneOf")

    assert [selected] =
             Enum.filter(
               variants,
               &(get_in(&1, ["properties", "method", "enum"]) === [@method])
             )

    assert selected === Enum.at(variants, 58)
    node = selected |> Map.fetch!("properties") |> Map.fetch!("id")
    assert JSON.decode!(@id_node_bytes) === node
    assert node === %{"$ref" => "#/definitions/RequestId"}
    assert hash(@id_node_bytes) === @id_node_sha
    definitions = Map.fetch!(document, "definitions")

    assert Map.fetch!(definitions, "RequestId") === %{
             "anyOf" => [
               %{"type" => "string"},
               %{"format" => "int64", "type" => "integer"}
             ]
           }

    assert :ok =
             Schema.validate(
               Map.put(node, "definitions", definitions),
               Map.fetch!(sent.wire, "id")
             )

    assert :ok =
             Schema.validate(Map.put(selected, "definitions", definitions), sent.wire,
               max_depth: 64
             )

    assert :ok = Schema.validate(document, sent.wire, max_depth: 64)
    assert [received] = Enum.filter(incoming(ctx), &(&1.wire["id"] === wire["id"]))
    assert Enum.sort(Map.keys(received.wire)) === ~w(id result)
    assert received.wire["id"] === wire["id"]
  end

  defp start(ctx) do
    args = [
      "-c",
      ~s(approval_policy="never"),
      "-c",
      ~s(sandbox_mode="danger-full-access"),
      "-c",
      "features.plugins=false",
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
    info = %{"name" => "owned_ordinary_search_occurrences", "version" => "1"}
    caps = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => caps}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, caps, id: id, timeout_ms: 5_000)

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
    assert [sent] = Enum.filter(outgoing(ctx), &(&1.wire["id"] === wire["id"]))
    assert [received] = Enum.filter(incoming(ctx), &(&1.wire["id"] === wire["id"]))
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert {:ok, decoded} = Wire.decode(sent.encoded, max_depth: 64)
    assert decoded === wire
    assert {:ok, decoded} = Wire.decode(received.encoded, max_depth: 64)
    assert decoded === response
    assert Enum.sort(Map.keys(response)) === ~w(id result)
    assert response["id"] === wire["id"]
    assert :ok = Schema.validate_request(wire["method"], wire["params"], experimental: true)
    assert :ok = Schema.validate_result(:server_response, wire["method"], response["result"])
  end

  defp assert_user_notification(ctx, thread, turn, user) do
    assert [frame] =
             Enum.filter(incoming(ctx), fn frame ->
               frame.wire["method"] === "item/completed" and
                 frame.wire["params"]["threadId"] === thread and
                 frame.wire["params"]["turnId"] === turn and
                 frame.wire["params"]["item"]["type"] === "userMessage"
             end)

    assert frame.wire["params"]["item"]["id"] === user
  end

  defp assert_inventory(ctx) do
    assert Enum.map(outgoing(ctx), & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/start turn/start thread/read thread/searchOccurrences thread/searchOccurrences thread/searchOccurrences thread/turns/list thread/loaded/list initialize initialized server/diagnostics thread/loaded/list thread/searchOccurrences thread/searchOccurrences thread/loaded/list)

    targets = Enum.filter(outgoing(ctx), &(&1.wire["method"] === @method))

    assert Enum.map(targets, & &1.wire["id"]) === [
             -1379,
             "-1379",
             "owned-search-final-1379",
             "owned-search-cold-second-1379",
             "owned-search-cold-third-1379"
           ]

    requests = Enum.filter(outgoing(ctx), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === 17 and length(Enum.uniq(ids)) === 17
    responses = Enum.filter(incoming(ctx), &Map.has_key?(&1.wire, "id"))
    assert length(responses) === 17
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    for frame <- Enum.reject(incoming(ctx), &Map.has_key?(&1.wire, "id")) do
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
      assert is_integer(frame.wire["emittedAtMs"]) and frame.wire["emittedAtMs"] > 0
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire
      assert :ok = Schema.validate(schema("ServerNotification.json"), frame.wire, max_depth: 64)

      assert :ok =
               Schema.validate_notification(
                 :server_notification,
                 frame.wire["method"],
                 frame.wire["params"],
                 experimental: true
               )
    end
  end

  defp await_notification(pid, method, predicate, until) do
    assert System.monotonic_time(:millisecond) < until,
           "ordinary occurrence notification deadline"

    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128

    found =
      Enum.find_value(events, fn event ->
        if event.wire["method"] === method and predicate.(event.wire["params"]),
          do: event.wire["params"]
      end)

    if found do
      found
    else
      assert %{phase: :ready, gap: nil} = Session.status(pid)
      remaining = min(max(until - System.monotonic_time(:millisecond), 0), 20)

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("ordinary occurrence event gap")
      after
        remaining -> :ok
      end

      await_notification(pid, method, predicate, until)
    end
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_one_model_request(ctx) do
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert request["model"] === "mock-model"

    assert Enum.any?(request["input"], fn item ->
             item["role"] === "user" and
               Enum.any?(Map.get(item, "content", []), &(&1["text"] === @text))
           end)
  end

  defp assert_controls(ctx) do
    for {path, before} <- ctx.inputs, do: assert(snapshot(path) === before)
    assert File.ls!(ctx.fixture.workspace) === []
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 128)
    assert length(events) <= 128
    assert {:ok, []} = Session.drain(pid, 128)
  end

  defp close_native(native) do
    monitor = Process.monitor(native.connection.owner.pid)
    assert :ok = Session.close(native.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(native.connection.owner.completion, 1) === 1
    assert Port.info(native.connection.port) === nil
    refute File.exists?("/proc/#{native.native}")
  end

  defp close_provider(ctx) do
    monitor = Process.monitor(ctx.fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(ctx.fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(ctx.fixture.transport.owner.completion, 1) === 1
    assert Port.info(ctx.fixture.port) === nil
    for pid <- ctx.fixture_pids, do: refute(File.exists?("/proc/#{pid}"))
  end

  defp owned_process_tree(port) do
    assert {:os_pid, pid} = Port.info(port, :os_pid)
    assert is_integer(pid) and pid > 0
    owned_descendants([pid], [])
  end

  defp owned_descendants([], found), do: found

  defp owned_descendants([pid | remaining], found) do
    assert length(found) < 16, "owned helper process bound"

    children =
      File.read!("/proc/#{pid}/task/#{pid}/children")
      |> String.split()
      |> Enum.map(&String.to_integer/1)

    assert Enum.all?(children, &(&1 > 0))
    owned_descendants(remaining ++ children, [pid | found])
  end

  defp outgoing(ctx), do: frames(ctx, :out)
  defp incoming(ctx), do: frames(ctx, :in)

  defp frames(ctx, direction),
    do:
      Agent.get(
        ctx.capture,
        &Enum.filter(&1.frames, fn frame -> frame.direction === direction end)
      )

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp schema(name), do: schema_path(name) |> File.read!() |> JSON.decode!()

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-occurrence-id-#{System.unique_integer([:positive, :monotonic])}"
  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
