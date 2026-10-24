defmodule SamgitaCodexDriver.NativeApprovalColdRestartProfileTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_approval_cold_restart_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @command "echo 'owned cold command' >> cold-command.txt; printf samgita_cold_command"
  @first "Owned unanswered cold approval"
  @second "Owned explicit post-crash command"
  @answer "Owned explicit cold command finished"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-cold-approval-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [
          @script,
          "--root",
          root,
          "--codex",
          Path.expand(binary)
        ],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          # The pinned native shell selector discovers the model's shell type on PATH.
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{
      root: root,
      owner: owner,
      socket: Path.join(root, "native.sock"),
      mode: tags.mode
    }

    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    assert [ready] = events(ctx, "bem-journal.json", "cold_provider_ready")
    assert ready["source_provider_requests"] == 0 and ready["request_auth"] == "none"

    assert ready["output"] == "fixed_owned_command_then_assistant_only"

    config = File.read!(Path.join(root, "codex/config.toml"))
    assert config =~ "cli_auth_credentials_store = \"file\""
    assert config =~ "requires_openai_auth = false"
    assert config =~ "supports_websockets = false"
    assert config =~ "enable_request_compression = false"
    assert config =~ "[analytics]\nenabled = false"
    refute config =~ "experimental_bearer_token"
    refute config =~ "experimental_realtime"
    refute File.exists?(Path.join(root, "codex/auth.json"))
    ctx
  end

  for mode <- ~w(legacy paginated) do
    @tag mode: mode
    test "#{mode} hard native restart cannot restore an unanswered approval or authorize the next explicit command",
         ctx do
      pid = connect(ctx)
      original = thread(pid, ctx)
      first = start_turn(pid, original, @first)
      initial = collect(pid, &Enum.any?(&1, fn event -> event.kind == :server_request end))
      assert [old] = Enum.filter(initial, &(&1.kind == :server_request))
      assert_approval(ctx, old, original, first, "cold-command-1")
      assert_no_effect(ctx, 1)
      assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
      live = call(pid, "thread/read", %{"threadId" => original, "includeTurns" => true})["thread"]
      assert [%{"id" => ^first, "status" => "inProgress"}] = live["turns"]
      # Verify the original user record reached the owned persistence artifact before SIGKILL.
      history_path = Map.fetch!(live, "path")
      assert is_binary(history_path) and String.starts_with?(history_path, ctx.root <> "/")
      await(fn -> File.regular?(history_path) and File.read!(history_path) =~ @first end)
      instance = Session.status(pid).instance_id
      native = json(ctx, "state.json")["native_pid"]
      control(ctx, "crashNative")

      assert [%{"native_pid" => ^native, "returncode" => -9, "reaped" => true}] =
               json(ctx, "cold-crashes.json")

      refute File.exists?("/proc/#{native}")
      await(fn -> Session.status(pid).phase == :disconnected end)

      assert %{interactions: 0, pending: 0, uncertain: 0, gap: %{reason: :disconnected}} =
               Session.status(pid)

      assert Session.interaction_outcomes(pid) == []
      assert Session.uncertain_operations(pid) == []
      assert_stale(pid, old)
      assert_no_effect(ctx, 1)
      assert :ok = Session.close(pid)

      control(ctx, "restart")
      refute json(ctx, "state.json")["native_pid"] == native
      cold = connect(ctx)
      refute Session.status(cold).instance_id == instance
      assert call(cold, "thread/loaded/list", %{})["data"] == []

      before_resume =
        call(cold, "thread/read", %{"threadId" => original, "includeTurns" => true})["thread"]

      assert before_resume["status"] == %{"type" => "notLoaded"}
      assert [%{"id" => ^first, "status" => "interrupted"} = abandoned] = before_resume["turns"]
      assert abandoned["completedAt"] == nil and abandoned["durationMs"] == nil
      assert abandoned["error"] == nil
      assert Enum.filter(abandoned["items"], &(&1["type"] == "commandExecution")) == []
      assert_no_effect(ctx, 1)
      assert_stale(cold, old)

      resumed = call(cold, "thread/resume", %{"threadId" => original})
      assert resumed["thread"]["id"] == original
      assert resumed["thread"]["turns"] == [abandoned]

      assert call(cold, "thread/read", %{"threadId" => original, "includeTurns" => true})[
               "thread"
             ][
               "turns"
             ] == [abandoned]

      # Stale-turn interruption above is a read projection, not a completion receipt.
      assert_idle(ctx, cold, 1)
      assert {:ok, recovered} = Session.drain(cold)

      refute Enum.any?(recovered, fn event ->
               event.kind == :server_request or
                 event.wire["method"] in [
                   "turn/started",
                   "turn/completed",
                   "item/started",
                   "item/completed",
                   "item/commandExecution/outputDelta"
                 ]
             end)

      assert_stale(cold, old)
      assert_no_effect(ctx, 1)

      second = start_turn(cold, original, @second)
      refute second == first
      pending = collect(cold, &Enum.any?(&1, fn event -> event.kind == :server_request end))
      assert [current] = Enum.filter(pending, &(&1.kind == :server_request))
      assert_approval(ctx, current, original, second, "cold-command-2")
      # Native numeric IDs restart at zero. Identity includes the driver instance/handle.
      assert current.wire["id"] == old.wire["id"]
      refute current.handle == old.handle
      assert_stale(cold, old)
      assert_stale(cold, old)
      assert %{interactions: 1, pending: 0, uncertain: 0} = Session.status(cold)
      assert_no_effect(ctx, 2)
      assert :ok = Session.respond(cold, current.handle, {:ok, %{"decision" => "accept"}})
      request_id = current.wire["id"]

      completed =
        collect(
          cold,
          fn rows ->
            completed?(rows, original, second) and
              Enum.any?(
                notices(rows, "serverRequest/resolved"),
                &(&1["requestId"] == request_id and &1["threadId"] == original)
              )
          end,
          pending
        )

      assert_completed(completed, original, second)

      assert [command] =
               for(
                 row <- notices(completed, "item/completed"),
                 row["threadId"] == original and row["turnId"] == second,
                 row["item"]["type"] == "commandExecution",
                 do: row["item"]
               )

      assert_command(ctx, command)

      assert File.read!(Path.join(ctx.root, "workspace/cold-command.txt")) ==
               "owned cold command\n"

      assert File.ls!(Path.join(ctx.root, "workspace")) == ["cold-command.txt"]
      assert [_, _, final_request] = json(ctx, "requests.json")
      assert @second in user_texts(final_request)

      history =
        call(cold, "thread/read", %{"threadId" => original, "includeTurns" => true})["thread"][
          "turns"
        ]

      assert [^abandoned, %{"id" => ^second, "status" => "completed"} = stored] = history
      commands = Enum.filter(stored["items"], &(&1["type"] == "commandExecution"))

      case ctx.mode do
        "paginated" ->
          assert [stored_command] = commands
          assert_command(ctx, stored_command)

        "legacy" ->
          # Native rollout policy omits command items in legacy history.
          assert commands == []
      end

      assert Enum.any?(stored["items"], &(&1["type"] == "agentMessage" and &1["text"] == @answer))
      assert_stale(cold, current)
      assert_idle(ctx, cold, 3)
      finish(ctx, cold)
    end
  end

  defp assert_approval(ctx, approval, thread, turn, item_id) do
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    params = approval.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["itemId"] == item_id and params["kind"] == "command"
    assert params["cwd"] == Path.join(ctx.root, "workspace")
    assert params["reason"] == "Owned synthetic cold approval only"
    assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0

    assert OptionParser.split(params["command"]) == [
             Path.join(ctx.root, "bin/sh"),
             "-c",
             @command
           ]
  end

  defp assert_command(ctx, command) do
    assert command["id"] == "cold-command-2" and command["status"] == "completed"
    assert command["cwd"] == Path.join(ctx.root, "workspace")

    assert OptionParser.split(command["command"]) == [
             Path.join(ctx.root, "bin/sh"),
             "-c",
             @command
           ]

    assert command["exitCode"] == 0 and command["aggregatedOutput"] == "samgita_cold_command"
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp assert_no_effect(ctx, count) do
    control(ctx, "barrier")
    assert File.ls!(Path.join(ctx.root, "workspace")) == []
    assert length(json(ctx, "requests.json")) == count
    refute File.exists?(Path.join(ctx.root, "codex/rules/default.rules"))
  end

  defp assert_idle(ctx, pid, count) do
    control(ctx, "barrier")

    assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert length(json(ctx, "requests.json")) == count
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []
    assert events(ctx, "realtime-journal.json", "handshake") == []
    assert events(ctx, "realtime-journal.json", "native_frame") == []
    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "codex/rules/default.rules"))
  end

  defp start_turn(pid, thread, text),
    do:
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

  defp connect(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport: {UnixSocket, [socket_path: ctx.socket]},
        request_timeout_ms: 10_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    # Choosing historyMode is experimental at the pin.
    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_approval_cold_restart", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp thread(pid, ctx) do
    id =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => Path.join(ctx.root, "workspace"),
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "historyMode" => ctx.mode,
        "ephemeral" => false
      })["thread"]["id"]

    assert_uuid(id)
    started = collect(pid, &notice(&1, "thread/started"))
    assert notice(started, "thread/started")["thread"]["id"] == id
    assert notices(started, "deprecationNotice") == []
    id
  end

  defp assert_completed(events, thread, turn) do
    [completion] =
      Enum.filter(
        notices(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

    assert completion["turn"]["status"] == "completed" and completion["turn"]["error"] == nil
  end

  defp completed?(events, thread, turn),
    do:
      Enum.any?(
        notices(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp finish(ctx, pid) do
    assert :ok = Session.close(pid)
    control(ctx, "close")
    assert length(events(ctx, "bem-journal.json", "fixture_closed")) == 1

    for native <- json(ctx, "state.json")["native_pids"],
        do: refute(File.exists?("/proc/#{native}"))
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: assert_process_reaped(pid)

      assert events(ctx, "bem-journal.json", "fixture_closed") != []
    end

    IO.puts(:stderr, "Owned approval cold-restart evidence retained: #{ctx.root}")
  end

  defp assert_process_reaped(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp user_texts(request),
    do:
      for(
        message <- request["input"],
        message["role"] == "user",
        part <- message["content"],
        part["type"] == "input_text",
        do: part["text"]
      )

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "owned-cold-approval-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.find(events(ctx, "bem-journal.json", "control_done"), &(&1["id"] == id)) end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned cold approval native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected cold approval event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned cold approval fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp notice(events, method), do: List.first(notices(events, method))
  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp events(ctx, name, kind), do: Enum.filter(json(ctx, name), &(&1["event"] == kind))

  defp assert_uuid(id),
    do: assert(id =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
end
