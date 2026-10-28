defmodule SamgitaCodexDriver.NativeOrdinaryLifecycleRequestIdsTest do
  @moduledoc """
  Two physical native request-id owners only. Memory rows/summary are synthetic
  reader inputs, not extraction, consolidation, writer or production evidence.
  """
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Error, Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @model_script Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @model_script_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @memory_input Path.expand("../../../scripts/codex/memory_status_input_fixture.py", __DIR__)
  @memory_input_sha "1e249e2d277849077224d93549238cd63433894fb6af9819d4335589878460a9"
  @root_sha "92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352"
  @id_node_bytes """
  {
    "$ref": "#/definitions/RequestId"
  }
  """
  @id_node_sha "f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7"
  @marker "Owned ordinary persisted deletion marker 806"
  @answer "Deterministic local fixture answer"
  @summary """
  v1
  ## User Profile
  Owned synthetic memory status reader 1249.
  ## User preferences
  Owned synthetic preference.
  ## General Tips
  Owned synthetic tip.
  ## What's in Memory
  Owned synthetic reader input only.
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
    assert hash(File.read!(@model_script)) === @model_script_sha
    assert hash(File.read!(@memory_input)) === @memory_input_sha
    assert hash(File.read!(schema_path("ClientRequest.json"))) === @root_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "owned-lifecycle-request-ids-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @model_script)

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
            "display_name" => "Owned ordinary lifecycle input",
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
    paths = [@model_script, @memory_input, catalog, config, schema_path("ClientRequest.json")]

    %{
      binary: binary,
      root: root,
      fixture: fixture,
      fixture_pids: fixture_pids,
      capture: capture,
      inputs: Map.new(paths, &{&1, snapshot(&1)})
    }
  end

  test "ordinary native thread delete preserves its exact integer request id and removes real persisted history",
       ctx do
    native = start(ctx)
    assert ModelFixture.requests(ctx.fixture) === []
    assert list(ctx, native.pid) === []

    started =
      call(ctx, native.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "legacy",
        "ephemeral" => false,
        "approvalPolicy" => "never",
        "sandbox" => "danger-full-access"
      })

    thread = Map.fetch!(started["thread"], "id")
    assert is_binary(thread) and byte_size(thread) in 1..128

    turn =
      call(ctx, native.pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @marker}]
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) in 1..128

    completed =
      await_notification(
        native.pid,
        "turn/completed",
        fn params ->
          params["threadId"] === thread and params["turn"]["id"] === turn
        end,
        deadline(15_000)
      )

    assert completed["turn"]["status"] === "completed"

    saved =
      call(ctx, native.pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})[
        "thread"
      ]

    assert saved["id"] === thread
    assert [history] = Map.fetch!(saved, "turns")
    assert history["id"] === turn and history["status"] === "completed"
    items = Map.fetch!(history, "items")

    assert Enum.any?(items, fn item ->
             item["type"] === "userMessage" and
               Enum.any?(
                 Map.get(item, "content", []),
                 &(&1["type"] === "text" and &1["text"] === @marker)
               )
           end)

    assert Enum.any?(items, &(&1["type"] === "agentMessage" and &1["text"] === @answer))
    path = Map.fetch!(saved, "path")
    assert is_binary(path) and Path.type(path) === :absolute
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    rollout = snapshot(path)
    assert String.contains?(rollout.bytes, @marker) and String.contains?(rollout.bytes, @answer)
    assert Enum.map(list(ctx, native.pid), & &1["id"]) === [thread]
    assert_one_model_request(ctx)
    before = snapshot(ctx.fixture.requests)

    # Exactly one state-changing delete. No disconnect/timeout retry is made.
    assert call(ctx, native.pid, %{
             "id" => -806,
             "method" => "thread/delete",
             "params" => %{"threadId" => thread}
           }) === %{}

    assert_target_owner(ctx, "thread/delete", -806, 11)

    assert await_notification(
             native.pid,
             "thread/deleted",
             &(&1["threadId"] === thread),
             deadline(5_000)
           ) === %{"threadId" => thread}

    refute File.exists?(path)
    assert list(ctx, native.pid) === []

    assert call(ctx, native.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert_absent_read(ctx, native.pid, thread)
    assert snapshot(ctx.fixture.requests) === before
    assert_one_model_request(ctx)
    assert_controls(ctx)
    assert_idle(native.pid)
    close_native(native)
    refute File.exists?(path)

    assert_inventory(
      ctx,
      ~w(initialize initialized server/diagnostics thread/list thread/start turn/start thread/read thread/list thread/delete thread/list thread/loaded/list thread/read)
    )

    assert [deleted] = notifications(ctx, "thread/deleted")
    assert deleted.wire["params"] === %{"threadId" => thread}
    close_provider(ctx)
    assert snapshot(ctx.fixture.requests) === before
    assert_controls(ctx)
  end

  test "ordinary native memory status preserves exact typed request ids over explicit synthetic persisted reader inputs",
       ctx do
    database = Path.join(ctx.fixture.codex_home, "memories_v2_1.sqlite")
    summary = Path.join(ctx.fixture.codex_home, "memories_v2/memory_summary.md")
    refute File.exists?(database)
    refute File.exists?(summary)
    initial = start(ctx)

    assert call(ctx, initial.pid, %{"id" => -1249, "method" => "memory/status", "params" => %{}}) ===
             %{"v2ConsolidatedThreads" => 0, "v2Ready" => false}

    assert_target_owner(ctx, "memory/status", -1249, 34)
    assert_empty_loaded(ctx, initial.pid)
    assert_controls(ctx)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_idle(initial.pid)
    close_native(initial)
    assert File.regular?(database)
    assert_input(ctx, "read", initial.native, 0, 0)
    assert_input(ctx, "seed-two", initial.native, 2, 1)
    assert_input(ctx, "read", initial.native, 2, 0)
    File.mkdir_p!(Path.dirname(summary))
    File.write!(summary, @summary, [:exclusive])
    saved_summary = snapshot(summary)

    # Native public reader, independently authored count/summary. No memory
    # generator, consolidation task, success record or provider inference ran.
    cold = start(ctx)
    refute cold.native === initial.native

    assert call(ctx, cold.pid, %{
             "id" => "-1249",
             "method" => "memory/status",
             "params" => %{"minConsolidatedThreads" => 2}
           }) ===
             %{"v2ConsolidatedThreads" => 2, "v2Ready" => true}

    assert_target_owner(ctx, "memory/status", "-1249", 34)

    assert call(ctx, cold.pid, %{
             "id" => "owned-memory-threshold-1249",
             "method" => "memory/status",
             "params" => %{"minConsolidatedThreads" => 3}
           }) ===
             %{"v2ConsolidatedThreads" => 2, "v2Ready" => false}

    assert_target_owner(ctx, "memory/status", "owned-memory-threshold-1249", 34)
    assert snapshot(summary) === saved_summary
    assert_empty_loaded(ctx, cold.pid)
    assert_controls(ctx)
    assert ModelFixture.requests(ctx.fixture) === []
    assert_idle(cold.pid)
    close_native(cold)
    assert_input(ctx, "read", cold.native, 2, 0)
    assert snapshot(summary) === saved_summary

    assert_inventory(
      ctx,
      ~w(initialize initialized server/diagnostics memory/status thread/loaded/list initialize initialized server/diagnostics memory/status memory/status thread/loaded/list)
    )

    targets = outgoing(ctx) |> Enum.filter(&(&1.wire["method"] === "memory/status"))
    assert Enum.map(targets, & &1.wire["id"]) === [-1249, "-1249", "owned-memory-threshold-1249"]
    close_provider(ctx)
    assert ModelFixture.requests(ctx.fixture) === []
    assert snapshot(summary) === saved_summary
    assert_controls(ctx)
  end

  defp assert_target_owner(ctx, method, id, index) do
    assert [sent] =
             Enum.filter(outgoing(ctx), &(&1.wire["method"] === method and &1.wire["id"] === id))

    assert byte_size(sent.encoded) <= 4096
    root = File.read!(schema_path("ClientRequest.json"))
    assert hash(root) === @root_sha
    document = JSON.decode!(root)
    variants = Map.fetch!(document, "oneOf")

    assert [selected] =
             Enum.filter(variants, &(get_in(&1, ["properties", "method", "enum"]) === [method]))

    assert selected === Enum.at(variants, index)
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
    assert sent.wire["id"] === id
    assert [received] = Enum.filter(incoming(ctx), &(&1.wire["id"] === id))
    assert Enum.sort(Map.keys(received.wire)) === ~w(id result)
    assert received.wire["id"] === id
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
    info = %{"name" => "owned_ordinary_lifecycle_request_ids", "version" => "1"}
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

    if wire["method"] in ["thread/delete", "memory/status"] do
      assert :ok = Schema.validate_result(:server_response, wire["method"], result)
    end

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
    assert response["id"] === wire["id"]
  end

  defp assert_absent_read(ctx, pid, thread) do
    id = request_id()

    wire = %{
      "id" => id,
      "method" => "thread/read",
      "params" => %{"threadId" => thread, "includeTurns" => true}
    }

    assert {:error,
            %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error} = response}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    assert Enum.sort(Map.keys(response)) === ~w(error id)
    assert error["code"] === -32_600
    assert error["message"] === "thread not loaded: #{thread}"
  end

  defp list(ctx, pid) do
    result =
      call(ctx, pid, "thread/list", %{
        "limit" => 10,
        "cwd" => ctx.fixture.workspace,
        "sourceKinds" => ["cli", "vscode", "exec", "appServer"]
      })

    assert result["nextCursor"] === nil
    Map.fetch!(result, "data")
  end

  defp assert_empty_loaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp await_notification(pid, method, predicate, until) do
    assert System.monotonic_time(:millisecond) < until, "ordinary lifecycle notification deadline"
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
        {:codex_driver, ^pid, {:gap, _}} -> flunk("ordinary lifecycle event gap")
      after
        remaining -> :ok
      end

      await_notification(pid, method, predicate, until)
    end
  end

  defp assert_inventory(ctx, expected) do
    assert Enum.map(outgoing(ctx), & &1.wire["method"]) === expected
    requests = Enum.filter(outgoing(ctx), &Map.has_key?(&1.wire, "id"))
    ids = Enum.map(requests, & &1.wire["id"])
    assert length(ids) === length(Enum.uniq(ids))
    responses = Enum.filter(incoming(ctx), &Map.has_key?(&1.wire, "id"))
    assert length(responses) === length(ids)
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)

    for frame <- Enum.reject(incoming(ctx), &Map.has_key?(&1.wire, "id")) do
      assert Enum.sort(Map.keys(frame.wire)) === ~w(emittedAtMs method params)
      assert is_integer(frame.wire["emittedAtMs"]) and frame.wire["emittedAtMs"] > 0
      assert {:ok, decoded} = Wire.decode(frame.encoded, max_depth: 64)
      assert decoded === frame.wire

      assert :ok =
               Schema.validate_notification(
                 :server_notification,
                 frame.wire["method"],
                 frame.wire["params"],
                 experimental: true
               )
    end
  end

  defp assert_one_model_request(ctx) do
    assert [request] = ModelFixture.requests(ctx.fixture)
    assert request["model"] === "mock-model"

    assert Enum.any?(request["input"], fn item ->
             item["role"] === "user" and
               Enum.any?(Map.get(item, "content", []), &(&1["text"] === @marker))
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

  defp assert_input(ctx, operation, stopped_native, count, updated) do
    refute File.exists?("/proc/#{stopped_native}")
    python = System.find_executable("python3") || flunk("BLOCKED_ENV: Python 3 required")

    assert {:ok, connection} =
             Stdio.open(
               executable: python,
               cwd: ctx.fixture.workspace,
               inherit_env: [],
               env: %{
                 "HOME" => ctx.fixture.home,
                 "CODEX_HOME" => ctx.fixture.codex_home,
                 "TMPDIR" => ctx.root
               },
               args: [
                 "-B",
                 @memory_input,
                 operation,
                 "--codex-home",
                 ctx.fixture.codex_home,
                 "--stopped-native-pid",
                 to_string(stopped_native)
               ]
             )

    try do
      assert read_input_output(connection.port, <<>>, deadline(5_000)) ===
               %{"singleton" => 1, "max_thread_count" => count, "updated_rows" => updated}
    after
      assert :ok = Stdio.close(connection)
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
    end
  end

  defp read_input_output(port, bytes, until) do
    remaining = max(until - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        bytes = bytes <> data
        assert byte_size(bytes) <= 4096
        assert System.monotonic_time(:millisecond) < until, "ordinary memory input deadline"
        read_input_output(port, bytes, until)

      {^port, {:exit_status, 0}} ->
        assert System.monotonic_time(:millisecond) < until, "ordinary memory input deadline"
        JSON.decode!(String.trim(bytes))

      {^port, {:exit_status, code}} ->
        flunk("Owned memory input helper exited #{code}")
    after
      remaining -> flunk("ordinary memory input deadline")
    end
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
    path = "/proc/#{pid}/task/#{pid}/children"
    children = File.read!(path) |> String.split() |> Enum.map(&String.to_integer/1)
    assert Enum.all?(children, &(&1 > 0))
    owned_descendants(remaining ++ children, [pid | found])
  end

  defp notifications(ctx, method), do: Enum.filter(incoming(ctx), &(&1.wire["method"] === method))
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

  defp schema_path(name),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> name)

  defp request_id, do: "owned-lifecycle-id-#{System.unique_integer([:positive, :monotonic])}"
  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
