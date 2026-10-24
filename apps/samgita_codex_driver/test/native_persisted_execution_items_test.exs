defmodule SamgitaCodexDriver.NativePersistedExecutionItemsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture, only: [call: 3, thread: 3, start_turn: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @scripts Path.expand("../../../scripts/codex", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @call_id "interaction-call-1"
  @mcp_message "Owned titled enum selection only"
  @mcp_meta %{"fixture/request" => %{"marker" => "titled-enum"}}
  @mcp_reply %{
    "action" => "accept",
    "content" => %{"route" => "green-id-λ"},
    "_meta" => %{"fixture/response" => %{"selected" => "green-id-λ"}}
  }
  @mcp_received %{
    "jsonrpc" => "2.0",
    "id" => "synthetic-titled-enum",
    "result" => @mcp_reply
  }
  @mcp_effect %{"effect" => "accepted-titled-enum", "route" => "green-id-λ"}

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-persisted-execution-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", Path.join(@scripts, tags[:provider_script]))

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # LIFO cleanup: each owned native/MCP process group, then provider, then root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    unless File.exists?(fixture.requests), do: File.write!(fixture.requests, "[]")
    assert ModelFixture.requests(fixture) == []
    File.mkdir!(Path.join(root, "tmp"))
    ctx = %{binary: binary, root: root, fixture: fixture}
    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  @tag provider_script: "server_interaction_fixture.py", scenario: "command_repeat"
  test "direct persisted command output survives a cold read without execution", ctx do
    # Independent OS input to the exact pin's shell selection, before native execution.
    command = expected_printf_command()
    observed_after_ms = System.system_time(:millisecond)

    {pid, id, turn, approval, events} =
      pending(
        ctx,
        "Owned persisted command execution only",
        "item/commandExecution/requestApproval"
      )

    params = approval.wire["params"]
    assert params["itemId"] == @call_id
    assert params["kind"] == "command"
    assert params["cwd"] == ctx.fixture.workspace
    assert params["proposedExecpolicyAmendment"] == ["printf"]
    assert_command(params["command"])
    assert params["command"] === command
    assert File.ls!(ctx.fixture.workspace) == []
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
    events = finish(pid, id, turn, approval, events)
    observed_before_ms = System.system_time(:millisecond)

    requests = assert_provider_continuation(ctx)
    [_, continued] = requests
    assert [output] = tool_outputs(continued)
    assert is_binary(output["output"])
    assert output["output"] =~ "Process exited with code 0"
    assert String.ends_with?(output["output"], "Output:\nsamgita_interaction")

    started = command_notification(events, "item/started")
    completed = command_notification(events, "item/completed")
    started_at_ms = Map.fetch!(started, "startedAtMs")
    completed_at_ms = Map.fetch!(completed, "completedAtMs")

    assert is_integer(started_at_ms)
    assert is_integer(completed_at_ms)
    assert observed_after_ms <= started_at_ms
    assert started_at_ms <= completed_at_ms
    assert completed_at_ms <= observed_before_ms

    # Only these two generated execution values come from the live item.
    process_id = Map.fetch!(completed["item"], "processId")
    duration_ms = Map.fetch!(completed["item"], "durationMs")
    assert is_binary(process_id) and Regex.match?(~r/^[1-9][0-9]{3,4}$/, process_id)
    assert String.to_integer(process_id) in 1_000..99_999
    assert is_integer(duration_ms) and duration_ms >= 0
    assert duration_ms <= observed_before_ms - observed_after_ms + 1

    expected = %{
      "id" => @call_id,
      "type" => "commandExecution",
      "pluginId" => nil,
      "scriptPath" => nil,
      "command" => command,
      "commandActions" => [%{"type" => "unknown", "command" => "printf samgita_interaction"}],
      "processId" => process_id,
      "durationMs" => duration_ms,
      "cwd" => ctx.fixture.workspace,
      "source" => "unifiedExecStartup",
      "status" => "completed",
      "exitCode" => 0,
      "aggregatedOutput" => "samgita_interaction"
    }

    # Approval synthesizes the first start; core suppresses its later canonical start.
    expected_started =
      Map.merge(expected, %{
        "source" => "agent",
        "status" => "inProgress",
        "processId" => nil,
        "aggregatedOutput" => nil,
        "exitCode" => nil,
        "durationMs" => nil
      })

    assert started === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected_started,
             "startedAtMs" => started_at_ms
           }

    assert completed === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected,
             "completedAtMs" => completed_at_ms
           }

    oracle = fn item ->
      assert Map.take(item, Map.keys(expected)) == expected
      assert item === expected
      assert_command(Map.fetch!(item, "command"))
      assert File.ls!(ctx.fixture.workspace) == []
    end

    entry_oracle = fn entry ->
      # Canonical start is not exposed by the suppressed live start. Observe only
      # this generated timestamp; independently bound it and retain exact cold equality.
      stored_started_at_ms = Map.fetch!(entry, "startedAtMs")
      assert is_integer(stored_started_at_ms)
      assert started_at_ms <= stored_started_at_ms
      assert stored_started_at_ms <= completed_at_ms

      assert entry === %{
               "turnId" => turn,
               "item" => expected,
               "startedAtMs" => stored_started_at_ms,
               "completedAtMs" => completed_at_ms
             }
    end

    persist_and_read_cold(
      ctx,
      pid,
      id,
      turn,
      requests,
      oracle,
      fn -> assert File.ls!(ctx.fixture.workspace) == [] end,
      entry_oracle
    )
  end

  @tag provider_script: "server_interaction_fixture.py", scenario: "patch"
  test "direct persisted added-file change matches owned bytes after a cold read", ctx do
    path = Path.join(ctx.fixture.workspace, "approved.txt")
    refute File.exists?(path)

    {pid, id, turn, approval, events} =
      pending(ctx, "Owned persisted added file only", "item/fileChange/requestApproval")

    assert approval.wire["params"]["itemId"] == @call_id

    assert %{"changes" => [%{"path" => ^path}]} =
             notification(events, "item/started", &(&1["item"]["type"] == "fileChange"))[
               "item"
             ]

    refute File.exists?(path)
    assert File.ls!(ctx.fixture.workspace) == []
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
    finish(pid, id, turn, approval, events)
    requests = assert_provider_continuation(ctx)

    expected = %{
      "id" => @call_id,
      "type" => "fileChange",
      "status" => "completed",
      "changes" => [
        %{"path" => path, "kind" => %{"type" => "add"}, "diff" => "synthetic patch\n"}
      ]
    }

    effect = fn ->
      assert File.lstat!(path).type == :regular
      assert File.read!(path) == "synthetic patch\n"
      assert File.ls!(ctx.fixture.workspace) == ["approved.txt"]
    end

    oracle = fn item ->
      assert item == expected
      effect.()
    end

    persist_and_read_cold(ctx, pid, id, turn, requests, oracle, effect)
  end

  @tag provider_script: "mcp_titled_enum_fixture.py", scenario: "legacy"
  test "direct persisted MCP result keeps the fixed selection with one owned effect", ctx do
    observed_after_ms = System.system_time(:millisecond)

    {pid, id, turn, request, events} =
      pending(ctx, @mcp_message, "mcpServer/elicitation/request", [
        %{"type" => "mention", "name" => "Fixture", "path" => "mcp://fixture"}
      ])

    assert request.wire["params"] === %{
             "threadId" => id,
             "turnId" => turn,
             "serverName" => "fixture",
             "mode" => "form",
             "message" => @mcp_message,
             "_meta" => @mcp_meta,
             "requestedSchema" => mcp_schema()
           }

    assert effects(ctx.fixture) == []
    assert :ok = Session.respond(pid, request.handle, {:ok, @mcp_reply})
    events = finish(pid, id, turn, request, events)
    observed_before_ms = System.system_time(:millisecond)
    requests = assert_provider_continuation(ctx)
    [_, continued] = requests
    assert [output] = tool_outputs(continued)

    assert [%{"type" => "input_text"}, %{"type" => "input_text", "text" => text}] =
             output["output"]

    assert JSON.decode!(text) === @mcp_received
    rows = journal(ctx.fixture)
    assert [call] = messages(rows, "in", "tools/call")
    assert %{"name" => "confirm", "arguments" => %{}} = call["params"]
    assert [initialize] = messages(rows, "in", "initialize")
    assert initialize["params"]["protocolVersion"] == "2025-06-18"
    assert messages(rows, "in", "server/discover") == []

    assert [received] =
             for(
               %{"direction" => "in", "message" => message} <- rows,
               message["id"] == "synthetic-titled-enum",
               do: message
             )

    assert received === @mcp_received

    started = mcp_notification(events, "item/started")
    completed = mcp_notification(events, "item/completed")
    started_at_ms = Map.fetch!(started, "startedAtMs")
    completed_at_ms = Map.fetch!(completed, "completedAtMs")
    duration_ms = Map.fetch!(completed["item"], "durationMs")
    assert is_integer(started_at_ms)
    assert is_integer(completed_at_ms)
    assert observed_after_ms <= started_at_ms
    assert started_at_ms <= completed_at_ms
    assert completed_at_ms <= observed_before_ms
    assert is_integer(duration_ms) and duration_ms >= 0
    assert duration_ms <= observed_before_ms - observed_after_ms + 1

    expected = %{
      "id" => @call_id,
      "type" => "mcpToolCall",
      "server" => "fixture",
      "tool" => "confirm",
      "arguments" => %{},
      "status" => "completed",
      "readOnlyHint" => true
    }

    # Fixture tools/list has no app UI metadata or plugin attribution. Its
    # tools/call result has one JSON text block and no structured content/_meta.
    # Compare that fixed text as decoded JSON; preserve every other wire member.
    expected_full =
      Map.merge(expected, %{
        "appContext" => nil,
        "mcpAppUi" => nil,
        "pluginId" => nil,
        "error" => nil,
        "durationMs" => duration_ms,
        "result" => %{
          "content" => [%{"type" => "text", "text" => @mcp_received}],
          "structuredContent" => nil,
          "_meta" => nil
        }
      })

    expected_started =
      Map.merge(expected_full, %{
        "status" => "inProgress",
        "durationMs" => nil,
        "result" => nil
      })

    assert started === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected_started,
             "startedAtMs" => started_at_ms
           }

    assert Map.update!(completed, "item", &mcp_result_semantics/1) === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected_full,
             "completedAtMs" => completed_at_ms
           }

    effect = fn ->
      assert effects(ctx.fixture) == [@mcp_effect]
      assert File.ls!(ctx.fixture.workspace) == []
    end

    oracle = fn item ->
      assert Map.take(item, Map.keys(expected)) == expected
      assert [%{"type" => "text", "text" => result_text}] = item["result"]["content"]
      assert item["result"]["content"] == [%{"type" => "text", "text" => result_text}]
      assert JSON.decode!(result_text) === @mcp_received
      assert mcp_result_semantics(item) === expected_full
      refute Map.has_key?(item, "mcpAppResourceUri")
      effect.()
    end

    entry_oracle = fn entry ->
      # This MCP path exposes its canonical start, unlike approval-synthetic commands.
      assert Map.update!(entry, "item", &mcp_result_semantics/1) === %{
               "turnId" => turn,
               "item" => expected_full,
               "startedAtMs" => started_at_ms,
               "completedAtMs" => completed_at_ms
             }
    end

    persist_and_read_cold(ctx, pid, id, turn, requests, oracle, effect, entry_oracle)
  end

  defp mcp_notification(events, method) do
    assert [params] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["id"] == @call_id,
               do: event.wire["params"]
             )

    params
  end

  defp mcp_result_semantics(item) do
    Map.update!(item, "result", fn result ->
      assert [%{"type" => "text", "text" => text} = content] = Map.fetch!(result, "content")
      assert is_binary(text)
      Map.put(result, "content", [%{content | "text" => JSON.decode!(text)}])
    end)
  end

  defp persist_and_read_cold(
         ctx,
         pid,
         id,
         turn,
         requests,
         oracle,
         effect,
         entry_oracle \\ fn _ -> :ok end
       ) do
    effect.()
    assert_idle(pid)

    # Observable native producer/store barrier, never the expected-item oracle.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [@call_id]}
    warm = call(pid, "thread/items/read", query)
    assert_direct(warm, turn, oracle, entry_oracle)
    assert_selection(pid, query, warm)
    assert ModelFixture.requests(ctx.fixture) == requests
    effect.()

    native_process = call(pid, "server/diagnostics", %{})["process"]["id"]
    close_owned(pid)
    cold = start(ctx)
    refute call(cold, "server/diagnostics", %{})["process"]["id"] == native_process
    assert call(cold, "thread/loaded/list", %{})["data"] == []

    # No resume/read barrier or new turn in this distinct process.
    persisted = call(cold, "thread/items/read", query)
    assert_direct(persisted, turn, oracle, entry_oracle)
    assert persisted == warm
    assert_selection(cold, query, warm)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert ModelFixture.requests(ctx.fixture) == requests
    effect.()
    assert_idle(cold)
    close_owned(cold)
    assert ModelFixture.requests(ctx.fixture) == requests
    effect.()
  end

  defp assert_direct(response, turn, oracle, entry_oracle) do
    assert Map.keys(response) == ["data"]
    assert [%{"turnId" => ^turn, "item" => item} = entry] = response["data"]
    assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
    assert item["id"] == @call_id
    oracle.(item)
    entry_oracle.(entry)
  end

  defp assert_selection(pid, query, expected) do
    assert call(
             pid,
             "thread/items/read",
             Map.put(query, "itemIds", [
               @call_id,
               @call_id,
               "owned-absent-item"
             ])
           ) == expected

    assert call(pid, "thread/items/read", Map.put(query, "itemIds", ["owned-absent-item"])) ==
             %{"data" => []}

    assert call(pid, "thread/items/read", Map.put(query, "turnId", "owned-absent-turn")) ==
             %{"data" => []}
  end

  defp pending(ctx, input, method, extra_input \\ []) do
    pid = start(ctx)
    id = thread(ctx, pid, %{"historyMode" => "paginated"})
    assert ModelFixture.requests(ctx.fixture) == []
    turn = start_turn(pid, id, [%{"type" => "text", "text" => input} | extra_input])
    events = collect(pid, [], &(interactions(&1) != []), true)
    assert [request] = interactions(events)
    assert request.wire["method"] == method
    assert request.wire["params"]["threadId"] == id
    assert request.wire["params"]["turnId"] == turn
    assert request.handle.id == request.wire["id"]
    assert request.handle.generation == Session.status(pid).generation
    assert is_reference(request.handle.reference)
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert File.ls!(ctx.fixture.workspace) == []
    {pid, id, turn, request, events}
  end

  defp finish(pid, id, turn, request, events) do
    request_id = request.wire["id"]

    events =
      collect(
        pid,
        events,
        fn all ->
          notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
            notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
        end,
        false
      )

    assert [^request] = interactions(events)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{"threadId" => ^id, "requestId" => ^request_id} =
             notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle == request.handle and outcome.status == :resolution_observed
    assert_idle(pid)
    events
  end

  defp assert_provider_continuation(ctx) do
    assert [first, continued] = requests = ModelFixture.requests(ctx.fixture)
    assert first["model"] == "mock-model" and continued["model"] == "mock-model"
    assert tool_outputs(first) == []
    assert [output] = tool_outputs(continued)
    assert output["call_id"] == @call_id
    requests
  end

  defp tool_outputs(request),
    do: Enum.filter(request["input"], &(&1["type"] == "function_call_output"))

  defp command_notification(events, method) do
    assert [params] =
             for(
               event <- events,
               event.wire["method"] == method,
               event.wire["params"]["item"]["id"] == @call_id,
               do: event.wire["params"]
             )

    params
  end

  defp expected_printf_command do
    # rust-v0.163.0 shell_detect.rs reads passwd, not SHELL. For a recognized,
    # existing account shell, get_shell_path returns that exact path before PATH.
    # Python is already required by ModelFixture; pwd uses the same account lookup.
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required for independent shell oracle"

    assert {encoded_shell, 0} =
             System.cmd(python, [
               "-c",
               "import json,os,pwd; print(json.dumps(pwd.getpwuid(os.getuid()).pw_shell))"
             ])

    shell = JSON.decode!(String.trim(encoded_shell))

    assert is_binary(shell) and Path.type(shell) == :absolute and File.regular?(shell),
           "BLOCKED_ENV: expected a regular absolute account shell"

    assert Path.basename(shell) in ~w(sh bash zsh),
           "BLOCKED_ENV: independent command oracle requires a POSIX account shell"

    # These characters are unquoted by pinned shlex 1.3.0. Keep other account
    # names visibly unsupported rather than copying a native presentation value.
    assert Regex.match?(~r|^[A-Za-z0-9_/.+@:-]+$|, shell),
           "BLOCKED_ENV: independent shell path requires shlex-safe characters"

    shell <> " -c 'printf samgita_interaction'"
  end

  defp assert_command(command) do
    assert [shell, "-c", "printf samgita_interaction"] = OptionParser.split(command)
    assert Path.type(shell) == :absolute and File.regular?(shell)
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp collect(pid, events, predicate, allow_request, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)

    unless allow_request do
      refute Enum.any?(incoming, &(&1.kind == :server_request)),
             "Unexpected native request; only the fixed owned interaction is answered"
    end

    events = events ++ incoming

    if predicate.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during persisted execution test")
      after
        remaining -> flunk("Persisted execution deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_persisted_execution_items", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
  end

  defp mcp_schema do
    %{
      "type" => "object",
      "properties" => %{
        "route" => %{
          "type" => "string",
          "title" => "Owned route λ",
          "description" => "Choose a synthetic identifier, not its display title.",
          "oneOf" => [
            %{"const" => "blue-id", "title" => "Blue display"},
            %{"const" => "green-id-λ", "title" => "Green display λ"}
          ],
          "default" => "blue-id"
        }
      },
      "required" => ["route"]
    }
  end

  defp journal(fixture) do
    case File.read(Path.join(fixture.codex_home, "mcp-titled-enum.jsonl")) do
      {:ok, text} -> text |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
      {:error, :enoent} -> []
    end
  end

  defp messages(rows, direction, method) do
    for %{"direction" => ^direction, "message" => message} <- rows,
        message["method"] == method,
        do: message
  end

  defp effects(fixture), do: Enum.filter(journal(fixture), &Map.has_key?(&1, "effect"))
  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))
end
