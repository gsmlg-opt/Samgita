defmodule SamgitaCodexDriver.NativeFileChangeEnvelopeTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Schema

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/file_change_envelope_fixture.py", __DIR__)
  @script_sha "95fca287be034b34a40519377a24d8a7385d7b4c5b2ac1c207f5c410f2ae02b5"
  @provider_base Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_base_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @patch "item/fileChange/patchUpdated"
  @diff "turn/diff/updated"
  @added "owned added λ🙂\n"
  @control "owned untouched\n"
  @patch_parts [
    "*** Begin Patch\n*** Add File: owned-added.txt\n+owned added ",
    "λ🙂\n*** End Patch\n"
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
        {:ok, next} -> record_sent(next, encoded)
        other -> other
      end
    end

    defp record_sent(state, encoded) do
      case record(state.capture, :out, encoded) do
        :ok -> {:ok, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} -> record_received(next, events)
        other -> other
      end
    end

    defp record_received(state, events) do
      case Enum.reduce_while(events, :ok, &record_event(&1, &2, state.capture)) do
        :ok -> {:ok, events, state}
        {:error, failure} -> {:error, failure, state}
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Original native JSONL payloads, before Session decoding or projection.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded}

        {:ok,
         %{count: ledger.count + 1, bytes: ledger.bytes + size, records: [entry | ledger.records]}}
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
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@provider_base)) === @provider_base_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-file-change-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for child <- ~w(home codex workspace tmp bin), do: File.mkdir!(Path.join(root, child))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      workspace: Path.join(root, "workspace"),
      capture: capture
    }

    File.write!(Path.join(profile.workspace, "untouched.txt"), @control)
    provider = start_provider(profile)
    session = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)
    %{profile: profile, provider: provider, session: session}
  end

  test "whole native file-change envelopes match a real owned added file and independent net diff",
       ctx do
    assert_contracts()
    assert_workspace(ctx.profile, false)
    run = run_turn(ctx)
    preview = assert_patch_notices(ctx.profile, run)

    started =
      assert_item(
        ctx.profile,
        run,
        "item/started",
        file_item(ctx.profile, "inProgress"),
        "startedAtMs"
      )

    completed =
      assert_item(
        ctx.profile,
        run,
        "item/completed",
        file_item(ctx.profile, "completed"),
        "completedAtMs"
      )

    expected_diff = %{"threadId" => run.thread, "turnId" => run.turn, "diff" => expected_diff()}

    # One tool completion and both model-response completions emit the current
    # tracker snapshot; equal diff payloads remain three distinct native events.
    [tool_diff, first_response_diff, final_response_diff] =
      assert_notices(ctx.profile, run, [@diff], List.duplicate({@diff, expected_diff}, 3))

    assert List.last(preview).sequence < started.sequence
    assert started.sequence < completed.sequence
    assert completed.sequence < tool_diff.sequence
    assert tool_diff.sequence < first_response_diff.sequence
    assert first_response_diff.sequence < final_response_diff.sequence
    assert final_response_diff.sequence < run.finished.sequence

    assert_original_order(
      ctx.profile,
      preview ++
        [started, completed, tool_diff, first_response_diff, final_response_diff, run.finished]
    )

    file_events =
      Enum.filter(run.events, &(get_in(&1.wire, ["params", "item", "type"]) == "fileChange"))

    assert file_events === [started, completed]
    answer = assert_answer(ctx.profile, run, "owned-patch-answer", "Synthetic patch finished")
    assert first_response_diff.sequence < answer.sequence
    assert answer.sequence < final_response_diff.sequence
    assert_workspace(ctx.profile, true)
    [first, second] = assert_provider(ctx.profile, run, 2)
    [tool] = Enum.filter(first["tools"], &(&1["name"] == "apply_patch"))
    assert tool["type"] === "custom"
    assert_tool_result(second)
    assert read_json(ctx.profile, "provider-events.json") === provider_events()
    finish(ctx, run)
  end

  defp start_provider(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [@script, "--root", profile.root],
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 4096
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    %{transport: transport, identity: identity}
  end

  defp provider_startup(port, buffer, deadline) do
    assert now() < deadline, "Owned provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned provider startup output")
      [_partial] -> provider_startup(port, buffer, deadline)
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
    on_exit(fn -> close_native(pid, connection, identity) end)
    info = %{"name" => "owned_file_change_envelope", "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert_exchange(profile, wire, response)
    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, identity: identity}
  end

  defp environment(profile) do
    %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off"
    }
  end

  defp run_turn(ctx) do
    profile = ctx.profile
    pid = ctx.session.pid

    thread =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.workspace,
        "sandbox" => "danger-full-access",
        "approvalPolicy" => "never",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(thread) and byte_size(thread) > 0
    lower = System.system_time(:millisecond)
    marker = "synthetic:file-change-add"

    turn =
      call(profile, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker}],
        "collaborationMode" => %{
          "mode" => "default",
          "settings" => %{
            "model" => "mock-model",
            "reasoning_effort" => nil,
            "developer_instructions" => nil
          }
        }
      })["turn"]["id"]

    assert is_binary(turn) and byte_size(turn) > 0
    events = collect(pid, thread, turn, [], now() + 20_000)
    upper = System.system_time(:millisecond)
    [finished] = notices(events, "turn/completed")

    assert %{
             "threadId" => ^thread,
             "turn" => %{"id" => ^turn, "status" => "completed", "error" => nil}
           } = finished.wire["params"]

    %{
      thread: thread,
      turn: turn,
      marker: marker,
      events: events,
      finished: finished,
      lower: lower,
      upper: upper
    }
  end

  defp collect(pid, thread, turn, events, deadline) do
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152
    finished = Enum.any?(events, &completed?(&1, thread, turn))
    collect_or_return(pid, thread, turn, events, deadline, finished)
  end

  defp completed?(event, thread, turn),
    do:
      event.wire["method"] == "turn/completed" and event.wire["params"]["threadId"] == thread and
        get_in(event.wire, ["params", "turn", "id"]) == turn

  defp collect_or_return(_pid, _thread, _turn, events, _deadline, true), do: events

  defp collect_or_return(pid, thread, turn, events, deadline, false) do
    assert now() < deadline, "Owned file-change turn deadline"
    Process.sleep(10)
    collect(pid, thread, turn, events, deadline)
  end

  defp assert_patch_notices(profile, run) do
    selected = notices(run.events, @patch)
    full = patch_params(run, @added)
    empty = patch_params(run, "")

    # The consumer may coalesce argument progress; its final state must be exact.
    # Both possibilities are independently fixed by our two literal SSE deltas.
    expected =
      case length(selected) do
        1 -> [{@patch, full}]
        2 -> [{@patch, empty}, {@patch, full}]
        count -> flunk("Unexpected bounded native patch update count #{count}")
      end

    assert_notices(profile, run, [@patch], expected)
  end

  defp patch_params(run, content) do
    %{
      "threadId" => run.thread,
      "turnId" => run.turn,
      "itemId" => "owned-patch-call",
      "changes" => [
        %{"path" => "owned-added.txt", "kind" => %{"type" => "add"}, "diff" => content}
      ]
    }
  end

  defp file_item(profile, status) do
    %{
      "id" => "owned-patch-call",
      "type" => "fileChange",
      "status" => status,
      "changes" => [
        %{
          "path" => Path.join(profile.workspace, "owned-added.txt"),
          "kind" => %{"type" => "add"},
          "diff" => @added
        }
      ]
    }
  end

  defp expected_diff do
    "diff --git a/owned-added.txt b/owned-added.txt\n" <>
      "new file mode 100644\n" <>
      "index 0000000000000000000000000000000000000000..#{blob_oid(@added)}\n" <>
      "--- /dev/null\n+++ b/owned-added.txt\n@@ -0,0 +1 @@\n+owned added λ🙂\n"
  end

  # Independent Git blob encoding; no native/driver diff renderer is reused.
  defp blob_oid(content),
    do: Base.encode16(:crypto.hash(:sha, "blob #{byte_size(content)}\0" <> content), case: :lower)

  defp assert_workspace(profile, added?) do
    target = Path.join(profile.workspace, "owned-added.txt")
    control = Path.join(profile.workspace, "untouched.txt")
    assert File.lstat!(control).type === :regular
    assert File.read!(control) === @control

    if added? do
      assert File.lstat!(target).type === :regular
      assert File.read!(target) === @added
      assert Enum.sort(File.ls!(profile.workspace)) === ["owned-added.txt", "untouched.txt"]
    else
      refute File.exists?(target)
      assert File.ls!(profile.workspace) === ["untouched.txt"]
    end
  end

  defp assert_contracts do
    kind = %{
      "properties" => %{
        "type" => %{"enum" => ["add"], "title" => "AddPatchChangeKindType", "type" => "string"}
      },
      "required" => ["type"],
      "title" => "AddPatchChangeKind",
      "type" => "object"
    }

    item = %{
      "properties" => %{
        "changes" => %{
          "items" => %{"$ref" => "#/definitions/FileUpdateChange"},
          "type" => "array"
        },
        "id" => %{"type" => "string"},
        "status" => %{"$ref" => "#/definitions/PatchApplyStatus"},
        "type" => %{
          "enum" => ["fileChange"],
          "title" => "FileChangeThreadItemType",
          "type" => "string"
        }
      },
      "required" => ["changes", "id", "status", "type"],
      "title" => "FileChangeThreadItem",
      "type" => "object"
    }

    for flavor <- ["stable", "experimental"] do
      schema = notification_schema(flavor)
      assert Enum.at(get_in(schema, ["definitions", "PatchChangeKind", "oneOf"]), 0) === kind
      assert Enum.at(get_in(schema, ["definitions", "ThreadItem", "oneOf"]), 7) === item

      assert Enum.at(schema["oneOf"], 26) ===
               wrapper_schema(@diff, "Turn/diff/updated", "TurnDiffUpdatedNotification")

      assert Enum.at(schema["oneOf"], 41) ===
               wrapper_schema(
                 @patch,
                 "Item/fileChange/patchUpdated",
                 "FileChangePatchUpdatedNotification"
               )
    end
  end

  defp wrapper_schema(method, title, definition) do
    %{
      "properties" => %{
        "method" => %{
          "enum" => [method],
          "title" => title <> "NotificationMethod",
          "type" => "string"
        },
        "params" => %{"$ref" => "#/definitions/" <> definition}
      },
      "required" => ["method", "params"],
      "title" => title <> "Notification",
      "type" => "object"
    }
  end

  defp assert_notices(profile, run, methods, expected) do
    selected = Enum.filter(run.events, &(&1.wire["method"] in methods))
    assert length(selected) === length(expected)

    for {event, {method, params}} <- Enum.zip(selected, expected),
        do: assert_notice(profile, run, event, method, params)

    originals =
      for record <- capture(profile),
          record.direction == :in,
          record.wire["method"] in methods,
          do: record.wire

    assert originals === Enum.map(selected, & &1.wire)
    selected
  end

  defp assert_notice(profile, run, event, method, params) do
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert_time(emitted_at, run)
    assert event.kind === :notification and event.generation === profile.generation
    assert event.wire === %{"method" => method, "params" => params, "emittedAtMs" => emitted_at}
    schema = notification_schema()
    assert :ok = Schema.validate(schema, event.wire, max_depth: 32)
  end

  defp assert_item(profile, run, method, item, time_key) do
    [event] =
      Enum.filter(notices(run.events, method), &(&1.wire["params"]["item"]["id"] == item["id"]))

    time = Map.fetch!(event.wire["params"], time_key)
    assert_time(time, run)

    params = %{
      "threadId" => run.thread,
      "turnId" => run.turn,
      "item" => item,
      time_key => time
    }

    assert event.wire["params"] === params
    assert_notice(profile, run, event, method, params)

    originals =
      for record <- capture(profile),
          record.direction == :in,
          record.wire["method"] == method,
          get_in(record.wire, ["params", "item", "id"]) == item["id"],
          do: record

    assert [original] = originals
    assert original.wire === event.wire
    assert JSON.decode!(original.encoded) === event.wire
    event
  end

  defp assert_answer(profile, run, id, text) do
    [event] =
      Enum.filter(
        notices(run.events, "item/completed"),
        &(&1.wire["params"]["item"]["type"] == "agentMessage")
      )

    item = %{
      "type" => "agentMessage",
      "id" => id,
      "text" => text,
      "phase" => nil,
      "memoryCitation" => nil,
      "delivery" => nil,
      "questions" => nil
    }

    assert_item(profile, run, "item/completed", item, "completedAtMs")
    assert event.sequence < run.finished.sequence
    event
  end

  defp assert_time(time, run),
    do: assert(is_integer(time) and run.lower <= time and time <= run.upper)

  defp assert_provider(profile, run, count) do
    refute File.exists?(Path.join(profile.root, "provider-error.json"))
    requests = read_json(profile, "requests.json")
    assert length(requests) === count
    for request <- requests, do: assert_provider_request(request, run)
    requests
  end

  defp assert_tool_result(request) do
    [output] =
      Enum.filter(
        request["input"],
        &(&1["type"] in ~w(function_call_output custom_tool_call_output))
      )

    identity = Map.fetch!(output, "id")

    assert is_binary(identity) and
             Regex.match?(
               ~r/^ctco_[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               identity
             )

    assert is_binary(output["output"])

    assert [_, duration] =
             Regex.run(
               ~r/^Exit code: 0\nWall time: ([0-9]+(?:\.[0-9]+)?) seconds\nOutput:\n/,
               output["output"]
             )

    assert {seconds, ""} = Float.parse(duration)
    assert seconds >= 0 and seconds <= 20

    assert output === %{
             "type" => "custom_tool_call_output",
             "id" => identity,
             "call_id" => "owned-patch-call",
             "output" =>
               "Exit code: 0\nWall time: #{duration} seconds\nOutput:\n" <>
                 "Success. Updated the following files:\nA owned-added.txt\n"
           }
  end

  defp assert_provider_request(request, run) do
    assert request["model"] === "mock-model"
    metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
    assert metadata["thread_id"] === run.thread and metadata["turn_id"] === run.turn

    markers =
      for item <- request["input"],
          item["role"] == "user",
          part <- item["content"],
          part["type"] == "input_text",
          String.starts_with?(part["text"], "synthetic:file-change-"),
          do: part["text"]

    assert markers === [run.marker]
    assert byte_size(JSON.encode!(request)) <= 1_048_576
  end

  defp provider_events do
    item = %{
      "type" => "custom_tool_call",
      "id" => "owned-patch-item",
      "name" => "apply_patch",
      "call_id" => "owned-patch-call",
      "input" => Enum.join(@patch_parts)
    }

    body =
      [
        %{
          "type" => "response.output_item.added",
          "item" => Map.merge(item, %{"input" => "", "status" => "in_progress"})
        }
      ] ++
        Enum.map(@patch_parts, fn part ->
          %{
            "type" => "response.custom_tool_call_input.delta",
            "item_id" => "owned-patch-item",
            "call_id" => "owned-patch-call",
            "delta" => part
          }
        end) ++ [%{"type" => "response.output_item.done", "item" => item}]

    final = %{
      "type" => "message",
      "role" => "assistant",
      "id" => "owned-patch-answer",
      "content" => [%{"type" => "output_text", "text" => "Synthetic patch finished"}]
    }

    [
      provider_response(1, body),
      provider_response(2, [%{"type" => "response.output_item.done", "item" => final}])
    ]
  end

  defp provider_response(index, body) do
    id = "owned-file-change-response-#{index}"

    [%{"type" => "response.created", "response" => %{"id" => id}} | body] ++
      [
        %{
          "type" => "response.completed",
          "response" => %{
            "id" => id,
            "usage" => %{
              "input_tokens" => 0,
              "input_tokens_details" => nil,
              "output_tokens" => 0,
              "output_tokens_details" => nil,
              "total_tokens" => 0
            }
          }
        }
      ]
  end

  defp read_json(profile, name) do
    path = Path.join(profile.root, name)
    assert File.stat!(path).size <= 2_097_152
    path |> File.read!() |> JSON.decode!()
  end

  defp assert_original_order(profile, events) do
    originals = Enum.filter(capture(profile), &(&1.direction == :in))
    Enum.reduce(events, originals, &consume_original/2)
  end

  defp consume_original(event, originals) do
    assert [original | remaining] = Enum.drop_while(originals, &(&1.wire !== event.wire))
    assert JSON.decode!(original.encoded) === event.wire
    remaining
  end

  defp finish(ctx, run) do
    assert Enum.map(run.events, & &1.sequence) === Enum.sort(Enum.map(run.events, & &1.sequence))
    assert length(Enum.uniq_by(run.events, & &1.sequence)) === length(run.events)

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(ctx.session.pid)

    assert Session.uncertain_operations(ctx.session.pid) === []

    outgoing =
      for record <- capture(ctx.profile), record.direction == :out, do: record.wire["method"]

    assert outgoing === ~w(initialize initialized server/diagnostics thread/start turn/start)
    close_native(ctx.session.pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.provider.transport, ctx.provider.identity)
    assert_final_ingress(ctx.profile, run)
    assert_provider(ctx.profile, run, 2)
    assert_workspace(ctx.profile, true)
  end

  defp assert_final_ingress(profile, run) do
    methods = [@patch, @diff] ++ ~w(item/started item/completed turn/completed)

    originals =
      for record <- capture(profile),
          record.direction == :in,
          record.wire["method"] in methods,
          do: record.wire

    selected = for event <- run.events, event.wire["method"] in methods, do: event.wire
    assert originals === selected
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
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp notices(events, method), do: Enum.filter(events, &(&1.wire["method"] == method))

  defp notification_schema(flavor \\ "experimental") do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/#{flavor}/ServerNotification.json")
    |> File.read!()
    |> JSON.decode!()
  end

  defp close_native(pid, connection, identity) do
    assert :ok = StdioSessionFixture.close(pid, connection)
    close_transport(connection, identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp request_id,
    do: "owned-file-change-#{System.unique_integer([:positive, :monotonic])}"

  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
