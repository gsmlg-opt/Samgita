defmodule SamgitaCodexDriver.NativeBackgroundTerminalProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/background_terminal_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @list "thread/backgroundTerminals/list"
  @clean "thread/backgroundTerminals/clean"
  @terminate "thread/backgroundTerminals/terminate"
  @continue "owned-continue λ🙂\n"
  @finish "owned-finish\n"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ["python3", "unshare", "ip"],
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-background-terminal-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp", "commands", "inputs", "bin"],
        do: File.mkdir_p!(Path.join(root, dir))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      socket: Path.join(root, "native.sock"),
      python: System.find_executable("python3"),
      shell: Path.join(root, "bin/sh"),
      workspace: Path.join(root, "workspace"),
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

    {:ok, owner} =
      Stdio.open(
        executable: ctx.python,
        args: [@script, "--root", root, "--codex", ctx.binary],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => ctx.shell,
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do:
              await(
                fn -> not File.exists?("/proc/#{os_pid}") end,
                "owned native/controller reaping"
              )
      end

      for path <- Path.wildcard(Path.join(root, "commands/*.json")) do
        os_pid = path |> File.read!() |> JSON.decode!() |> Map.fetch!("pid")
        await(fn -> not File.exists?("/proc/#{os_pid}") end, "owned reader reaping")
      end
    end)

    await(fn -> ready?(ctx) end, "private namespace/native UDS startup")

    assert read_json(ctx, "interpreter.json")["executable"] == ctx.python,
           "fixed interpreter path mismatch: controller sys.executable must equal approved ctx.python"

    proof = state(ctx)
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    Map.put(ctx, :owner, owner)
  end

  test "empty terminals, malformed native parameters and experimental negotiation execute nothing",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    assert terminals(pid, thread) == %{"data" => [], "nextCursor" => nil}
    assert call(pid, @clean, %{"threadId" => thread}) == %{}
    assert terminate(pid, thread, "2147483647") == false

    for id <- ["not-a-number", "2147483648"] do
      error = upstream_error(pid, @terminate, %{"threadId" => thread, "processId" => id})
      assert error["code"] == -32_600
      assert error["message"] =~ "invalid background terminal process id:"
    end

    error = upstream_error(pid, @list, %{"threadId" => thread, "cursor" => "invalid"})
    assert error["code"] == -32_600
    assert error["message"] =~ "invalid cursor:"

    for {method, params} <- [
          {@list, %{}},
          {@clean, %{"threadId" => 9}},
          {@terminate, %{"threadId" => thread}},
          {@list, %{"threadId" => thread, "limit" => -1}}
        ] do
      assert {:error, %Error{code: :schema_violation}} = Session.request(pid, method, params)
      assert upstream_error(pid, method, params, validation: :wire)["code"] == -32_600
    end

    stable = client(ctx, false)

    for {method, params} <- [
          {@list, %{"threadId" => thread}},
          {@clean, %{"threadId" => thread}},
          {@terminate, %{"threadId" => thread, "processId" => "2147483647"}}
        ] do
      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(stable, method, params)

      assert upstream_error(stable, method, params, validation: :wire) == %{
               "code" => -32_600,
               "message" => "#{method} requires experimentalApi capability"
             }
    end

    assert requests(ctx) == []
    assert Path.wildcard(Path.join(ctx.root, "commands/*.json")) == []
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))
  end

  test "actual core sessions paginate numerically and targeted termination preserves the other thread",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    turn = start_turn(pid, thread, "pair")

    {events, approvals} =
      finish(pid, ctx, thread, turn, [{:launch, "pair-a"}, {:launch, "pair-b"}])

    assert length(approvals) == 2
    assert_completed(events, thread, turn)
    sessions = sessions(ctx, ["pair-a", "pair-b"])
    entries = terminals(pid, thread)["data"]
    assert_entries(entries, ctx, sessions)
    assert terminals(pid, thread)["nextCursor"] == nil
    [first, second] = entries
    assert String.to_integer(first["processId"]) < String.to_integer(second["processId"])

    for limit <- [0, 1] do
      assert terminals(pid, thread, %{"limit" => limit}) == %{
               "data" => [first],
               "nextCursor" => first["processId"]
             }
    end

    assert terminals(pid, thread, %{"cursor" => first["processId"], "limit" => 1}) == %{
             "data" => [second],
             "nextCursor" => nil
           }

    empty_thread = thread(pid, ctx)
    assert terminals(pid, empty_thread) == %{"data" => [], "nextCursor" => nil}
    refute terminate(pid, empty_thread, first["processId"])
    assert terminals(pid, thread)["data"] == entries
    assert terminate(pid, thread, first["processId"])
    first_name = String.replace_prefix(first["itemId"], "owned-", "")
    assert_gone(ctx, first_name)
    await(fn -> terminals(pid, thread)["data"] == [second] end, "first native session removed")
    refute terminate(pid, thread, first["processId"])

    assert terminals(pid, thread, %{"cursor" => first["processId"], "limit" => 1}) == %{
             "data" => [second],
             "nextCursor" => nil
           }

    assert terminals(pid, thread, %{"cursor" => "2147483647"}) == %{
             "data" => [],
             "nextCursor" => nil
           }

    for id <- ["invalid", "2147483648"] do
      assert upstream_error(pid, @terminate, %{"threadId" => thread, "processId" => id})["code"] ==
               -32_600
    end

    assert terminals(pid, thread)["data"] == [second]

    assert File.exists?(
             "/proc/#{marker(ctx, String.replace_prefix(second["itemId"], "owned-", ""))["pid"]}"
           )

    assert terminate(pid, thread, second["processId"])
    assert_gone(ctx, String.replace_prefix(second["itemId"], "owned-", ""))
    assert length(requests(ctx)) == 3
    assert length(emitted(ctx)) == 2
  end

  test "clean ACK only submits cleanup and bounded observation proves owned processes stopped",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    turn = start_turn(pid, thread, "clean")
    {events, _} = finish(pid, ctx, thread, turn, [{:launch, "clean-a"}, {:launch, "clean-b"}])
    assert_completed(events, thread, turn)
    assert_entries(terminals(pid, thread)["data"], ctx, sessions(ctx, ["clean-a", "clean-b"]))
    assert call(pid, @clean, %{"threadId" => thread}) == %{}
    await(fn -> terminals(pid, thread)["data"] == [] end, "submitted clean drains native store")
    for name <- ["clean-a", "clean-b"], do: assert_gone(ctx, name)
    assert call(pid, @clean, %{"threadId" => thread}) == %{}
    assert terminals(pid, thread) == %{"data" => [], "nextCursor" => nil}
    assert length(requests(ctx)) == 3
    assert length(emitted(ctx)) == 2
  end

  test "native write_stdin preserves original item while current turn emits Unicode poll and final interactions",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    original_turn = start_turn(pid, thread, "interactive-start")

    {original_events, [launch]} =
      finish(pid, ctx, thread, original_turn, [{:launch, "interactive"}])

    assert_completed(original_events, thread, original_turn)
    %{"interactive" => session} = sessions(ctx, ["interactive"])
    [entry] = terminals(pid, thread)["data"]
    assert_entries([entry], ctx, %{"interactive" => session})

    turn = start_turn(pid, thread, "interactive-write")

    expected = [
      {:write, "interactive", session.id, "owned-continue", @continue, launch},
      {:write, "interactive", session.id, "owned-finish", @finish, launch}
    ]

    {events, approvals} = finish(pid, ctx, thread, turn, expected)
    assert length(approvals) == 2
    assert Enum.uniq(Enum.map(approvals, & &1.wire["id"])) |> length() == 2
    assert Enum.uniq(Enum.map(approvals, & &1.handle.reference)) |> length() == 2
    assert_completed(events, thread, turn)

    interactions = notifications(events, "item/commandExecution/terminalInteraction")
    assert Enum.map(interactions, & &1["stdin"]) == [@continue, "", @finish]

    for params <- interactions do
      assert params == %{
               "threadId" => thread,
               "turnId" => turn,
               "itemId" => "owned-interactive",
               "processId" => session.id,
               "stdin" => params["stdin"]
             }
    end

    # Native source guarantees the final nonempty interaction precedes command end.
    events = collect(pid, &item(&1, "item/completed", "owned-interactive"), events)
    completed = item(events, "item/completed", "owned-interactive")
    assert completed["status"] == "completed"
    assert completed["exitCode"] == 0
    assert completed["aggregatedOutput"] =~ "owned-read:owned-continue λ🙂"
    assert completed["aggregatedOutput"] =~ "owned-finished:interactive"

    finish_index =
      Enum.find_index(
        events,
        &(&1.wire["method"] == "item/commandExecution/terminalInteraction" and
            &1.wire["params"]["stdin"] == @finish)
      )

    completed_index =
      Enum.find_index(
        events,
        &(&1.wire["method"] == "item/completed" and
            &1.wire["params"]["item"]["id"] == "owned-interactive")
      )

    assert finish_index < completed_index
    assert read_json(ctx, "inputs/interactive.json") == [@continue, @finish]
    assert_gone(ctx, "interactive")
    assert terminals(pid, thread) == %{"data" => [], "nextCursor" => nil}
    assert length(requests(ctx)) == 6
    assert length(emitted(ctx)) == 4
    assert Session.status(pid).interactions == 0
    assert Session.uncertain_operations(pid) == []
  end

  test "cancelling exact stdin approval consumes no input and preserves the original background reader",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    original_turn = start_turn(pid, thread, "denial-start")
    {events, [launch]} = finish(pid, ctx, thread, original_turn, [{:launch, "denial"}])
    assert_completed(events, thread, original_turn)
    %{"denial" => session} = sessions(ctx, ["denial"])
    turn = start_turn(pid, thread, "denial-write")

    expected = [{:write, "denial", session.id, "owned-denied-write", @continue, launch}]
    {events, [_]} = finish(pid, ctx, thread, turn, expected, "cancel")

    assert notification(events, "turn/completed", &(&1["turn"]["id"] == turn))["turn"]["status"] ==
             "interrupted"

    assert notifications(events, "item/commandExecution/terminalInteraction") == []
    refute File.exists?(Path.join(ctx.root, "inputs/denial.json"))
    assert_entries(terminals(pid, thread)["data"], ctx, %{"denial" => session})
    assert File.exists?("/proc/#{marker(ctx, "denial")["pid"]}")
    assert terminate(pid, thread, session.id)
    assert_gone(ctx, "denial")
    assert length(requests(ctx)) == 3
    assert length(emitted(ctx)) == 2
    assert Session.status(pid).interactions == 0
  end

  defp client(ctx, experimental \\ true) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_terminals", "version" => "0.1.0"},
               %{
                 "experimentalApi" => experimental
               }
             )

    pid
  end

  defp thread(pid, ctx) do
    call(pid, "thread/start", %{
      "cwd" => ctx.workspace,
      "historyMode" => "legacy",
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request"
    })["thread"]["id"]
  end

  defp start_turn(pid, thread, scenario) do
    call(pid, "turn/start", %{
      "threadId" => thread,
      "input" => [%{"type" => "text", "text" => "synthetic:terminals:" <> scenario}]
    })["turn"]["id"]
  end

  defp finish(pid, ctx, thread, turn, expected, decision \\ "accept") do
    finish_loop(pid, ctx, {thread, turn}, expected, decision, [], [], now() + 15_000)
  end

  defp finish_loop(pid, ctx, {thread, turn}, expected, decision, acc, approvals, deadline) do
    assert {:ok, incoming} = Session.drain(pid)

    {expected, approvals} =
      Enum.reduce(incoming, {expected, approvals}, fn event, {remaining, seen} ->
        if event.kind == :server_request do
          assert [next | rest] = remaining
          validate_approval(event, next, pid, ctx, thread, turn)
          assert decision in event.wire["params"]["availableDecisions"]
          assert :ok = Session.respond(pid, event.handle, {:ok, %{"decision" => decision}})
          {rest, seen ++ [event]}
        else
          {remaining, seen}
        end
      end)

    acc = acc ++ incoming

    if notification(acc, "turn/completed", &(&1["turn"]["id"] == turn)) do
      assert expected == [], "missing exact native approval"
      {acc, approvals}
    else
      assert now() < deadline, "native terminal turn barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      finish_loop(pid, ctx, {thread, turn}, expected, decision, acc, approvals, deadline)
    end
  end

  defp validate_approval(event, expected, pid, ctx, thread, turn) do
    assert event.wire["method"] == "item/commandExecution/requestApproval"
    params = event.wire["params"]
    assert event.handle.generation == Session.status(pid).generation
    assert event.handle.id == event.wire["id"]
    assert is_reference(event.handle.reference)
    assert params["threadId"] == thread
    assert params["turnId"] == turn
    assert params["cwd"] == ctx.workspace
    assert is_integer(params["startedAtMs"])
    assert params["networkApprovalContext"] == nil
    assert params["additionalPermissions"] == nil
    assert params["proposedNetworkPolicyAmendments"] == nil

    case expected do
      {:launch, name} ->
        assert params["proposedExecpolicyAmendment"] == [ctx.shell]
        assert params["kind"] == "command"
        assert params["itemId"] == "owned-" <> name
        assert params["approvalId"] == nil
        assert is_binary(params["environmentId"]) and params["environmentId"] != ""
        assert OptionParser.split(params["command"]) == [ctx.shell, "-c", command(ctx, name)]
        assert params["reason"] == "Run only the fixed owned background-terminal reader"

      {:write, name, actual_id, call, text, launch} ->
        assert params["proposedExecpolicyAmendment"] == nil
        assert params["kind"] == "writeStdin"
        assert params["itemId"] == "owned-" <> name
        assert params["approvalId"] == call
        assert params["environmentId"] == launch.wire["params"]["environmentId"]

        assert OptionParser.split(params["command"]) == [
                 "write_stdin",
                 "--session-id",
                 actual_id,
                 text
               ]

        assert params["availableDecisions"] == ["accept", "cancel"]
        assert params["reason"] =~ "Send input to an existing terminal."
    end
  end

  defp sessions(ctx, names) do
    recorded = read_json(ctx, "observed-sessions.json")

    Map.new(names, fn name ->
      output = actual_tool_output(ctx, "owned-" <> name)
      assert [_, actual_id] = Regex.run(~r/^Process running with session ID ([0-9]+)$/m, output)
      assert recorded["owned-" <> name] == %{"process_id" => actual_id, "output" => output}
      assert String.to_integer(actual_id) > 0
      marker(ctx, name)
      {name, %{id: actual_id, item: "owned-" <> name}}
    end)
  end

  defp actual_tool_output(ctx, call) do
    outputs =
      for request <- requests(ctx),
          item <- request["input"] || [],
          item["type"] == "function_call_output" and item["call_id"] == call,
          do: item["output"]

    assert [output] = Enum.uniq(outputs)
    assert is_binary(output)
    output
  end

  defp assert_entries(entries, ctx, sessions) do
    expected =
      sessions
      |> Enum.map(fn {name, session} ->
        %{
          "itemId" => session.item,
          "processId" => session.id,
          "command" => command(ctx, name),
          "cwd" => ctx.workspace,
          "osPid" => nil,
          "cpuPercent" => nil,
          "rssKb" => nil
        }
      end)
      |> Enum.sort_by(&String.to_integer(&1["processId"]))

    assert entries == expected
  end

  defp command(ctx, name) do
    "exec " <>
      Enum.map_join(
        [ctx.python, @script, "--command", "--root", ctx.root, "--name", name],
        " ",
        fn value ->
          "'" <> String.replace(value, "'", "'\\''") <> "'"
        end
      )
  end

  defp marker(ctx, name) do
    value = read_json(ctx, "commands/#{name}.json")
    assert value["parent_namespace"] == ctx.parent_namespace
    assert value["namespace"] == state(ctx)["namespace"]
    assert value["interfaces"] == ["lo"]
    refute value["default_route"]
    refute value["ipv6_default_route"]
    assert value["cwd"] == ctx.workspace
    assert value["stdin_tty"]
    value
  end

  defp assert_gone(ctx, name) do
    os_pid = marker(ctx, name)["pid"]
    await(fn -> not File.exists?("/proc/#{os_pid}") end, "owned reader OS process gone")
  end

  defp assert_completed(events, thread, turn) do
    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
  end

  defp terminals(pid, thread, extra \\ %{}),
    do: call(pid, @list, Map.merge(%{"threadId" => thread}, extra))

  defp terminate(pid, thread, id),
    do: call(pid, @terminate, %{"threadId" => thread, "processId" => id})["terminated"]

  defp requests(ctx), do: read_json(ctx, "requests.json")
  defp emitted(ctx), do: read_json(ctx, "emitted-calls.json")
  defp state(ctx), do: read_json(ctx, "state.json")
  defp read_json(ctx, path), do: ctx.root |> Path.join(path) |> File.read!() |> JSON.decode!()

  defp ready?(ctx) do
    if File.exists?(Path.join(ctx.root, "state.json")),
      do: state(ctx)["ready"] and File.exists?(ctx.socket),
      else: false
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params, opts \\ []) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, opts)

    error
  end

  defp notifications(events, method) do
    for event <- events, event.wire["method"] == method, do: event.wire["params"]
  end

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp item(events, method, id) do
    case notification(events, method, &(&1["item"]["id"] == id)) do
      nil -> nil
      params -> params["item"]
    end
  end

  defp collect(pid, predicate, acc, deadline \\ nil) do
    deadline = deadline || now() + 5_000
    assert {:ok, incoming} = Session.drain(pid)
    refute Enum.any?(incoming, &(&1.kind == :server_request)), "unexpected additional approval"
    acc = acc ++ incoming

    if predicate.(acc) do
      acc
    else
      assert now() < deadline, "native terminal notification barrier"

      receive do
      after
        10 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, label, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(predicate, label, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
