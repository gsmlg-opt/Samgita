defmodule SamgitaCodexDriver.NativeResumeCollaborationResultTest do
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
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @answer "Deterministic local fixture answer"
  @warmup_markers ["Owned resume prerequisite first λ", "Owned resume prerequisite second λ"]
  @modes [
    %{
      "mode" => "plan",
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => nil,
        "developer_instructions" => "Owned resume result plan marker"
      }
    },
    %{
      "mode" => "default",
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => nil,
        "developer_instructions" => "Owned resume result default marker"
      }
    }
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
      case JSON.decode(encoded) do
        {:ok, wire} ->
          if selected?(direction, wire),
            do: Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire)),
            else: :ok

        {:error, _} ->
          :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 32 and size <= limit and ledger.bytes + size <= 1_048_576 do
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

  setup tags do
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs =
      Map.new(
        [
          config,
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          @provider,
          __ENV__.file,
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

  test "loaded native resume returns the complete applied nonnull collaboration object", ctx do
    assert ModelFixture.requests(ctx.fixture) == []
    first = start(ctx)
    first_result = qualify(ctx, first.pid, 1)
    close(first)
    assert_inputs(ctx)
    assert snapshot(ctx.fixture.requests) === first_result.journal

    second = start(ctx)
    assert second.native != first.native
    assert snapshot(ctx.fixture.requests) === first_result.journal
    second_result = qualify(ctx, second.pid, 2)
    assert second_result.thread != first_result.thread
    assert second_result.turn.id != first_result.turn.id
    ids = Enum.map(first_result.turn.items ++ second_result.turn.items, & &1["id"])
    assert length(ids) == 4 and length(Enum.uniq(ids)) == 4
    close(second)
    assert_inputs(ctx)
    assert snapshot(ctx.fixture.requests) === second_result.journal
    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_inventory(ctx)
  end

  defp qualify(ctx, pid, index) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    created =
      call(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })

    thread = Map.fetch!(Map.fetch!(created, "thread"), "id")
    assert is_binary(thread) and thread != ""

    # Fresh native threads have no rollout until their first real turn. The
    # assistant-only warmup supplies that prerequisite before either mode update.
    marker = Enum.fetch!(@warmup_markers, index - 1)
    params = %{"threadId" => thread, "input" => [%{"type" => "text", "text" => marker}]}
    turn = call(ctx, pid, "turn/start", params)["turn"]["id"]
    assert is_binary(turn) and turn != ""
    events = await_turn(ctx, pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)
    row = assert_turn(events, thread, turn, marker)
    assert_provider(ctx, index, thread, turn, marker)
    journal = snapshot(ctx.fixture.requests)
    persisted = read_history(ctx, pid, thread, row)
    path = Map.fetch!(persisted, "path")
    assert is_binary(path)
    assert String.starts_with?(Path.expand(path), Path.expand(ctx.fixture.codex_home) <> "/")
    assert File.lstat!(path).type == :regular
    history = Map.fetch!(persisted, "turns")
    assert_quiet(ctx, pid, journal)

    for expected <- @modes do
      assert_quiet(ctx, pid, journal)

      assert call(ctx, pid, "thread/settings/update", %{
               "threadId" => thread,
               "collaborationMode" => expected
             }) === %{}

      await_settings(ctx, pid, thread, expected, [], deadline())
      applied = read_history(ctx, pid, thread, row)
      assert Map.fetch!(applied, "turns") === history
      assert Map.fetch!(applied, "path") === path
      assert_quiet(ctx, pid, journal)
      response = call(ctx, pid, "thread/resume", %{"threadId" => thread, "excludeTurns" => true})
      assert Map.fetch!(response, "multiAgentMode") === "explicitRequestOnly"
      assert Map.fetch!(response, "collaborationMode") === expected
      assert Map.fetch!(response, "model") == "mock-model"
      assert Map.fetch!(response, "modelProvider") == "fixture"
      assert Map.fetch!(response, "cwd") == ctx.fixture.workspace
      resumed = Map.fetch!(response, "thread")
      assert Map.fetch!(resumed, "id") == thread
      assert Map.fetch!(resumed, "turns") === []
      retained = read_history(ctx, pid, thread, row)
      assert Map.fetch!(retained, "turns") === history
      assert Map.fetch!(retained, "path") === path
      assert_quiet(ctx, pid, journal)
    end

    assert call(ctx, pid, "thread/loaded/list", %{}) === %{
             "data" => [thread],
             "nextCursor" => nil
           }

    assert_quiet(ctx, pid, journal)
    %{thread: thread, turn: row, journal: journal}
  end

  defp await_turn(ctx, pid, thread, turn, events, until) do
    events = events ++ drain(ctx, pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576

    if TurnFixture.notification(events, "turn/completed", fn params ->
         params["threadId"] == thread and params["turn"]["id"] == turn
       end) do
      events
    else
      remaining = until - System.monotonic_time(:millisecond)
      assert remaining > 0, "native resume prerequisite turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} ->
          await_turn(ctx, pid, thread, turn, events, until)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected native resume prerequisite turn gap")
      after
        remaining -> flunk("native resume prerequisite turn deadline")
      end
    end
  end

  defp assert_turn(events, thread, turn, marker) do
    assert [started] = notifications(events, "turn/started", thread)
    assert %{"turn" => %{"id" => ^turn}} = started
    assert [completed] = notifications(events, "turn/completed", thread)

    assert %{"turn" => %{"id" => ^turn, "status" => "completed", "error" => nil}} = completed

    items = items(events, "item/completed", thread, turn)
    assert [user, assistant] = items
    assert Map.fetch!(user, "type") == "userMessage"

    assert Map.fetch!(user, "content") === [
             %{"type" => "text", "text" => marker, "text_elements" => []}
           ]

    assert Map.fetch!(assistant, "type") == "agentMessage"
    assert Map.fetch!(assistant, "text") == @answer

    assert Enum.map(items(events, "item/started", thread, turn), &Map.take(&1, ~w(id type))) ===
             Enum.map(items, &Map.take(&1, ~w(id type)))

    assert Enum.all?(items, &(is_binary(&1["id"]) and &1["id"] != ""))
    refute user["id"] == assistant["id"]
    %{id: turn, items: items}
  end

  defp notifications(events, method, thread) do
    for event <- events,
        event.wire["method"] == method,
        event.wire["params"]["threadId"] == thread,
        do: event.wire["params"]
  end

  defp items(events, method, thread, turn) do
    for params <- notifications(events, method, thread),
        params["turnId"] == turn,
        do: params["item"]
  end

  defp assert_provider(ctx, index, thread, turn, marker) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == index
    request = List.last(requests)
    assert Map.fetch!(request, "model") == "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

    assert Map.take(metadata, ~w(thread_id turn_id)) === %{
             "thread_id" => thread,
             "turn_id" => turn
           }

    texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(texts, &(&1 == marker)) == 1
  end

  defp read_history(ctx, pid, thread, row) do
    saved =
      call(ctx, pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

    assert Map.fetch!(saved, "id") == thread
    assert Map.fetch!(saved, "historyMode") == "paginated"
    assert [turn] = Map.fetch!(saved, "turns")

    assert Map.take(turn, ~w(id status error)) === %{
             "id" => row.id,
             "status" => "completed",
             "error" => nil
           }

    assert Map.fetch!(turn, "items") === row.items
    saved
  end

  defp await_settings(ctx, pid, thread, expected, events, until) do
    events = events ++ drain(ctx, pid)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert_no_turns(events)

    matches =
      for event <- events,
          event.wire["method"] == "thread/settings/updated",
          event.wire["params"]["threadId"] == thread,
          do: event.wire["params"]["threadSettings"]

    case matches do
      [settings] ->
        assert Map.fetch!(settings, "collaborationMode") === expected
        assert Map.fetch!(settings, "model") == "mock-model"
        assert Map.fetch!(settings, "modelProvider") == "fixture"
        assert Map.fetch!(settings, "cwd") == ctx.fixture.workspace
        assert Map.fetch!(settings, "personality") === nil
        assert Map.fetch!(settings, "summary") === nil

      [] ->
        remaining = until - System.monotonic_time(:millisecond)
        assert remaining > 0, "native collaboration settings deadline"

        receive do
          {:codex_driver, ^pid, :events_available} ->
            await_settings(ctx, pid, thread, expected, events, until)

          {:codex_driver, ^pid, {:gap, _}} ->
            flunk("Unexpected native collaboration settings gap")
        after
          remaining -> flunk("native collaboration settings deadline")
        end

      _ ->
        flunk("Duplicate native collaboration settings snapshot")
    end
  end

  defp assert_quiet(ctx, pid, journal) do
    assert_no_turns(drain(ctx, pid))
    assert_inputs(ctx)
    assert snapshot(ctx.fixture.requests) === journal
  end

  defp assert_no_turns(events) do
    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""
             String.starts_with?(method, "turn/") or String.starts_with?(method, "item/")
           end)
  end

  defp drain(_ctx, pid) do
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert Session.uncertain_operations(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Enum.all?(events, &(&1.kind == :notification))
    refute Enum.any?(events, &(&1.wire["method"] == "error"))

    events
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
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
    info = %{"name" => "owned_resume_collaboration_result", "version" => "0.1.0"}
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

    case Session.request_native(pid, wire, timeout_ms: 5_000) do
      {:ok, %{"id" => ^id, "result" => result} = response} ->
        assert_exchange(ctx, wire, response)
        result

      other ->
        flunk("Native #{method} did not succeed: #{inspect(upstream_summary(other))}")
    end
  end

  defp upstream_summary({:error, %SamgitaProtocolCodex.Error{wire: wire}}) when is_map(wire),
    do: wire |> Map.get("error", %{}) |> Map.take(["code", "message"])

  defp upstream_summary(_reply), do: :unexpected_reply

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] == wire["id"]))
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() == ["id", "result"]
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    generation = [
      "initialize",
      "server/diagnostics",
      "thread/loaded/list",
      "thread/start",
      "turn/start",
      "thread/read",
      "thread/settings/update",
      "thread/read",
      "thread/resume",
      "thread/read",
      "thread/settings/update",
      "thread/read",
      "thread/resume",
      "thread/read",
      "thread/loaded/list"
    ]

    assert Enum.map(ledger.out, & &1.wire["method"]) === generation ++ generation
    assert length(ledger.in) == 30
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 30
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_inputs(ctx) do
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert File.ls!(ctx.fixture.workspace) == []
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000

  defp request_id,
    do: "owned-resume-collaboration-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
