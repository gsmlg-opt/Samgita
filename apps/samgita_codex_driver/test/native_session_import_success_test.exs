defmodule SamgitaCodexDriver.NativeSessionImportSuccessTest do
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

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @prompt "Owned imported history λ"
  @answer "Owned foreign transcript answer"
  @marker "<EXTERNAL SESSION IMPORTED>"
  @turn "external-import-turn-1"
  @attribution "owned-native-session-import"
  @max_file_bytes 4_194_304
  @max_line_bytes 262_144

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
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 256 and size <= 262_144 and ledger.bytes + size <= 4_194_304 do
          entry = %{direction: direction, encoded: encoded, wire: JSON.decode!(encoded)}

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
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    binary = Path.expand(binary)
    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-session-import-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
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

    File.write!(fixture.requests, "[]")
    on_exit(fn -> close_provider(fixture) end)
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: binary, fixture: fixture, root: root, capture: capture}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    source = Path.join(fixture.home, ".claude/projects/owned-import/session.jsonl")
    File.mkdir_p!(Path.dirname(source))
    first_time = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-30, :second)
    last_time = DateTime.add(first_time, 10, :second)

    source_records = [
      foreign_record("user", fixture.workspace, first_time, @prompt),
      foreign_record("assistant", fixture.workspace, last_time, @answer)
    ]

    source_bytes = Enum.map_join(source_records, "", &(JSON.encode!(&1) <> "\n"))
    File.write!(source, source_bytes, [:exclusive])

    inputs = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.merge(ctx, %{
      source: source,
      source_records: source_records,
      source_bytes: source_bytes,
      created: DateTime.to_unix(first_time),
      updated: DateTime.to_unix(last_time),
      inputs: Map.new(inputs, &{&1, bounded_file(&1)})
    })
  end

  test "actual foreign-session import persists legacy history and deduplicates completed source versions across cold reads",
       ctx do
    assert_retained(ctx)
    warm = start(ctx)
    warm_native = native_id(ctx, warm.pid)
    assert_unloaded(ctx, warm.pid)

    detected =
      call(ctx, warm.pid, "externalAgentConfig/detect", %{
        "includeHome" => true,
        "migrationSource" => "claude-code",
        "maxSessionAgeDays" => 1,
        "maxSessions" => 4
      })

    assert Map.fetch!(detected, "connectors") === []
    assert [selected] = Map.fetch!(detected, "items")
    assert_selected(ctx, selected)
    first = import_source(ctx, warm.pid, selected, true)
    expected_success = success(ctx, first.target)
    assert first.completed === completed(first.id, [expected_success])
    assert first.progress === [type_result([]), type_result([expected_success])]
    assert_history(ctx, warm.pid, first.id, [expected_success])
    stored = assert_native_history(ctx, warm.pid, first.target)
    assert_canonical(ctx, stored.path, first.target)
    assert_unloaded(ctx, warm.pid)
    assert_retained(ctx, stored)

    # This second operation starts only after actual native completion and
    # durable history have been observed. It is not ambiguous-disconnect retry.
    second = import_source(ctx, warm.pid, selected, false)
    refute second.id == first.id
    assert second.completed === completed(second.id, [])
    assert second.progress === [type_result([]), type_result([])]
    assert_history(ctx, warm.pid, second.id, [])
    assert_history(ctx, warm.pid, first.id, [expected_success])
    assert_native_history(ctx, warm.pid, first.target, stored)
    assert_unloaded(ctx, warm.pid)
    assert_idle(ctx, warm.pid)
    assert_retained(ctx, stored)
    close(warm, warm_native)
    assert_retained(ctx, stored)

    cold = start(ctx)
    cold_native = native_id(ctx, cold.pid)
    refute cold_native == warm_native
    assert_unloaded(ctx, cold.pid)

    # No resume, turn start or handcrafted native history precedes these reads.
    assert_native_history(ctx, cold.pid, first.target, stored)
    assert_history(ctx, cold.pid, first.id, [expected_success])
    assert_history(ctx, cold.pid, second.id, [])
    assert_unloaded(ctx, cold.pid)
    assert_idle(ctx, cold.pid)
    assert_retained(ctx, stored)
    close(cold, cold_native)
    assert_retained(ctx, stored)
    assert_wire_inventory(ctx)
    assert hash(File.read!(ctx.binary)) === @binary_sha
  end

  defp foreign_record(role, cwd, time, text) do
    %{
      "type" => role,
      "cwd" => cwd,
      "timestamp" => DateTime.to_iso8601(time),
      "message" => %{"content" => text}
    }
  end

  defp assert_selected(ctx, selected) do
    assert Map.fetch!(selected, "itemType") === "SESSIONS"
    assert Map.fetch!(selected, "cwd") === nil

    assert Map.fetch!(selected, "description") ===
             "Migrate recent sessions from #{Path.join(ctx.fixture.home, ".claude/projects")}"

    details = Map.fetch!(selected, "details")

    assert Map.fetch!(details, "sessions") === [
             %{"path" => ctx.source, "cwd" => ctx.fixture.workspace, "title" => @prompt}
           ]

    for key <- ~w(commands hooks mcpServers plugins skills subagents),
        do: assert(Map.fetch!(details, key) === [])

    refute Map.has_key?(details, "memory")
  end

  defp import_source(ctx, pid, selected, expect_target) do
    params = %{
      "migrationSource" => "claude-code",
      "providerId" => @attribution,
      "migrationItems" => [selected]
    }

    {request_id, receipt} = request(ctx, pid, "externalAgentConfig/import", params)
    assert %{"importId" => id} = receipt
    assert Map.keys(receipt) === ["importId"]
    assert_uuid(id)
    events = await_completion(pid, id, [], now() + 10_000)
    notifications = Enum.map(events, & &1.wire)

    relevant =
      Enum.filter(notifications, fn wire ->
        wire["method"] in [
          "externalAgentConfig/import/progress",
          "externalAgentConfig/import/completed"
        ] and wire["params"]["importId"] == id
      end)

    assert Enum.map(relevant, & &1["method"]) === [
             "externalAgentConfig/import/progress",
             "externalAgentConfig/import/progress",
             "externalAgentConfig/import/completed"
           ]

    [validation, imported, completion] = relevant
    assert [validation_result] = validation["params"]["itemTypeResults"]
    assert [import_result] = imported["params"]["itemTypeResults"]
    assert validation_result === type_result([])
    assert Map.fetch!(import_result, "failures") === []
    assert Map.fetch!(import_result, "itemType") === "SESSIONS"
    target = import_target(import_result, expect_target)
    assert_receipt_before_processing(ctx, request_id, id)

    %{
      id: id,
      target: target,
      progress: [validation_result, import_result],
      completed: completion["params"]
    }
  end

  defp import_target(result, true) do
    assert [success] = Map.fetch!(result, "successes")
    target = Map.fetch!(success, "target")
    assert is_binary(target) and target != ""
    target
  end

  defp import_target(result, false) do
    assert Map.fetch!(result, "successes") === []
    nil
  end

  defp await_completion(pid, id, events, deadline) do
    assert {:ok, batch} = Session.drain(pid, 256)
    events = events ++ batch
    assert length(events) <= 256
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= @max_file_bytes
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(events, &completion_event?(&1, id)) do
      events
    else
      await_import_notice(pid, id, events, deadline)
    end
  end

  defp completion_event?(event, id) do
    event.wire["method"] == "externalAgentConfig/import/completed" and
      event.wire["params"]["importId"] == id
  end

  defp await_import_notice(pid, id, events, deadline) do
    remaining = max(deadline - now(), 0)
    assert remaining > 0, "Native import completion deadline for #{id}"

    receive do
      {:codex_driver, ^pid, :events_available} -> await_completion(pid, id, events, deadline)
      {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected native import event gap")
    after
      remaining -> flunk("Native import completion deadline for #{id}")
    end
  end

  defp assert_receipt_before_processing(ctx, request_id, id) do
    indexed = capture(ctx) |> Enum.with_index()

    assert [{_receipt, receipt_index}] =
             Enum.filter(indexed, fn {entry, _index} ->
               entry.direction == :in and entry.wire["id"] == request_id
             end)

    notices =
      Enum.filter(indexed, fn {entry, _index} ->
        entry.direction == :in and
          entry.wire["method"] in [
            "externalAgentConfig/import/progress",
            "externalAgentConfig/import/completed"
          ] and entry.wire["params"]["importId"] == id
      end)

    assert length(notices) == 3
    for {_entry, index} <- notices, do: assert(index > receipt_index)
  end

  defp success(ctx, target) do
    %{
      "itemType" => "SESSIONS",
      "cwd" => ctx.fixture.workspace,
      "source" => ctx.source,
      "target" => target,
      "title" => @prompt
    }
  end

  defp type_result(successes),
    do: %{"itemType" => "SESSIONS", "successes" => successes, "failures" => []}

  defp completed(id, successes),
    do: %{"importId" => id, "itemTypeResults" => [type_result(successes)]}

  defp assert_history(ctx, pid, id, expected_successes) do
    result = call(ctx, pid, "externalAgentConfig/import/readHistories", nil)
    assert Map.fetch!(result, "connectors") === []
    data = Map.fetch!(result, "data")
    assert length(data) in [1, 2]
    assert [record] = Enum.filter(data, &(&1["importId"] == id))
    assert Map.fetch!(record, "providerId") === @attribution
    assert Map.fetch!(record, "successes") === expected_successes
    assert Map.fetch!(record, "failures") === []
    assert is_integer(record["completedAtMs"]) and record["completedAtMs"] > 0

    assert Map.keys(record) |> Enum.sort() ===
             Enum.sort(~w(importId providerId completedAtMs successes failures))

    record
  end

  defp assert_native_history(ctx, pid, id, previous \\ nil) do
    result = call(ctx, pid, "thread/list", %{"limit" => 100, "useStateDbOnly" => true})
    assert Map.fetch!(result, "nextCursor") === nil
    assert [listed] = Map.fetch!(result, "data")

    expected = %{
      "id" => id,
      "sessionId" => id,
      "source" => "vscode",
      "cwd" => ctx.fixture.workspace,
      "modelProvider" => "fixture",
      # The importer patches metadata.title, without writing the separate
      # legacy name index. Its import history title is asserted independently.
      "name" => nil,
      "preview" => @prompt,
      "historyMode" => "legacy",
      "createdAt" => ctx.created,
      "updatedAt" => ctx.updated,
      "recencyAt" => ctx.updated,
      "cliVersion" => "0.163.0",
      "turns" => []
    }

    assert Map.take(listed, Map.keys(expected)) === expected
    path = Map.fetch!(listed, "path")
    assert is_binary(path) and String.starts_with?(path, ctx.fixture.codex_home <> "/")
    bytes = bounded_file(path)
    assert_canonical(ctx, path, id)
    read = call(ctx, pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

    # Legacy read can obtain metadata through a different native path than
    # SQLite listing. The independent complete turn oracle remains unchanged.
    assert Map.take(read, ~w(id source cwd modelProvider path historyMode cliVersion)) === %{
             "id" => id,
             "source" => "vscode",
             "cwd" => ctx.fixture.workspace,
             "modelProvider" => "fixture",
             "path" => path,
             "historyMode" => "legacy",
             "cliVersion" => "0.163.0"
           }

    assert Map.fetch!(read, "turns") === [expected_turn(ctx)]
    assert bounded_file(path) === bytes
    assert only_rollout(ctx) === path
    stored = %{path: path, bytes: bytes, listed: listed, read: read}

    if previous do
      assert stored.path === previous.path
      assert stored.bytes === previous.bytes
      assert stored.listed === previous.listed
      assert stored.read === previous.read
    end

    stored
  end

  defp expected_turn(ctx) do
    %{
      "id" => @turn,
      "rootTurnId" => nil,
      "status" => "completed",
      "error" => nil,
      "itemsView" => "full",
      "startedAt" => ctx.created,
      "completedAt" => ctx.updated,
      "durationMs" => nil,
      "items" => [
        %{
          "type" => "userMessage",
          "id" => "item-1",
          "clientId" => nil,
          "content" => [%{"type" => "text", "text" => @prompt, "text_elements" => []}]
        },
        agent_item("item-2", @answer),
        agent_item("item-3", @marker)
      ]
    }
  end

  defp agent_item(id, text) do
    %{
      "type" => "agentMessage",
      "id" => id,
      "text" => text,
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }
  end

  defp assert_canonical(ctx, path, id) do
    records = path |> bounded_file() |> jsonl()
    assert [%{"type" => "session_meta", "payload" => meta} | _] = records

    assert Map.take(meta, ~w(id session_id cwd source model_provider cli_version history_mode)) ===
             %{
               "id" => id,
               "session_id" => id,
               "cwd" => ctx.fixture.workspace,
               "source" => "vscode",
               "model_provider" => "fixture",
               "cli_version" => "0.163.0",
               "history_mode" => "legacy"
             }

    messages = for %{"type" => "response_item", "payload" => payload} <- records, do: payload

    assert messages === [
             %{
               "type" => "message",
               "role" => "user",
               "content" => [%{"type" => "input_text", "text" => @prompt}]
             },
             %{
               "type" => "message",
               "role" => "assistant",
               "content" => [%{"type" => "output_text", "text" => @answer}]
             }
           ]

    events = for %{"type" => "event_msg", "payload" => event} <- records, do: event

    assert [%{"turn_id" => @turn, "started_at" => started}] = of_type(events, "task_started")
    assert started === ctx.created
    assert [%{"message" => @prompt}] = of_type(events, "user_message")

    assert Enum.map(of_type(events, "agent_message"), &Map.fetch!(&1, "message")) === [
             @answer,
             @marker
           ]

    assert of_type(events, "task_complete") === [
             %{
               "type" => "task_complete",
               "turn_id" => @turn,
               "last_agent_message" => nil,
               "started_at" => ctx.created,
               "completed_at" => ctx.updated
             }
           ]

    assert of_type(events, "error") === []
    assert of_type(events, "turn_aborted") === []
    assert length(of_type(events, "token_count")) == 1
  end

  defp of_type(records, type), do: Enum.filter(records, &(&1["type"] == type))

  defp only_rollout(ctx) do
    assert [path] =
             Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl"))

    path
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
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
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    },
                    max_message_bytes: @max_line_bytes
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_native_session_import", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    %{pid: pid, connection: connection}
  end

  defp call(ctx, pid, method, params), do: elem(request(ctx, pid, method, params), 1)

  defp request(ctx, pid, method, params) do
    id = "owned-native-session-import-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [sent, received] = Enum.filter(capture(ctx), &(&1.wire["id"] == id))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and received.wire === response
    assert JSON.decode!(sent.encoded) === wire
    assert JSON.decode!(received.encoded) === response
    {id, result}
  end

  defp capture(ctx), do: Agent.get(ctx.capture, &Enum.reverse(&1.records))

  defp assert_wire_inventory(ctx) do
    records = capture(ctx)
    outgoing = for %{direction: :out, wire: wire} <- records, do: wire

    allowed =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/list thread/read externalAgentConfig/detect externalAgentConfig/import externalAgentConfig/import/readHistories)

    assert Enum.all?(outgoing, &(&1["method"] in allowed))
    assert Enum.count(outgoing, &(&1["method"] == "externalAgentConfig/detect")) == 1
    assert Enum.count(outgoing, &(&1["method"] == "externalAgentConfig/import")) == 2
    for record <- records, do: assert(JSON.decode!(record.encoded) === record.wire)
  end

  defp native_id(ctx, pid) do
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    native
  end

  defp close(session, native) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{native}")
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(fixture.transport.owner.completion, 1) == 1
    assert Port.info(fixture.port) == nil
  end

  defp assert_unloaded(ctx, pid),
    do: assert(call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil})

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.all?(events, &(&1.wire["method"] != "error"))
    assert requests(ctx) === []
  end

  defp assert_retained(ctx, stored \\ nil) do
    assert bounded_file(ctx.source) === ctx.source_bytes
    assert jsonl(ctx.source_bytes) === ctx.source_records
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    assert requests(ctx) === []
    assert File.ls!(ctx.fixture.workspace) === []
    if stored, do: assert(bounded_file(stored.path) === stored.bytes)
  end

  defp requests(ctx) do
    result = ctx.fixture.requests |> bounded_file() |> JSON.decode!()
    assert is_list(result) and length(result) <= 1
    result
  end

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) === size
    bytes
  end

  defp jsonl(bytes) do
    lines = String.split(bytes, "\n", trim: true)
    assert length(lines) <= 1024

    Enum.map(lines, fn line ->
      assert byte_size(line) <= @max_line_bytes
      JSON.decode!(line)
    end)
  end

  defp assert_uuid(value) do
    assert is_binary(value) and
             value =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp now, do: System.monotonic_time(:millisecond)
end
