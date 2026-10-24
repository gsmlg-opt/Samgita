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
    assert File.ls!(ctx.fixture.workspace) == []
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
    finish(pid, id, turn, approval, events)

    requests = assert_provider_continuation(ctx)
    [_, continued] = requests
    assert [output] = tool_outputs(continued)
    assert is_binary(output["output"])
    assert output["output"] =~ "Process exited with code 0"
    assert String.ends_with?(output["output"], "Output:\nsamgita_interaction")

    expected = %{
      "id" => @call_id,
      "type" => "commandExecution",
      "cwd" => ctx.fixture.workspace,
      "source" => "unifiedExecStartup",
      "status" => "completed",
      "exitCode" => 0,
      "aggregatedOutput" => "samgita_interaction"
    }

    oracle = fn item ->
      assert Map.take(item, Map.keys(expected)) == expected
      assert_command(Map.fetch!(item, "command"))
      assert File.ls!(ctx.fixture.workspace) == []
    end

    persist_and_read_cold(ctx, pid, id, turn, requests, oracle, fn ->
      assert File.ls!(ctx.fixture.workspace) == []
    end)
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
    finish(pid, id, turn, request, events)
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

    expected = %{
      "id" => @call_id,
      "type" => "mcpToolCall",
      "server" => "fixture",
      "tool" => "confirm",
      "arguments" => %{},
      "status" => "completed",
      "readOnlyHint" => true
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
      effect.()
    end

    persist_and_read_cold(ctx, pid, id, turn, requests, oracle, effect)
  end

  defp persist_and_read_cold(ctx, pid, id, turn, requests, oracle, effect) do
    effect.()
    assert_idle(pid)

    # Observable native producer/store barrier, never the expected-item oracle.
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    query = %{"threadId" => id, "turnId" => turn, "itemIds" => [@call_id]}
    warm = call(pid, "thread/items/read", query)
    assert_direct(warm, turn, oracle)
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
    assert_direct(persisted, turn, oracle)
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

  defp assert_direct(response, turn, oracle) do
    assert Map.keys(response) == ["data"]
    assert [%{"turnId" => ^turn, "item" => item} = entry] = response["data"]
    assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
    assert item["id"] == @call_id
    oracle.(item)
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
