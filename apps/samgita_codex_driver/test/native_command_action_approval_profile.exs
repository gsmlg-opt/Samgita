defmodule SamgitaCodexDriver.NativeCommandActionApprovalProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.{Error, Wire}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag :isolated_command_action_approval
  @moduletag timeout: 60_000
  @script Path.expand("support/native_command_action_approval_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @inputs %{
    "owned.txt" => "owned read contents v119\n",
    "owned-dir/alpha.txt" => "owned alpha contents v119\n",
    "owned-dir/needle.txt" => "haystack\nOWNED_NEEDLE v119\n"
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    for tool <- ~w(python3 unshare ip cat ls rg), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-command-action-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    scenario = tags[:scenario]
    assert scenario in ~w(read list search)

    ctx = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      scenario: scenario,
      binary: Path.expand(binary),
      socket: Path.join(root, "native.sock")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: ["-B", @script, "--root", root, "--codex", ctx.binary, "--scenario", scenario],
        cwd: root,
        inherit_env: [],
        env: %{
          "CODEX_HOME" => Path.join(root, "codex"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "PYTHONDONTWRITEBYTECODE" => "1",
          "NO_COLOR" => "1",
          "RUST_LOG" => "off"
        }
      )

    ctx = Map.put(ctx, :owner, owner)

    on_exit(fn ->
      close_owner(ctx)
      assert_closed(ctx)
    end)

    await(fn -> state(ctx)["ready"] == true end)
    assert_namespace(ctx)
    assert_inputs(ctx)
    assert File.ls!(Path.join(root, "commands")) == []
    ctx
  end

  # Approval-request owners only; these expectations are never inferred from
  # execution-history siblings or from the received commandActions field.
  @tag scenario: "read"
  test "actual native read approval preserves exact action before one accepted stock read", ctx do
    qualify(ctx)
  end

  @tag scenario: "list"
  test "actual native list approval preserves exact action before one accepted stock listing",
       ctx do
    qualify(ctx)
  end

  @tag scenario: "search"
  test "actual native search approval preserves exact action before one accepted stock search",
       ctx do
    qualify(ctx)
  end

  defp qualify(ctx) do
    pid = client(ctx)
    warm_instance = Session.status(pid).instance_id
    native = List.last(state(ctx)["native_pids"])
    assert call(pid, "server/diagnostics", %{})["process"]["id"] == native
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha

    thread =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "approvalsReviewer" => "user",
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    before_turn = System.system_time(:millisecond)

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => marker(ctx)}]
      })["turn"]["id"]

    events = collect(pid, [], &(length(approvals(&1)) == 1))
    assert [approval] = approvals(events)
    assert_approval(ctx, pid, approval, thread, turn, before_turn)

    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.interaction_outcomes(pid) == []
    assert length(requests(ctx)) == 1
    assert File.ls!(Path.join(ctx.root, "commands")) == []
    assert_inputs(ctx)
    assert command_items(events, "item/completed", ctx) == []
    refute Enum.any?(events, &(&1.wire["method"] == "item/commandExecution/outputDelta"))

    # Exact native IDs, action, cwd, generation and still-pending state have all
    # been checked. Only this explicit response can release the owned command.
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})

    events =
      collect(pid, events, fn all ->
        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) != nil
      end)

    assert [^approval] = approvals(events)
    assert [started] = command_items(events, "item/started", ctx)
    assert started["status"] == "inProgress"
    assert started["source"] == "agent"
    assert started["commandActions"] === [action(ctx)]
    assert [completed] = command_items(events, "item/completed", ctx)
    assert_completed(ctx, completed)

    for method <- ["item/started", "item/completed"] do
      assert [%{"threadId" => ^thread, "turnId" => ^turn}] =
               for(
                 event <- events,
                 event.wire["method"] == method,
                 get_in(event.wire, ["params", "item", "id"]) == call_id(ctx),
                 do: Map.take(event.wire["params"], ~w(threadId turnId))
               )
    end

    assert [%{"threadId" => ^thread, "requestId" => request_id}] =
             params(events, "serverRequest/resolved")

    assert request_id == approval.wire["id"]

    assert [%{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}}] =
             params(events, "turn/completed")

    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle == approval.handle and outcome.status == :resolution_observed
    assert outcome.method == "item/commandExecution/requestApproval"

    assert {:ok, encoded} =
             Wire.encode(%{"id" => request_id, "result" => %{"decision" => "accept"}})

    assert outcome.response_digest == hash(encoded)

    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})

    assert_idle(pid)

    refute Enum.any?(
             events,
             &(&1.wire["method"] in ["error", "warning", "item/autoApprovalReview/started"])
           )

    assert_provider(ctx)
    command_journal = assert_execution(ctx)
    provider_journal = File.read!(Path.join(ctx.root, "requests.json"))
    assert_inputs(ctx)

    # A public full read is the native store barrier. The action/output oracle
    # remains the fixed expectation above, independent of either history read.
    history = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] = history["turns"]
    assert [persisted] = Enum.filter(items, &(&1["type"] == "commandExecution"))
    assert_completed(ctx, persisted)
    assert comparable(persisted) === comparable(completed)
    query = %{"threadId" => thread, "turnId" => turn, "itemIds" => [call_id(ctx)]}
    warm = call(pid, "thread/items/read", query)
    assert_selection(ctx, warm, turn)
    assert_no_reexecution(ctx, command_journal, provider_journal)
    assert :ok = Session.close(pid)
    control(ctx, "restart")
    assert state(ctx)["generation"] == 2
    await_gone(native)

    cold = client(ctx)
    refute Session.status(cold).instance_id == warm_instance
    refute List.last(state(ctx)["native_pids"]) == native
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    persisted_selection = call(cold, "thread/items/read", query)
    assert_selection(ctx, persisted_selection, turn)
    assert persisted_selection === warm
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_no_reexecution(ctx, command_journal, provider_journal)
    assert_idle(cold)
    assert :ok = Session.close(cold)
    close_owner(ctx)
    assert_closed(ctx)
    assert_no_reexecution(ctx, command_journal, provider_journal)
  end

  defp assert_approval(ctx, pid, approval, thread, turn, before_turn) do
    assert approval.kind == :server_request
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    params = approval.wire["params"]
    amendment = expected_execpolicy_amendment(ctx)
    assert is_integer(params["startedAtMs"])

    assert before_turn <= params["startedAtMs"] and
             params["startedAtMs"] <= System.system_time(:millisecond)

    assert Map.delete(params, "startedAtMs") === %{
             "kind" => "command",
             "threadId" => thread,
             "turnId" => turn,
             "itemId" => call_id(ctx),
             "environmentId" => "local",
             "reason" => "Owned command action #{ctx.scenario} only",
             "command" => command_display(ctx),
             "cwd" => ctx.workspace,
             "commandActions" => [action(ctx)],
             "proposedExecpolicyAmendment" => amendment,
             "availableDecisions" => [
               "accept",
               %{"acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => amendment}},
               "cancel"
             ]
           }

    assert approval.handle.id == approval.wire["id"]
    assert is_integer(approval.wire["id"]) or is_binary(approval.wire["id"])
    assert approval.handle.generation == Session.status(pid).generation
    assert is_reference(approval.handle.reference)
  end

  defp assert_completed(ctx, item) do
    # Pinned approval handling starts an Agent placeholder; the actual unified
    # executor completes it with UnifiedExecStartup. Stored items retain this
    # completion source rather than the earlier approval placeholder's source.
    assert comparable(item) === %{
             "id" => call_id(ctx),
             "type" => "commandExecution",
             "status" => "completed",
             "cwd" => ctx.workspace,
             "command" => command_display(ctx),
             "source" => "unifiedExecStartup",
             "commandActions" => [action(ctx)],
             "exitCode" => 0,
             "aggregatedOutput" => stdout(ctx)
           }
  end

  defp comparable(item),
    do:
      Map.take(
        item,
        ~w(id type status cwd command source commandActions exitCode aggregatedOutput)
      )

  defp expected_execpolicy_amendment(ctx) do
    shell = state(ctx)["expected_shell"]

    if shell == Path.join(ctx.root, "bin/sh") do
      [shell]
    else
      assert is_binary(shell) and Path.basename(shell) == "sh"
      String.split(command(ctx))
    end
  end

  defp assert_selection(ctx, selection, turn) do
    assert Map.keys(selection) == ["data"]
    assert [%{"turnId" => ^turn, "item" => item} = entry] = selection["data"]
    assert Enum.sort(Map.keys(entry)) == ~w(completedAtMs item startedAtMs turnId)
    assert_completed(ctx, item)
    assert is_integer(entry["startedAtMs"]) and is_integer(entry["completedAtMs"])
    assert entry["startedAtMs"] <= entry["completedAtMs"]
  end

  defp assert_provider(ctx) do
    assert [first, second] = requests = requests(ctx)
    assert Enum.all?(requests, &(&1["model"] == "mock-model"))
    assert Enum.filter(first["input"], &(&1["type"] == "function_call_output")) == []
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == call_id(ctx)
    assert output["output"] =~ "Process exited with code 0"
    assert String.ends_with?(output["output"], "Output:\n" <> stdout(ctx))
    assert read(ctx, "provider-audit.json") === %{"unexpected_http" => [], "errors" => []}
  end

  defp assert_execution(ctx) do
    assert File.ls!(Path.join(ctx.root, "commands")) == [ctx.scenario <> ".json"]
    journal = read(ctx, "commands/#{ctx.scenario}.json")
    [name | argv] = String.split(command(ctx))
    stock = state(ctx)["stock"][name]
    assert journal["status"] == "finished" and journal["scenario"] == ctx.scenario
    assert journal["args"] === [name | argv] and journal["cwd"] == ctx.workspace
    assert journal["namespace"] == state(ctx)["namespace"]["child"]
    assert journal["executable"] == stock["path"]
    assert journal["executable_sha256"] == hash(File.read!(stock["path"]))
    assert journal["stdout"] == stdout(ctx) and journal["stderr"] == ""
    assert journal["exit_code"] == 0 and journal["inputs_unchanged"] == true
    for key <- ~w(pid stock_pid), do: await_gone(journal[key])
    File.read!(Path.join(ctx.root, "commands/#{ctx.scenario}.json"))
  end

  defp assert_no_reexecution(ctx, command_journal, provider_journal) do
    assert assert_execution(ctx) === command_journal
    assert File.read!(Path.join(ctx.root, "requests.json")) === provider_journal
    assert_provider(ctx)
    assert_inputs(ctx)
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    refute File.exists?(Path.join(ctx.root, "codex/rules/default.rules"))
  end

  defp assert_inputs(ctx) do
    assert File.lstat!(ctx.workspace).type == :directory
    assert File.lstat!(Path.join(ctx.workspace, "owned-dir")).type == :directory
    assert Enum.sort(File.ls!(ctx.workspace)) == ["owned-dir", "owned.txt"]

    assert Enum.sort(File.ls!(Path.join(ctx.workspace, "owned-dir"))) == [
             "alpha.txt",
             "needle.txt"
           ]

    for {name, expected} <- @inputs do
      path = Path.join(ctx.workspace, name)
      assert File.lstat!(path).type == :regular
      assert File.read!(path) === expected
      assert state(ctx)["inputs"][name]["sha256"] == hash(expected)
      stat = File.stat!(path, time: :posix)
      assert stat.size == byte_size(expected)
      assert stat.mtime == div(state(ctx)["inputs"][name]["mtime_ns"], 1_000_000_000)
    end
  end

  defp action(%{scenario: "read"} = ctx),
    do: %{
      "type" => "read",
      "command" => command(ctx),
      "name" => "owned.txt",
      "path" => Path.join(ctx.workspace, "owned.txt")
    }

  defp action(%{scenario: "list"} = ctx),
    do: %{"type" => "listFiles", "command" => command(ctx), "path" => "owned-dir"}

  defp action(%{scenario: "search"} = ctx),
    do: %{
      "type" => "search",
      "command" => command(ctx),
      "query" => "OWNED_NEEDLE",
      "path" => "needle.txt"
    }

  defp command(%{scenario: "read"}), do: "cat owned.txt"
  defp command(%{scenario: "list"}), do: "ls -1 owned-dir"
  defp command(%{scenario: "search"}), do: "rg -n OWNED_NEEDLE owned-dir/needle.txt"
  defp stdout(%{scenario: "read"}), do: "owned read contents v119\n"
  defp stdout(%{scenario: "list"}), do: "alpha.txt\nneedle.txt\n"
  defp stdout(%{scenario: "search"}), do: "2:OWNED_NEEDLE v119\n"
  defp marker(ctx), do: "OWNED_COMMAND_ACTION_#{String.upcase(ctx.scenario)}_V119"
  defp call_id(ctx), do: "owned-command-action-#{ctx.scenario}-v119"

  defp command_display(ctx) do
    shell = state(ctx)["expected_shell"]
    assert shell == Path.join(ctx.root, "bin/sh") or Path.basename(shell) == "sh"
    assert Regex.match?(~r|^[A-Za-z0-9_/.+@:-]+$|, shell)
    shell <> " -c '" <> command(ctx) <> "'"
  end

  defp client(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_command_actions", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp control(ctx, operation) do
    id = "owned-command-action-control-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => operation}))
    await(fn -> state(ctx)["last_control_id"] == id end)
  end

  defp close_owner(ctx) do
    if Port.info(ctx.owner.port) != nil and File.exists?(Path.join(ctx.root, "state.json")) and
         "fixture_closed" not in state(ctx)["events"],
       do: control(ctx, "close")
  after
    assert :ok = Stdio.close(ctx.owner)
  end

  defp assert_namespace(ctx) do
    proof = state(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    refute proof["child"] == proof["parent"]
    assert proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    native = List.last(state(ctx)["native_pids"])
    assert File.read_link!("/proc/#{native}/ns/net") == proof["child"]
  end

  defp assert_closed(ctx) do
    proof = state(ctx)

    for os_pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
        do: await_gone(os_pid)

    assert Enum.count(proof["events"], &(&1 == "fixture_closed")) == 1
    assert Enum.count(proof["events"], &(&1 == "native_stopped")) == length(proof["native_pids"])

    for path <- Path.wildcard(Path.join(ctx.root, "commands/*.json")),
        key <- ~w(pid stock_pid),
        do: await_gone(JSON.decode!(File.read!(path))[key])
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end

  defp approvals(events), do: Enum.filter(events, &(&1.kind == :server_request))

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp command_items(events, method, ctx),
    do:
      for(
        event <- events,
        event.wire["method"] == method,
        get_in(event.wire, ["params", "item", "id"]) == call_id(ctx),
        do: event.wire["params"]["item"]
      )

  defp collect(pid, events, done, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(approvals(events)) <= 1

    if done.(events) do
      events
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} -> collect(pid, events, done, deadline)
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected command-action event gap")
      after
        remaining -> flunk("Owned command-action event deadline")
      end
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000

    if predicate.() do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned command-action observation deadline"

      receive do
      after
        10 -> :ok
      end

      await(predicate, deadline)
    end
  end

  defp await_gone(pid) do
    assert is_integer(pid) and pid > 0
    await(fn -> not File.exists?("/proc/#{pid}") end)
  end

  defp requests(ctx), do: read(ctx, "requests.json")
  defp state(ctx), do: read(ctx, "state.json")

  defp read(ctx, name) do
    case File.read(Path.join(ctx.root, name)) do
      {:ok, bytes} -> JSON.decode!(bytes)
      {:error, :enoent} -> %{}
    end
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
