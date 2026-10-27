defmodule SamgitaCodexDriver.NativeTerminalInteractionEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/ordinary_terminal_interaction_fixture.py", __DIR__)
  @script_sha "f0750739ee76f66023e95dac447579b77e462e6271b799536f52d82a4bff86fd"
  @prompt "Owned ordinary terminal interaction only"
  @input "owned-terminal-input λ🙂\n"
  @ready "owned-terminal-ready\n"
  @output "owned-terminal-received λ🙂\n"
  @answer "Owned ordinary terminal interaction finished."
  @exec "owned-terminal-exec"
  @write "owned-terminal-write"
  @method "item/commandExecution/terminalInteraction"

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
      with {:ok, next} <- Stdio.send(state, encoded) do
        case record(next.capture, :out, encoded) do
          :ok -> {:ok, next}
          {:error, failure} -> {:error, failure, next}
        end
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          result = Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture))

          case result do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    defp record(capture, direction, encoded) do
      Agent.get_and_update(capture, fn ledger ->
        size = byte_size(encoded)
        limit = if direction == :out, do: 8192, else: 65_536

        if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
          entry = %{direction: direction, encoded: encoded, index: ledger.count + 1}

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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-ordinary-terminal-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.cp!(@script, Path.join(root, "bin/reader.py"))
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      python: python,
      binary: Path.expand(binary),
      capture: capture
    }

    peer = start_peer(profile)
    frozen = frozen_files(profile)
    native = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(native.pid).generation)
    %{profile: profile, peer: peer, native: native, frozen: frozen}
  end

  test "native terminal interaction keeps original exec identity and exact Unicode stdin across persisted reads",
       ctx do
    profile = ctx.profile
    pid = ctx.native.pid
    deadline = now() + 25_000

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "ephemeral" => false,
        "historyMode" => "paginated"
      })["thread"]["id"]

    assert_uuid(thread)
    lower = System.system_time(:millisecond)

    turn =
      call(profile, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => @prompt}]
      })["turn"]["id"]

    assert_uuid(turn)

    events =
      collect(profile, pid, [], min(deadline, now() + 5_000), fn _events ->
        state = peer_state(profile)

        length(state["requests"]) == 2 and length(state["emitted"]) == 1 and
          is_binary(state["sessionId"])
      end)

    state = peer_state(profile)
    process_id = state["sessionId"]
    assert Regex.match?(~r/\A[1-9][0-9]*\z/, process_id)
    assert String.to_integer(process_id) in 1000..99_999
    assert %{"pid" => reader_pid} = read_json(profile, "reader-started.json")
    assert is_integer(reader_pid) and reader_pid > 0
    assert File.exists?("/proc/#{reader_pid}")
    refute File.exists?(Path.join(profile.root, "reader-input.json"))
    before = call(profile, pid, "thread/backgroundTerminals/list", %{"threadId" => thread})
    assert [terminal] = before["data"]
    assert before["nextCursor"] === nil
    assert terminal["itemId"] === @exec and terminal["processId"] === process_id
    assert terminal["cwd"] === profile.workspace
    # The pinned projection deliberately supplies no OS process metrics. The
    # actual reader PID remains independently observed and checked for cleanup.
    assert Map.take(terminal, ~w(osPid cpuPercent rssKb)) === %{
             "osPid" => nil,
             "cpuPercent" => nil,
             "rssKb" => nil
           }

    # A live terminal projects the original tool command; command items below
    # separately project the complete shell argv.
    assert terminal["command"] === command(profile)
    release_boundary = length(capture(profile))
    release_lower = System.system_time(:millisecond)
    release_write(ctx.peer.port, min(deadline, now() + 5_000))

    events =
      collect(profile, pid, events, min(deadline, now() + 5_000), fn events ->
        Enum.any?(notices(events, "turn/completed"), &(&1.wire["params"]["turn"]["id"] == turn)) and
          Enum.any?(
            notices(events, "item/completed"),
            &(&1.wire["params"]["item"]["id"] == @exec)
          )
      end)

    upper = System.system_time(:millisecond)
    [interaction] = notices(events, @method)
    emitted = Map.fetch!(interaction.wire, "emittedAtMs")

    expected = %{
      "method" => @method,
      "params" => %{
        "threadId" => thread,
        "turnId" => turn,
        "itemId" => @exec,
        "processId" => process_id,
        "stdin" => @input
      },
      "emittedAtMs" => emitted
    }

    assert is_integer(emitted) and release_lower <= emitted and emitted <= upper
    assert interaction.kind === :notification and interaction.generation === profile.generation
    assert interaction.wire === expected
    assert :ok = Schema.validate(schema("ServerNotification.json"), expected, max_depth: 32)
    original = assert_original_interaction(profile, interaction)
    assert original.index > release_boundary

    [start] =
      notices(events, "item/started") |> Enum.filter(&(&1.wire["params"]["item"]["id"] == @exec))

    [completed] =
      notices(events, "item/completed")
      |> Enum.filter(&(&1.wire["params"]["item"]["id"] == @exec))

    # write_stdin holds the per-process interaction lock through its event;
    # the native exit watcher acquires that same lock before completion emission.
    assert start.sequence < interaction.sequence and interaction.sequence < completed.sequence
    assert start.wire["params"]["threadId"] === thread and start.wire["params"]["turnId"] === turn

    assert completed.wire["params"]["threadId"] === thread and
             completed.wire["params"]["turnId"] === turn

    item = completed.wire["params"]["item"]
    assert_command_item(item, profile, process_id, lower, upper)
    assert start.wire["params"]["item"]["processId"] === process_id
    assert start.wire["params"]["item"]["status"] === "inProgress"

    assert lower <= start.wire["params"]["startedAtMs"] and
             start.wire["params"]["startedAtMs"] <= emitted

    # Core completion time and app-server emission time use separate tasks;
    # their wall-clock order is not the notification publication order.
    assert release_lower <= completed.wire["params"]["completedAtMs"] and
             completed.wire["params"]["completedAtMs"] <= upper

    assert [done] = notices(events, "turn/completed")
    assert done.wire["params"]["threadId"] === thread
    assert done.wire["params"]["turn"]["status"] === "completed"

    assert Enum.filter(
             notices(events, "item/completed"),
             &(&1.wire["params"]["item"]["type"] == "agentMessage")
           )
           |> Enum.map(& &1.wire["params"]["item"]["text"]) === [@answer]

    assert_effects(profile, reader_pid)

    assert call(profile, pid, "thread/backgroundTerminals/list", %{"threadId" => thread}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    # Public store read is a completion barrier; terminal observations are not
    # promoted into extra command items or another execution.
    saved =
      call(profile, pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})[
        "thread"
      ]

    assert saved["id"] === thread and saved["historyMode"] === "paginated"
    assert saved["turns"] === []

    turns =
      call(profile, pid, "thread/turns/list", %{
        "threadId" => thread,
        "itemsView" => "full",
        "sortDirection" => "asc",
        "limit" => 100
      })

    assert turns["nextCursor"] === nil
    assert [%{"id" => ^turn, "status" => "completed", "error" => nil}] = turns["data"]
    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => [@exec]}
    history = call(profile, pid, "thread/items/read", query)
    assert [%{"turnId" => ^turn, "item" => ^item} = entry] = history["data"]
    assert entry["startedAtMs"] === start.wire["params"]["startedAtMs"]
    assert entry["completedAtMs"] === completed.wire["params"]["completedAtMs"]
    assert call(profile, pid, "thread/items/read", query) === history

    all_items =
      call(profile, pid, "thread/items/list", %{
        "threadId" => thread,
        "turnId" => turn,
        "limit" => 100
      })

    assert all_items["nextCursor"] === nil

    assert Enum.filter(all_items["data"], &(&1["item"]["type"] == "commandExecution"))
           |> Enum.map(& &1["item"]) === [item]

    peer = assert_peer(profile)
    peer_bytes = File.read!(Path.join(profile.root, "peer.json"))
    assert_inputs(ctx)
    assert {:ok, final} = Session.drain(pid, 128)
    events = events ++ final
    assert_events(profile, events)
    assert notices(events, @method) === [interaction]
    assert_original_interaction(profile, interaction)
    assert_ready(profile, pid)

    assert outgoing(profile) ===
             ~w(initialize initialized server/diagnostics thread/start turn/start thread/backgroundTerminals/list thread/backgroundTerminals/list thread/read thread/turns/list thread/items/read thread/items/read thread/items/list)

    warm_capture = Agent.get(profile.capture, & &1)
    close_native(ctx.native)
    assert_effects(profile, reader_pid)

    cold_capture =
      start_supervised!(
        Supervisor.child_spec(
          {Agent, fn -> %{count: 0, bytes: 0, records: []} end},
          id: :terminal_cold_capture
        )
      )

    cold_profile = %{profile | capture: cold_capture}
    cold = start_native(cold_profile)
    cold_profile = %{cold_profile | generation: Session.status(cold.pid).generation}
    refute :atomics.get(cold.identity, 1) === :atomics.get(ctx.native.identity, 1)

    assert call(cold_profile, cold.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert call(cold_profile, cold.pid, "thread/items/read", query) === history
    assert call(cold_profile, cold.pid, "thread/items/read", query) === history

    assert call(cold_profile, cold.pid, "thread/loaded/list", %{}) === %{
             "data" => [],
             "nextCursor" => nil
           }

    assert {:ok, cold_events} = Session.drain(cold.pid, 128)
    assert_events(cold_profile, cold_events)
    assert notices(cold_events, @method) === []

    assert Enum.filter(
             capture(cold_profile),
             &(&1.direction == :in and &1.wire["method"] == @method)
           ) === []

    assert_ready(cold_profile, cold.pid)

    assert outgoing(cold_profile) ===
             ~w(initialize initialized server/diagnostics thread/loaded/list thread/items/read thread/items/read thread/loaded/list)

    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert peer_state(profile) === peer
    assert Agent.get(profile.capture, & &1) === warm_capture
    assert assert_original_interaction(profile, interaction) === original
    assert_inputs(ctx)
    assert_effects(profile, reader_pid)
    assert now() <= deadline
    close_native(cold)
    close_transport(ctx.peer.transport, ctx.peer.identity)

    assert read_json(profile, "peer-closed.json") === %{
             "activeSockets" => 0,
             "handlerThreads" => 0,
             "threadAlive" => false,
             "serverClosed" => true
           }

    assert File.read!(Path.join(profile.root, "peer.json")) === peer_bytes
    assert_inputs(ctx)
    assert_effects(profile, reader_pid)
  end

  defp assert_command_item(item, profile, process_id, lower, upper) do
    assert item["id"] === @exec and item["type"] === "commandExecution"
    assert item["processId"] === process_id and item["cwd"] === profile.workspace
    assert item["command"] === display_command(profile)
    assert item["status"] === "completed" and item["exitCode"] === 0
    assert item["aggregatedOutput"] === @ready <> @output
    assert item["source"] === "unifiedExecStartup"
    assert is_integer(item["durationMs"]) and item["durationMs"] >= 0
    assert item["durationMs"] <= upper - lower + 1
  end

  defp assert_effects(profile, reader_pid) do
    assert read_json(profile, "reader-started.json") === %{"pid" => reader_pid}

    assert read_json(profile, "reader-input.json") === %{
             "text" => @input,
             "bytes" => :binary.bin_to_list(@input)
           }

    assert read_json(profile, "reader-finished.json") === %{
             "pid" => reader_pid,
             "inputBytes" => byte_size(@input)
           }

    refute File.exists?("/proc/#{reader_pid}")
    assert File.ls!(profile.workspace) === []
  end

  defp assert_original_interaction(profile, event) do
    [original] =
      Enum.filter(capture(profile), &(&1.direction == :in and &1.wire["method"] == @method))

    assert JSON.decode!(original.encoded) === event.wire
    assert {:ok, decoded} = Wire.decode(original.encoded, max_depth: 32)
    assert decoded === event.wire
    original
  end

  defp assert_peer(profile) do
    state = peer_state(profile)
    assert state["requestCount"] === 4 and state["errors"] === []

    assert state["controls"] === [
             %{"method" => "POST", "path" => "/fixture/release", "bodyBytes" => 0}
           ]

    assert [first, second, third] = state["requests"]
    assert first === %{"index" => 1, "marker" => @prompt, "toolOutputs" => []}
    assert second["index"] === 2 and third["index"] === 3
    assert second["marker"] === @prompt and third["marker"] === @prompt
    assert [initial] = second["toolOutputs"]
    assert initial["type"] === "function_call_output" and initial["call_id"] === @exec
    assert String.ends_with?(initial["output"], "Output:\n" <> @ready)

    assert Regex.scan(~r/^Process running with session ID ([1-9][0-9]*)$/m, initial["output"],
             capture: :all_but_first
           ) === [[state["sessionId"]]]

    assert [^initial, final] = third["toolOutputs"]
    assert final["type"] === "function_call_output" and final["call_id"] === @write
    assert final["output"] =~ "Process exited with code 0\n"
    assert String.ends_with?(final["output"], "Output:\n" <> @output)

    exec = %{
      "type" => "function_call",
      "name" => "exec_command",
      "call_id" => @exec,
      "arguments" => JSON.encode!(exec_args(profile))
    }

    write_args = %{
      "session_id" => String.to_integer(state["sessionId"]),
      "chars" => @input,
      "yield_time_ms" => 1000,
      "max_output_tokens" => 512
    }

    write = %{"type" => "function_call", "name" => "write_stdin", "call_id" => @write}

    answer = %{
      "type" => "message",
      "role" => "assistant",
      "id" => "owned-terminal-answer",
      "content" => [%{"type" => "output_text", "text" => @answer}]
    }

    assert [a, b, c] = state["emitted"]

    for {events, index, expected_item} <- [{a, 1, exec}, {b, 2, write}, {c, 3, answer}] do
      assert_backend_exchange(events, index, expected_item, profile, write_args)
    end

    state
  end

  defp assert_backend_exchange(events, index, expected_item, profile, write_args) do
    identity = "owned-terminal-response-#{index}"
    assert [created, output, completed] = events
    assert created === %{"type" => "response.created", "response" => %{"id" => identity}}
    assert output["type"] === "response.output_item.done"
    actual = output["item"]

    cond do
      index == 1 ->
        assert Map.delete(actual, "arguments") === Map.delete(expected_item, "arguments")
        assert JSON.decode!(actual["arguments"]) === exec_args(profile)

      index == 2 ->
        assert Map.delete(actual, "arguments") === expected_item
        assert JSON.decode!(actual["arguments"]) === write_args

      true ->
        assert actual === expected_item
    end

    assert Enum.sort(Map.keys(output)) === ["item", "type"]

    assert completed === %{
             "type" => "response.completed",
             "response" => %{
               "id" => identity,
               "usage" => %{
                 "input_tokens" => 0,
                 "input_tokens_details" => nil,
                 "output_tokens" => 0,
                 "output_tokens_details" => nil,
                 "total_tokens" => 0
               }
             }
           }
  end

  defp exec_args(profile),
    do: %{
      "cmd" => command(profile),
      "workdir" => profile.workspace,
      "shell" => Path.join(profile.root, "bin/sh"),
      "login" => false,
      "tty" => true,
      "yield_time_ms" => 1000,
      "max_output_tokens" => 512
    }

  defp command(profile),
    do: "exec #{profile.python} #{profile.root}/bin/reader.py --reader --root #{profile.root}"

  defp display_command(profile), do: "#{profile.root}/bin/sh -c '#{command(profile)}'"

  defp collect(profile, pid, events, deadline, predicate) do
    assert now() < deadline, "Owned terminal notification deadline"
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert_events(profile, events)
    assert peer_state(profile)["errors"] === []

    if predicate.(events) do
      events
    else
      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Owned terminal event gap")
      after
        10 -> :ok
      end

      collect(profile, pid, events, deadline, predicate)
    end
  end

  defp assert_events(profile, events) do
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152

    assert Enum.all?(
             events,
             &(&1.kind === :notification and &1.generation === profile.generation)
           )

    refute Enum.any?(events, &(&1.wire["method"] in ~w(error warning deprecationNotice)))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))
  end

  defp release_write(port, deadline) do
    remaining = deadline - now()
    assert remaining > 0

    assert {:ok, socket} =
             :gen_tcp.connect(
               {127, 0, 0, 1},
               port,
               [:binary, active: false, send_timeout: remaining, send_timeout_close: true],
               remaining
             )

    try do
      request =
        "POST /fixture/release HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"

      assert :ok = :gen_tcp.send(socket, request)
      response = control_response(socket, <<>>, deadline)
      assert byte_size(request) + byte_size(response) <= 8192

      assert response ===
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 17\r\nConnection: close\r\n\r\n{\"released\":true}"
    after
      assert :ok = :gen_tcp.close(socket)
    end
  end

  defp control_response(socket, bytes, deadline) do
    remaining = deadline - now()
    assert remaining > 0, "Owned terminal control deadline"

    case :gen_tcp.recv(socket, 0, remaining) do
      {:ok, data} ->
        assert byte_size(bytes) + byte_size(data) <= 8192
        control_response(socket, bytes <> data, deadline)

      {:error, :closed} ->
        bytes

      other ->
        flunk("Owned terminal control failed: #{inspect(other)}")
    end
  end

  defp start_peer(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [@script, "--root", profile.root],
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 8192
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = peer_startup(transport.port, <<>>, now() + 5_000)
    assert is_integer(startup["pid"]) and startup["pid"] > 0
    :atomics.put(identity, 1, startup["pid"])
    assert hash(File.read!(profile.python)) === hash(File.read!("/proc/#{startup["pid"]}/exe"))
    assert is_integer(startup["port"]) and startup["port"] in 1..65_535
    assert startup["command"] === command(profile) and startup["execArgs"] === exec_args(profile)
    %{transport: transport, identity: identity, port: startup["port"]}
  end

  defp peer_startup(port, bytes, deadline) do
    assert now() < deadline, "Owned terminal peer startup deadline"
    assert byte_size(bytes) <= 8192

    case String.split(bytes, "\n", parts: 2) do
      [line, ""] ->
        JSON.decode!(line)

      [_line, _extra] ->
        flunk("Unexpected terminal peer startup output")

      [_partial] ->
        receive do
          {^port, {:data, data}} -> peer_startup(port, bytes <> data, deadline)
          {^port, {:exit_status, status}} -> flunk("Owned terminal peer startup exit #{status}")
        after
          10 -> peer_startup(port, bytes, deadline)
        end
    end
  end

  defp start_native(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: profile.capture,
                    executable: profile.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: profile.workspace,
                    inherit_env: [],
                    env: environment(profile),
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    native = %{pid: pid, connection: connection, identity: identity}

    on_exit(fn ->
      close_native(native)
      path = Path.join(profile.root, "reader-started.json")

      if File.exists?(path),
        do: refute(File.exists?("/proc/#{JSON.decode!(File.read!(path))["pid"]}"))
    end)

    info = %{"name" => "owned_ordinary_terminal", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      profile,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    process_id = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(process_id) and process_id > 0
    :atomics.put(identity, 1, process_id)
    assert hash(File.read!("/proc/#{process_id}/exe")) === @binary_sha
    native
  end

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in and sent.index < received.index
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response and JSON.decode!(received.encoded) === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp assert_ready(profile, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === profile.generation
    assert Session.uncertain_operations(pid) === []
  end

  defp environment(profile),
    do: %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }

  defp frozen_files(profile),
    do:
      Map.new(
        ~w(codex/config.toml codex/models.json bin/reader.py bin/sh),
        &{&1, File.read!(Path.join(profile.root, &1))}
      )

  defp assert_inputs(ctx) do
    assert frozen_files(ctx.profile) === ctx.frozen
    assert hash(File.read!(@script)) === @script_sha
    assert File.ls!(ctx.profile.workspace) === []
  end

  defp capture(profile),
    do:
      Agent.get(profile.capture, & &1.records)
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))

  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] == method))

  defp outgoing(profile),
    do: for(frame <- capture(profile), frame.direction == :out, do: frame.wire["method"])

  defp peer_state(profile), do: read_json(profile, "peer.json")

  defp read_json(profile, path) do
    bytes = File.read!(Path.join(profile.root, path))
    assert byte_size(bytes) <= 2_097_152
    JSON.decode!(bytes)
  end

  defp schema(relative),
    do:
      :samgita_protocol_codex
      |> :code.priv_dir()
      |> Path.join("upstream/0.163.0/experimental/" <> relative)
      |> File.read!()
      |> JSON.decode!()

  defp close_native(native) do
    assert :ok = StdioSessionFixture.close(native.pid, native.connection)
    close_transport(native.connection, native.identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    os_pid = :atomics.get(identity, 1)
    if os_pid > 0, do: refute(File.exists?("/proc/#{os_pid}"))
  end

  defp assert_uuid(id),
    do:
      assert(
        is_binary(id) and
          Regex.match?(
            ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
            id
          )
      )

  defp request_id, do: "owned-terminal-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
