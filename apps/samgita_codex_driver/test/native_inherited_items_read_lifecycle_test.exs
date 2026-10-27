defmodule SamgitaCodexDriver.NativeInheritedItemsReadLifecycleTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 100_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @instructions "Owned inherited item selection fixture instructions."
  @answer "Deterministic local fixture answer"
  @markers [
    "Owned inherited P1 λ",
    "Owned inherited P2 🙂",
    "Owned inherited P3 retained",
    "Owned inherited P4 excluded",
    "Owned inherited child C1",
    "Owned inherited parent P5"
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
      wire = JSON.decode!(encoded)
      Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire))
    end

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      count_limit = if direction == :out, do: 128, else: 768
      message_limit = if direction == :out, do: 4096, else: 131_072
      size = byte_size(encoded)

      if length(entries) < count_limit and size <= message_limit and
           ledger.bytes + size <= 4_194_304 do
        entry = %{encoded: encoded, wire: wire}

        next =
          ledger |> Map.put(direction, entries ++ [entry]) |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
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

    assert hash(File.read!(binary)) == @binary_sha
    assert hash(File.read!(@provider)) == @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-inherited-items-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
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

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    ctx = %{binary: binary, root: root, fixture: fixture}

    # Only the model catalog writer is shared. The mixed thread/finish helpers
    # are deliberately not used; all native calls below belong to this profile.
    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(fixture.codex_home, "turn-models.json"),
          @provider,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})
    Map.merge(ctx, %{inputs: inputs, capture: capture})
  end

  test "native inherited selective items retain fork cutoff across parent revert and first cold recovery",
       ctx do
    warm = start(ctx)

    parent_thread =
      call(ctx, warm.pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]

    parent = Map.fetch!(parent_thread, "id")
    assert_identity(parent)

    [first, second, third, fourth] =
      original =
      for index <- 1..4, do: complete(ctx, warm.pid, parent, index)

    parent_saved = history(ctx, warm.pid, parent, original)
    assert_no_work(ctx, warm.pid, 4)

    child_thread =
      call(ctx, warm.pid, "thread/fork", %{
        "threadId" => parent,
        "beforeTurnId" => fourth.id,
        "excludeTurns" => true,
        "ephemeral" => false
      })["thread"]

    child = Map.fetch!(child_thread, "id")
    assert_identity(child)
    refute child == parent
    assert child_thread["forkedFromId"] === parent
    assert child_thread["historyMode"] === "paginated"
    assert child_thread["turns"] === []
    assert child_thread["ephemeral"] === false
    child_path = Map.fetch!(child_thread, "path")
    assert_owned_path(ctx, child_path)

    # Select the actual ancestor entries through the child's lineage. IDs are
    # reversed and repeated, but output must keep original durable item order.
    for row <- [first, second, third], do: selection(ctx, warm.pid, child, row)
    absent(ctx, warm.pid, child, fourth)
    assert_no_work(ctx, warm.pid, 4)

    child_own = complete(ctx, warm.pid, child, 5)
    parent_own = complete(ctx, warm.pid, parent, 6)
    child_expected = [first, second, third, child_own]
    parent_before_revert = original ++ [parent_own]
    child_saved = history(ctx, warm.pid, child, child_expected)
    history(ctx, warm.pid, parent, parent_before_revert)
    selection(ctx, warm.pid, child, third)
    selection(ctx, warm.pid, child, child_own)
    absent(ctx, warm.pid, child, parent_own)
    absent(ctx, warm.pid, parent, child_own)
    assert_provider(ctx, parent, child, original, child_own, parent_own)
    assert_no_work(ctx, warm.pid, 6)
    original_rollout = snapshot(parent_saved["path"])
    existing_child_rollout = snapshot(child_path)

    reverted =
      call(ctx, warm.pid, "thread/revert", %{"threadId" => parent, "beforeTurnId" => third.id})

    assert reverted["thread"]["id"] === parent
    assert reverted["thread"]["turns"] === []
    parent_reverted = history(ctx, warm.pid, parent, [first, second])
    refute parent_reverted["path"] == parent_saved["path"]
    final_child = history(ctx, warm.pid, child, child_expected)
    assert final_child["path"] === child_path
    assert final_child["turns"] === child_saved["turns"]
    assert snapshot(parent_saved["path"]) === original_rollout
    assert snapshot(child_path) === existing_child_rollout
    selection(ctx, warm.pid, parent, second)
    for removed <- [third, fourth, parent_own], do: absent(ctx, warm.pid, parent, removed)
    selection(ctx, warm.pid, child, third)
    selection(ctx, warm.pid, child, child_own)
    absent(ctx, warm.pid, child, fourth)
    absent(ctx, warm.pid, child, parent_own)
    assert_no_work(ctx, warm.pid, 6)

    retained =
      Map.new(
        [parent_saved["path"], parent_reverted["path"], child_path, ctx.fixture.requests],
        &{&1, snapshot(&1)}
      )

    cold_boundary = length(Agent.get(ctx.capture, & &1.out))
    close(warm)
    cold = start(ctx)
    refute cold.native == warm.native
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # The first content read of this new native process is the inherited item
    # lookup. Neither resume nor full-history hydration may precede it.
    assert call(ctx, cold.pid, "thread/items/read", query(child, third)) === %{
             "data" => third.entries
           }

    cold_calls = Agent.get(ctx.capture, &Enum.drop(&1.out, cold_boundary))

    assert Enum.map(cold_calls, & &1.wire["method"]) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/items/read)

    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    for row <- [first, second, third, child_own], do: selection(ctx, cold.pid, child, row)
    for row <- [fourth, parent_own], do: absent(ctx, cold.pid, child, row)
    selection(ctx, cold.pid, parent, second)
    for row <- [third, fourth, parent_own], do: absent(ctx, cold.pid, parent, row)
    cold_child = history(ctx, cold.pid, child, child_expected)
    cold_parent = history(ctx, cold.pid, parent, [first, second])
    assert cold_child["path"] === child_path and cold_child["turns"] === final_child["turns"]
    assert cold_parent["path"] === parent_reverted["path"]
    assert cold_parent["turns"] === parent_reverted["turns"]
    assert call(ctx, cold.pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_retained(ctx, cold.pid, retained)

    resumed = call(ctx, cold.pid, "thread/resume", %{"threadId" => child, "excludeTurns" => true})
    assert resumed["thread"]["id"] === child
    assert resumed["thread"]["turns"] === []
    resumed_child = history(ctx, cold.pid, child, child_expected)
    assert resumed_child["path"] === child_path
    assert resumed_child["turns"] === final_child["turns"]
    selection(ctx, cold.pid, child, third)
    selection(ctx, cold.pid, child, child_own)
    absent(ctx, cold.pid, child, fourth)
    absent(ctx, cold.pid, parent, third)
    assert_no_work(ctx, cold.pid, 6)
    close(cold)
    # Resume may append normal session metadata; it must preserve the exact
    # existing history prefix and must not modify the other retained rollouts.
    for {path, saved} <- retained do
      if path == child_path,
        do: assert(String.starts_with?(snapshot(path).bytes, saved.bytes)),
        else: assert(snapshot(path) === saved)
    end

    assert_inputs(ctx.inputs)
    assert_inventory(ctx)
  end

  defp complete(ctx, pid, thread, index) do
    marker = Enum.at(@markers, index - 1)
    client = "owned-inherited-client-#{index}"
    before_ms = System.system_time(:millisecond)

    result =
      call(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "clientUserMessageId" => client,
        "input" => [%{"type" => "text", "text" => marker}]
      })

    turn = result["turn"]["id"]
    assert_identity(turn)
    events = collect(pid, thread, turn, [], deadline(20_000))
    after_ms = System.system_time(:millisecond)
    completed = item_events(events, "item/completed", thread, turn)

    assert Enum.map(completed, & &1.wire["params"]["item"]["type"]) === [
             "userMessage",
             "agentMessage"
           ]

    [user_event, agent_event] = completed
    user_id = user_event.wire["params"]["item"]["id"]
    assert_identity(user_id)

    user = %{
      "id" => user_id,
      "type" => "userMessage",
      "clientId" => client,
      "content" => [%{"type" => "text", "text" => marker, "text_elements" => []}]
    }

    agent = %{
      "id" => "fixture-message-#{index}",
      "type" => "agentMessage",
      "text" => @answer,
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

    entries =
      for {event, item} <- [{user_event, user}, {agent_event, agent}] do
        params = event.wire["params"]
        assert params["item"] === item
        assert_original(ctx, event)

        [started] =
          Enum.filter(
            item_events(events, "item/started", thread, turn),
            &(&1.wire["params"]["item"]["id"] == item["id"])
          )

        assert_original(ctx, started)
        assert started.sequence < event.sequence
        assert started.wire["params"]["item"]["type"] === item["type"]
        began = Map.fetch!(started.wire["params"], "startedAtMs")
        ended = Map.fetch!(params, "completedAtMs")
        assert is_integer(began) and is_integer(ended)
        assert before_ms <= began and began <= ended and ended <= after_ms
        %{"turnId" => turn, "item" => item, "startedAtMs" => began, "completedAtMs" => ended}
      end

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             for(
               event <- events,
               event.wire["method"] == "turn/completed",
               do: event.wire["params"]
             )

    assert length(ModelFixture.requests(ctx.fixture)) == index
    # Metadata-only read is the native durable-store barrier, never an oracle.
    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})["thread"]

    assert saved["id"] === thread and saved["turns"] === []
    %{id: turn, marker: marker, entries: entries, index: index}
  end

  defp selection(ctx, pid, thread, row) do
    params = query(thread, row)
    assert call(ctx, pid, "thread/items/read", params) === %{"data" => row.entries}
    ids = Enum.map(row.entries, & &1["item"]["id"])
    mixed = ["owned-absent-inherited-item" | Enum.reverse(ids) ++ ids]

    assert call(ctx, pid, "thread/items/read", %{params | "itemIds" => mixed}) === %{
             "data" => row.entries
           }
  end

  defp absent(ctx, pid, thread, row),
    do: assert(call(ctx, pid, "thread/items/read", query(thread, row)) === %{"data" => []})

  defp query(thread, row),
    do: %{
      "threadId" => thread,
      "turnId" => row.id,
      "itemIds" => Enum.map(row.entries, & &1["item"]["id"])
    }

  defp history(ctx, pid, thread, expected) do
    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"
    assert_owned_path(ctx, saved["path"])
    assert Enum.map(saved["turns"], & &1["id"]) === Enum.map(expected, & &1.id)

    for {actual, row} <- Enum.zip(saved["turns"], expected) do
      assert actual["status"] === "completed" and actual["error"] === nil
      assert actual["items"] === Enum.map(row.entries, & &1["item"])
    end

    saved
  end

  defp assert_provider(ctx, parent, child, original, child_own, parent_own) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 6
    expected_rows = original ++ [child_own, parent_own]

    prefixes = [
      Enum.take(@markers, 1),
      Enum.take(@markers, 2),
      Enum.take(@markers, 3),
      Enum.take(@markers, 4),
      Enum.take(@markers, 3) ++ [child_own.marker],
      Enum.take(@markers, 4) ++ [parent_own.marker]
    ]

    for {request, row, markers} <- Enum.zip([requests, expected_rows, prefixes]) do
      thread = if row.index == 5, do: child, else: parent
      assert request["model"] === "mock-model"

      assert %{"thread_id" => ^thread, "turn_id" => turn} =
               JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

      assert turn === row.id

      assert %{
               "role" => "developer",
               "content" => [%{"type" => "input_text", "text" => @instructions}]
             } =
               hd(request["input"])

      texts =
        for item <- request["input"],
            item["role"] == "user",
            part <- Map.get(item, "content", []),
            part["type"] == "input_text",
            part["text"] in @markers,
            do: part["text"]

      assert texts === markers
    end
  end

  defp collect(pid, thread, turn, events, until) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         events,
         &(&1.wire["method"] == "turn/completed" and
             &1.wire["params"]["threadId"] == thread and &1.wire["params"]["turn"]["id"] == turn)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "native inherited-items turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected inherited-items event gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, until)
    end
  end

  defp item_events(events, method, thread, turn),
    do:
      Enum.filter(
        events,
        &(&1.wire["method"] == method and
            &1.wire["params"]["threadId"] == thread and &1.wire["params"]["turnId"] == turn)
      )

  defp assert_original(ctx, event) do
    entries = Agent.get(ctx.capture, & &1.in)

    assert [_] =
             Enum.filter(
               entries,
               &(&1.wire === event.wire and JSON.decode!(&1.encoded) === event.wire)
             )
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 131_072,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 131_072,
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

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_inherited_items_read_lifecycle", "version" => "0.1.0"}
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
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    result
  end

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))

    assert [received] =
             Enum.filter(
               ledger.in,
               &(&1.wire["id"] == wire["id"] and not Map.has_key?(&1.wire, "method"))
             )

    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() == ["id", "result"]
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1000
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_retained(ctx, pid, retained) do
    assert_inputs(retained)
    assert_no_work(ctx, pid, 6)
  end

  defp assert_no_work(ctx, pid, count) do
    assert length(ModelFixture.requests(ctx.fixture)) == count
    assert_inputs(ctx.inputs)
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)
    requests = Enum.filter(ledger.out, &Map.has_key?(&1.wire, "id"))

    responses =
      Enum.filter(
        ledger.in,
        &(Map.has_key?(&1.wire, "id") and not Map.has_key?(&1.wire, "method"))
      )

    ids = Enum.map(requests, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == length(ids)
    assert length(responses) == length(requests)
    assert MapSet.new(Enum.map(responses, & &1.wire["id"])) === MapSet.new(ids)
    assert Enum.count(requests, &(&1.wire["method"] == "turn/start")) == 6
    assert Enum.count(requests, &(&1.wire["method"] == "thread/fork")) == 1
    assert Enum.count(requests, &(&1.wire["method"] == "thread/revert")) == 1
    assert Enum.count(requests, &(&1.wire["method"] == "thread/resume")) == 1

    for entry <- ledger.out do
      assert entry.wire["method"] in ~w(initialize initialized server/diagnostics thread/start turn/start thread/read thread/fork thread/items/read thread/revert thread/loaded/list thread/resume)
    end
  end

  defp assert_owned_path(ctx, path) do
    assert is_binary(path) and Path.type(path) == :absolute
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.regular?(path)
  end

  defp assert_identity(value), do: assert(is_binary(value) and byte_size(value) > 0)

  defp assert_inputs(inputs),
    do: Enum.each(inputs, fn {path, saved} -> assert snapshot(path) === saved end)

  defp snapshot(path) do
    assert File.stat!(path).size <= 2_097_152
    bytes = File.read!(path)
    assert byte_size(bytes) <= 2_097_152
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id, do: "owned-inherited-items-#{System.unique_integer([:positive, :monotonic])}"
  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
