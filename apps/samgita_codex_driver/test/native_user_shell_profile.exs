defmodule SamgitaCodexDriver.NativeUserShellProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_user_shell_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ["python3", "unshare", "ip"],
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-user-shell-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ["home", "codex", "workspace", "tmp", "commands", "releases", "bin"],
        do: File.mkdir_p!(Path.join(root, dir))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      socket: Path.join(root, "native.sock"),
      python: System.find_executable("python3"),
      workspace: Path.join(root, "workspace"),
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

    {:ok, owner} =
      Stdio.open(
        executable: ctx.python,
        args: [
          @script,
          "--root",
          root,
          "--codex",
          ctx.binary,
          "--scenario",
          tags[:scenario] || "standalone"
        ],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        state = state(ctx)

        for os_pid <-
              state["native_pids"] ++ [state["controller_pid"], state["namespace_owner_pid"]] do
          await(
            fn -> not File.exists?("/proc/#{os_pid}") end,
            "owned fixture/native process reaping"
          )
        end
      end

      for path <- Path.wildcard(Path.join(root, "commands/*.json")) do
        os_pid = path |> File.read!() |> JSON.decode!() |> Map.fetch!("pid")
        await(fn -> not File.exists?("/proc/#{os_pid}") end, "owned user-shell command reaping")
      end
    end)

    await(fn -> ready?(ctx, 1) end, "isolated fixture startup")
    proof = state(ctx)
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    Map.put(ctx, :owner, owner)
  end

  test "ACK precedes completion and owned shell syntax executes with userShell item correlation",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    shell = start_shell(pid, thread, "  " <> command(ctx, "ack", "held") <> "  ")

    events =
      collect(
        pid,
        fn events -> output(events, shell.item) =~ "owned-ready:ack\n" end,
        shell.events
      )

    marker = marker(ctx, "ack")
    assert File.exists?("/proc/#{marker["pid"]}")
    assert Session.status(pid).pending == 0
    assert Session.uncertain_operations(pid) == []
    assert item(events, "item/started", shell.item)["status"] == "inProgress"
    assert item(events, "item/started", shell.item)["cwd"] == ctx.workspace
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == shell.turn))
    release(ctx, "ack")
    {completed, events} = finish_shell(pid, shell, events)
    assert completed["status"] == "completed" and completed["exitCode"] == 0
    assert completed["aggregatedOutput"] == "owned-ready:ack\nowned-done:ack\n"
    assert output(events, shell.item) == completed["aggregatedOutput"]
    assert_gone(ctx, "ack")

    target = Path.join(ctx.root, "pipeline.json")

    syntax =
      "printf '%s' 'owned pipeline input' | " <>
        command(ctx, "syntax", "stdin") <> " > " <> shell_quote(target)

    second = start_shell(pid, thread, syntax)
    {completed, _} = finish_shell(pid, second)
    assert completed["exitCode"] == 0
    assert completed["aggregatedOutput"] == nil

    assert JSON.decode!(File.read!(target)) == %{
             "stdin" => "owned pipeline input",
             "cwd" => ctx.workspace
           }

    marker(ctx, "syntax")
    assert_gone(ctx, "syntax")
    assert requests(ctx) == []
    assert :ok = Session.close(pid)
  end

  test "failed user-shell item and successful standalone turn remain different outcomes", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    shell = start_shell(pid, thread, command(ctx, "failure", "fail"))
    {completed, events} = finish_shell(pid, shell)
    assert completed["status"] == "failed" and completed["exitCode"] == 7
    assert completed["aggregatedOutput"] =~ "owned-stdout\n"
    assert completed["aggregatedOutput"] =~ "owned-stderr\n"

    assert notification(events, "turn/completed", &(&1["turn"]["id"] == shell.turn))["turn"][
             "status"
           ] == "completed"

    marker(ctx, "failure")
    assert_gone(ctx, "failure")
    assert requests(ctx) == []
    assert :ok = Session.close(pid)
  end

  test "paginated shell actions and fixed failure survive first cold selective reads", ctx do
    pid = client(ctx)

    id =
      call(pid, "thread/start", %{"cwd" => ctx.workspace, "historyMode" => "paginated"})[
        "thread"
      ]["id"]

    File.write!(Path.join(ctx.workspace, "owned.txt"), "owned-history\n")
    File.mkdir!(Path.join(ctx.workspace, "owned-dir"))
    File.write!(Path.join(ctx.workspace, "owned-dir/needle.txt"), "owned-history\n")
    account_shell = expected_account_shell(ctx)

    cases = [
      {"cat owned.txt",
       %{
         "type" => "read",
         "command" => "cat owned.txt",
         "name" => "owned.txt",
         "path" => Path.join(ctx.workspace, "owned.txt")
       }, "completed", 0, "owned-history\n"},
      {"ls owned-dir",
       %{"type" => "listFiles", "command" => "ls owned-dir", "path" => "owned-dir"}, "completed",
       0, "needle.txt\n"},
      {"grep -R owned-history -n owned-dir",
       %{
         "type" => "search",
         "command" => "grep -R owned-history -n owned-dir",
         "query" => "owned-history",
         "path" => "owned-dir"
       }, "completed", 0, "owned-dir/needle.txt:1:owned-history\n"},
      {"false", %{"type" => "unknown", "command" => "false"}, "failed", 1, nil}
    ]

    records =
      for {command, action, status, exit_code, output} <- cases do
        before_ms = System.system_time(:millisecond)
        shell = start_shell(pid, id, command)
        {completed, events} = finish_shell(pid, shell)
        after_ms = System.system_time(:millisecond)
        refute Enum.any?(events, &(&1.kind == :server_request))
        started = notification(events, "item/started", &(&1["item"]["id"] == shell.item))
        ended = notification(events, "item/completed", &(&1["item"]["id"] == shell.item))
        started_at = Map.fetch!(started, "startedAtMs")
        completed_at = Map.fetch!(ended, "completedAtMs")
        duration = Map.fetch!(completed, "durationMs")
        assert is_integer(started_at) and is_integer(completed_at)
        assert before_ms <= started_at and started_at <= completed_at and completed_at <= after_ms
        assert is_integer(duration) and duration >= 0 and duration <= after_ms - before_ms

        # rust-v0.163.0 uses the account shell, login=true and shlex::try_join.
        # These fixed scripts contain no quotes; all expected payload values
        # except generated identity/timing are prescribed before reading history.
        display_command =
          if command == "false",
            do: account_shell <> " -lc false",
            else: account_shell <> " -lc '" <> command <> "'"

        expected_item = %{
          "id" => shell.item,
          "type" => "commandExecution",
          "pluginId" => nil,
          "scriptPath" => nil,
          "command" => display_command,
          "commandActions" => [action],
          "cwd" => ctx.workspace,
          "processId" => nil,
          "source" => "userShell",
          "status" => status,
          "exitCode" => exit_code,
          "aggregatedOutput" => output,
          "durationMs" => duration
        }

        assert completed === expected_item

        assert notification(events, "turn/completed", &(&1["turn"]["id"] == shell.turn))[
                 "turn"
               ]["status"] == "completed"

        %{
          "query" => %{"threadId" => id, "turnId" => shell.turn, "itemIds" => [shell.item]},
          "entry" => %{
            "turnId" => shell.turn,
            "item" => expected_item,
            "startedAtMs" => started_at,
            "completedAtMs" => completed_at
          }
        }
      end

    assert_owned_history_files(ctx)
    assert requests(ctx) == []

    # Full read is the warm producer/store barrier, never the semantic oracle.
    assert length(
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]
           ) == 4

    assert_shell_selection(pid, records)
    assert_owned_history_files(ctx)
    assert requests(ctx) == []
    assert :ok = Session.close(pid)
    old = state(ctx)
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"restart" => true}))
    await(fn -> ready?(ctx, old["generation"] + 1) end, "explicit paginated shell restart")
    for os_pid <- old["native_pids"], do: refute(File.exists?("/proc/#{os_pid}"))
    refute List.last(state(ctx)["native_pids"]) in old["native_pids"]
    cold = client(ctx)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    # First content operation after the owned restart is selective, without resume.
    assert_shell_selection(cold, records)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert_owned_history_files(ctx)
    assert requests(ctx) == []
    assert :ok = Session.close(cold)
  end

  test "omitted null large zero and bounded timeouts preserve native shell semantics", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)

    cases = [
      {"omitted", %{}, false},
      {"nullable", %{"timeoutMs" => nil}, false},
      {"large", %{"timeoutMs" => 28_800_000}, false},
      {"zero", %{"timeoutMs" => 0}, true},
      {"bounded", %{"timeoutMs" => 500}, true}
    ]

    for {name, options, expires} <- cases do
      mode = if expires, do: "held", else: "quick"
      shell = start_shell(pid, thread, command(ctx, name, mode), options)
      {completed, events} = finish_shell(pid, shell)

      if expires do
        assert completed["status"] == "failed" and completed["exitCode"] == -1
        assert completed["aggregatedOutput"] =~ "Timeout"

        if name == "bounded" do
          assert completed["aggregatedOutput"] =~ "owned-ready:bounded"
          marker(ctx, name)
        end
      else
        assert completed["status"] == "completed" and completed["exitCode"] == 0
        assert completed["aggregatedOutput"] == "owned-output:#{name}\n"
        marker(ctx, name)
      end

      assert notification(events, "turn/completed", &(&1["turn"]["id"] == shell.turn))["turn"][
               "status"
             ] == "completed"

      if File.exists?(marker_path(ctx, name)), do: assert_gone(ctx, name)
    end

    assert requests(ctx) == []
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
  end

  test "native empty negative and missing-thread errors and driver type validation cause no execution",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)

    for text <- ["", "  \n \t"] do
      assert upstream_error(pid, "thread/shellCommand", %{"threadId" => thread, "command" => text}) ==
               %{
                 "code" => -32_600,
                 "message" => "command must not be empty"
               }
    end

    base = %{"threadId" => thread, "command" => command(ctx, "must-not-run", "quick")}

    assert upstream_error(pid, "thread/shellCommand", Map.put(base, "timeoutMs", -1)) == %{
             "code" => -32_602,
             "message" => "thread/shellCommand timeoutMs must be non-negative, got -1"
           }

    for value <- [1.5, "1000", 18_446_744_073_709_551_615] do
      assert {:error, %Error{code: :schema_violation}} =
               Session.request(pid, "thread/shellCommand", Map.put(base, "timeoutMs", value))
    end

    missing = "00000000-0000-0000-0000-000000000000"

    assert upstream_error(pid, "thread/shellCommand", Map.put(base, "threadId", missing))[
             "message"
           ] == "thread not found: #{missing}"

    assert call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})["thread"][
             "status"
           ] == %{"type" => "idle"}

    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] in ["turn/started", "item/started"]))
    assert Path.wildcard(Path.join(ctx.root, "commands/*.json")) == []
    assert requests(ctx) == []
    assert :ok = Session.close(pid)
  end

  @tag scenario: "active"
  test "auxiliary shell shares the active turn while its approval stays unresolved", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    {turn, approval, events} = active(pid, thread)
    shell = start_shell(pid, thread, command(ctx, "auxiliary", "quick"))
    assert shell.turn == turn
    {completed, events} = finish_item(pid, shell, events ++ shell.events)
    assert completed["status"] == "completed" and completed["exitCode"] == 0
    assert_active(pid, thread, turn, events)
    assert Session.status(pid).interactions == 1
    assert length(requests(ctx)) == 1
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "decline"}})
    events = finish_turn(pid, turn, events)

    assert notification(events, "turn/completed", &(&1["turn"]["id"] == turn))["turn"]["status"] ==
             "completed"

    assert item(events, "item/completed", "owned-held-agent-command")["status"] == "declined"
    assert length(requests(ctx)) == 2
    marker(ctx, "auxiliary")
    assert_gone(ctx, "auxiliary")
    assert :ok = Session.close(pid)
  end

  @tag scenario: "active"
  test "auxiliary shell timeout does not complete or replace the original active turn", ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    {turn, approval, events} = active(pid, thread)

    shell =
      start_shell(pid, thread, command(ctx, "auxiliary-timeout", "held"), %{"timeoutMs" => 500})

    assert shell.turn == turn
    {completed, events} = finish_item(pid, shell, events ++ shell.events)
    assert completed["status"] == "failed" and completed["exitCode"] == -1
    assert completed["aggregatedOutput"] =~ "Timeout"
    assert completed["aggregatedOutput"] =~ "owned-ready:auxiliary-timeout"
    assert_active(pid, thread, turn, events)
    assert Session.status(pid).interactions == 1
    assert length(requests(ctx)) == 1
    assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "decline"}})
    finish_turn(pid, turn, events)
    assert length(requests(ctx)) == 2
    marker(ctx, "auxiliary-timeout")
    assert_gone(ctx, "auxiliary-timeout")
    assert :ok = Session.close(pid)
  end

  test "persisted shell output survives native restart while history filters command execution items",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    shell = start_shell(pid, thread, command(ctx, "history", "quick"))
    finish_shell(pid, shell)
    marker(ctx, "history")
    assert_gone(ctx, "history")
    assert_history(pid, thread)
    paths = Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl"))

    assert Enum.any?(paths, &(File.read!(&1) =~ "owned-output:history")),
           "persisted native user-shell output"

    assert :ok = Session.close(pid)
    old = state(ctx)
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"restart" => true}))
    await(fn -> ready?(ctx, 2) end, "explicit native restart")
    for os_pid <- old["native_pids"], do: refute(File.exists?("/proc/#{os_pid}"))
    replacement = client(ctx)

    resumed =
      call(replacement, "thread/resume", %{"threadId" => thread, "historyMode" => "legacy"})[
        "thread"
      ]

    assert resumed["id"] == thread
    assert length(resumed["turns"]) == 1
    assert_no_commands(resumed["turns"])
    assert_history(replacement, thread)
    forked = call(replacement, "thread/fork", %{"threadId" => thread})["thread"]
    assert length(forked["turns"]) == 1
    assert_no_commands(forked["turns"])
    assert length(Path.wildcard(Path.join(ctx.root, "commands/*.json"))) == 1
    assert requests(ctx) == []
    assert :ok = Session.close(replacement)
  end

  test "borrowed reconnect after acknowledgement preserves running shell and does not replay execution",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx)
    shell = start_shell(pid, thread, command(ctx, "reconnect", "held"))
    events = collect(pid, &(output(&1, shell.item) =~ "owned-ready:reconnect\n"), shell.events)
    marker = marker(ctx, "reconnect")
    generation = Session.status(pid).generation
    native = List.last(state(ctx)["native_pids"])
    assert :ok = Session.reconnect(pid)
    assert Session.status(pid).generation == generation + 1
    assert Session.uncertain_operations(pid) == []
    assert File.exists?("/proc/#{marker["pid"]}") and File.exists?("/proc/#{native}")
    initialize(pid)

    resumed =
      call(pid, "thread/resume", %{"threadId" => thread, "historyMode" => "legacy"})["thread"]

    assert resumed["id"] == thread
    assert Enum.any?(resumed["turns"], &(&1["id"] == shell.turn and &1["status"] == "inProgress"))
    assert length(Path.wildcard(Path.join(ctx.root, "commands/*.json"))) == 1
    release(ctx, "reconnect")
    {completed, events} = finish_shell(pid, shell, events)
    assert completed["exitCode"] == 0
    assert completed["aggregatedOutput"] == "owned-ready:reconnect\nowned-done:reconnect\n"

    assert Enum.count(
             events,
             &(&1.wire["method"] == "item/started" and
                 &1.wire["params"]["item"]["id"] == shell.item)
           ) == 1

    assert_gone(ctx, "reconnect")
    assert requests(ctx) == []
    assert :ok = Session.close(pid)
    assert File.exists?("/proc/#{native}") and File.exists?(ctx.socket)
    survivor = client(ctx)
    assert thread in call(survivor, "thread/loaded/list", %{})["data"]
    assert :ok = Session.close(survivor)
  end

  defp client(ctx) do
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

    initialize(pid)
    pid
  end

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_user_shell", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })
  end

  defp thread(pid, ctx),
    do:
      call(pid, "thread/start", %{"cwd" => ctx.workspace, "historyMode" => "legacy"})["thread"][
        "id"
      ]

  defp command(ctx, name, mode) do
    "exec " <>
      Enum.map_join(
        [ctx.python, @script, "--command", "--root", ctx.root, "--name", name, "--mode", mode],
        " ",
        &shell_quote/1
      )
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp start_shell(pid, thread, command, extra \\ %{}) do
    assert call(
             pid,
             "thread/shellCommand",
             Map.merge(%{"threadId" => thread, "command" => command}, extra)
           ) == %{}

    events =
      collect(pid, fn events ->
        notification(
          events,
          "item/started",
          &(&1["threadId"] == thread and &1["item"]["source"] == "userShell")
        )
      end)

    params =
      notification(
        events,
        "item/started",
        &(&1["threadId"] == thread and &1["item"]["source"] == "userShell")
      )

    assert params["item"]["type"] == "commandExecution"
    %{thread: thread, turn: params["turnId"], item: params["item"]["id"], events: events}
  end

  defp finish_shell(pid, shell, events \\ nil) do
    {completed, events} = finish_item(pid, shell, events || shell.events)
    {completed, finish_turn(pid, shell.turn, events)}
  end

  defp finish_item(pid, shell, events) do
    events = collect(pid, &item(&1, "item/completed", shell.item), events)
    params = notification(events, "item/completed", &(&1["item"]["id"] == shell.item))
    assert params["threadId"] == shell.thread and params["turnId"] == shell.turn
    assert params["item"]["source"] == "userShell"
    {params["item"], events}
  end

  defp finish_turn(pid, turn, events),
    do:
      collect(
        pid,
        &notification(&1, "turn/completed", fn params -> params["turn"]["id"] == turn end),
        events
      )

  defp active(pid, thread) do
    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "Owned synthetic approval barrier"}]
      })["turn"]["id"]

    events = collect(pid, &Enum.any?(&1, fn event -> event.kind == :server_request end))
    approval = Enum.find(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/commandExecution/requestApproval"
    assert approval.wire["params"]["threadId"] == thread
    assert approval.wire["params"]["turnId"] == turn
    {turn, approval, events}
  end

  defp assert_active(pid, thread, turn, events) do
    assert Enum.count(events, &(&1.wire["method"] == "turn/started")) == 1
    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    current = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]
    assert Enum.any?(current["turns"], &(&1["id"] == turn and &1["status"] == "inProgress"))
  end

  defp assert_history(pid, thread) do
    turns =
      call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]["turns"]

    assert length(turns) == 1
    assert_no_commands(turns)

    turns =
      call(pid, "thread/turns/list", %{"threadId" => thread, "sortDirection" => "asc"})["data"]

    assert length(turns) == 1
    assert_no_commands(turns)
  end

  defp expected_account_shell(ctx) do
    # The owned fixture uses --map-root-user, so the native passwd lookup is
    # for namespace UID 0. SHELL and the outer test user's UID are not its input.
    assert {encoded, 0} =
             System.cmd(ctx.python, [
               "-c",
               "import json,pwd; print(json.dumps(pwd.getpwuid(0).pw_shell))"
             ])

    shell = JSON.decode!(String.trim(encoded))

    assert is_binary(shell) and Path.type(shell) == :absolute and File.regular?(shell),
           "BLOCKED_ENV: independent oracle requires a regular absolute account shell"

    assert Path.basename(shell) in ~w(sh bash zsh),
           "BLOCKED_ENV: independent oracle requires a POSIX account shell"

    assert Regex.match?(~r|^[A-Za-z0-9_/.+@:-]+$|, shell),
           "BLOCKED_ENV: independent shell path requires shlex-safe characters"

    shell
  end

  defp assert_owned_history_files(ctx) do
    assert Enum.sort(File.ls!(ctx.workspace)) == ["owned-dir", "owned.txt"]
    assert File.ls!(Path.join(ctx.workspace, "owned-dir")) == ["needle.txt"]
    assert File.read!(Path.join(ctx.workspace, "owned.txt")) == "owned-history\n"
    assert File.read!(Path.join(ctx.workspace, "owned-dir/needle.txt")) == "owned-history\n"
  end

  defp assert_shell_selection(pid, records) do
    for %{"query" => query, "entry" => entry} <- records do
      assert call(pid, "thread/items/read", query) === %{"data" => [entry]}
      [item_id] = query["itemIds"]

      assert call(pid, "thread/items/read", %{
               query
               | "itemIds" => ["owned-absent-shell-item", item_id, item_id]
             }) === %{"data" => [entry]}

      assert call(pid, "thread/items/read", %{
               query
               | "itemIds" => ["owned-absent-shell-item"]
             }) === %{"data" => []}

      assert call(pid, "thread/items/read", %{query | "turnId" => "owned-absent-turn"}) ===
               %{"data" => []}
    end

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))

    refute Enum.any?(remaining, fn event ->
             event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/started",
               "item/completed"
             ]
           end)
  end

  defp assert_no_commands(turns),
    do:
      assert(
        Enum.all?(turns, fn turn ->
          Enum.all?(turn["items"], &(&1["type"] != "commandExecution"))
        end)
      )

  defp release(ctx, name), do: File.write!(Path.join(ctx.root, "releases/#{name}"), "release\n")
  defp requests(ctx), do: ctx.root |> Path.join("requests.json") |> File.read!() |> JSON.decode!()
  defp state(ctx), do: ctx.root |> Path.join("state.json") |> File.read!() |> JSON.decode!()
  defp marker_path(ctx, name), do: Path.join(ctx.root, "commands/#{name}.json")

  defp marker(ctx, name) do
    value = marker_path(ctx, name) |> File.read!() |> JSON.decode!()
    assert value["parent_namespace"] == ctx.parent_namespace
    assert value["namespace"] == state(ctx)["namespace"]
    assert value["namespace"] != ctx.parent_namespace
    assert value["interfaces"] == ["lo"]
    refute value["default_route"]
    assert value["cwd"] == ctx.workspace
    value
  end

  defp assert_gone(ctx, name) do
    value = marker(ctx, name)
    await(fn -> not File.exists?("/proc/#{value["pid"]}") end, "owned user-shell command exit")
  end

  defp ready?(ctx, generation) do
    path = Path.join(ctx.root, "state.json")

    if File.exists?(path) do
      value = state(ctx)
      value["ready"] and value["generation"] == generation and File.exists?(ctx.socket)
    else
      false
    end
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end

  defp item(events, method, id) do
    case notification(events, method, &(&1["item"]["id"] == id)) do
      nil -> nil
      params -> params["item"]
    end
  end

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp output(events, id),
    do:
      events
      |> Enum.filter(
        &(&1.wire["method"] == "item/commandExecution/outputDelta" and
            &1.wire["params"]["itemId"] == id)
      )
      |> Enum.map_join(& &1.wire["params"]["delta"])

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || now() + 5_000
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    if predicate.(acc) do
      acc
    else
      assert now() < deadline,
             "native user-shell observable barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, message, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, message

      receive do
      after
        10 -> :ok
      end

      await(predicate, message, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
