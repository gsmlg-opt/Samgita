defmodule SamgitaCodexDriver.NativeHookLifecycleProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_hook_lifecycle_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @prompt "Owned synthetic hook lifecycle input"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    tools =
      Map.new(["python3", "ip", "unshare"], fn name ->
        path = System.find_executable(name)
        assert is_binary(path), "BLOCKED_ENV: #{name} required"
        {name, path}
      end)

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-hooks-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    for dir <- ["home", "codex", "workspace", "tmp", "bin"], do: File.mkdir!(Path.join(root, dir))
    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    File.write!(Path.join(root, "provider-errors.json"), "[]")

    ctx = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      scenario: tags.hook_scenario,
      parent_netns: File.read_link!("/proc/self/ns/net"),
      parent_userns: File.read_link!("/proc/self/ns/user")
    }

    # Registered before the Session cleanup so LIFO cleanup reaps before checking.
    on_exit(fn ->
      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)
        pids = Enum.map(["native_pid", "controller_pid", "namespace_owner_pid"], &proof[&1])

        hook_pids =
          for event <- ["SessionStart", "UserPromptSubmit"],
              File.exists?(Path.join(root, event <> ".json")),
              do: read_json(ctx, event <> ".json")["pid"]

        for os_pid <- pids ++ hook_pids do
          await(
            fn -> not File.exists?("/proc/#{os_pid}") end,
            "owned hook fixture process reaping"
          )
        end
      end
    end)

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: tools["python3"],
             args: [
               @script,
               "--root",
               root,
               "--codex",
               Path.expand(binary),
               "--ip",
               tools["ip"],
               "--unshare",
               tools["unshare"],
               "--scenario",
               tags.hook_scenario
             ],
             cwd: ctx.workspace,
             inherit_env: [],
             env: %{
               "HOME" => Path.join(root, "home"),
               "CODEX_HOME" => Path.join(root, "codex"),
               "TMPDIR" => Path.join(root, "tmp"),
               "PATH" => "/usr/bin:/bin",
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off",
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    await(fn -> File.exists?(Path.join(root, "state.json")) end, "private hook fixture startup")
    proof = state(ctx)
    assert proof["parent"] == ctx.parent_netns and proof["child"] != ctx.parent_netns
    assert proof["parent_user"] == ctx.parent_userns and proof["child_user"] != ctx.parent_userns
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_hooks", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    Map.put(ctx, :pid, pid)
  end

  for scenario <- ["success", "untrusted", "disabled", "blocked", "failed", "stopped"] do
    @tag hook_scenario: scenario
    test "native fixed #{scenario} hooks preserve lifecycle and trust boundaries", ctx do
      pid = ctx.pid
      hooks = hooks(pid, ctx)
      assert Enum.all?(hooks, &(&1["trustStatus"] == "untrusted" and &1["enabled"]))
      assert read_json(ctx, "requests.json") == []
      assert {:ok, registration_events} = Session.drain(pid)
      assert lifecycle(registration_events) == []
      refute File.exists?(Path.join(ctx.root, "SessionStart.json"))
      refute File.exists?(Path.join(ctx.root, "UserPromptSubmit.json"))

      if ctx.scenario != "untrusted" do
        states =
          Map.new(hooks, fn hook ->
            {hook["key"],
             %{"trusted_hash" => hook["currentHash"], "enabled" => ctx.scenario != "disabled"}}
          end)

        call(pid, "config/batchWrite", %{
          "edits" => [
            %{"keyPath" => "hooks.state", "value" => states, "mergeStrategy" => "upsert"}
          ],
          "reloadUserConfig" => true
        })

        approved = hooks(pid, ctx)
        assert Enum.all?(approved, &(&1["trustStatus"] == "trusted"))
        assert Enum.all?(approved, &(&1["enabled"] == (ctx.scenario != "disabled")))
      end

      thread =
        call(pid, "thread/start", %{
          "cwd" => ctx.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request"
        })["thread"]["id"]

      assert {:ok, thread_events} = Session.drain(pid)
      assert lifecycle(thread_events) == []
      refute File.exists?(Path.join(ctx.root, "SessionStart.json"))
      refute File.exists?(Path.join(ctx.root, "UserPromptSubmit.json"))
      assert read_json(ctx, "requests.json") == []

      turn =
        call(pid, "turn/start", %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => @prompt}]
        })["turn"]["id"]

      events =
        collect(pid, fn events ->
          Enum.any?(events, fn event ->
            event.wire["method"] == "turn/completed" and
              event.wire["params"]["turn"]["id"] == turn
          end)
        end)

      # Read native thread metadata after the terminal event; no polling delay proves absence.
      read = call(pid, "thread/read", %{"threadId" => thread})["thread"]
      assert read["id"] == thread

      [terminal] =
        for event <- events,
            event.wire["method"] == "turn/completed",
            event.wire["params"]["turn"]["id"] == turn,
            do: event.wire["params"]

      assert terminal["threadId"] == thread
      assert {:ok, tail} = Session.drain(pid)
      events = events ++ tail
      refute Enum.any?(events, &(&1.kind == :server_request))
      for event <- lifecycle(events), do: assert(event.kind == :notification)
      assert Session.uncertain_operations(pid) == []
      assert read_json(ctx, "provider-errors.json") == []

      if ctx.scenario in ["untrusted", "disabled"] do
        assert lifecycle(events) == []
        refute File.exists?(Path.join(ctx.root, "SessionStart.json"))
        refute File.exists?(Path.join(ctx.root, "UserPromptSubmit.json"))
        assert length(read_json(ctx, "requests.json")) == 1
      else
        expected =
          %{
            "success" => "completed",
            "blocked" => "blocked",
            "failed" => "failed",
            "stopped" => "stopped"
          }[ctx.scenario]

        assert length(lifecycle(events)) == 4
        assert_pair(events, hooks, ctx, thread, turn, "sessionStart", "completed")
        done = assert_pair(events, hooks, ctx, thread, turn, "userPromptSubmit", expected)
        assert done["entries"] == expected_entries(ctx.scenario)

        for event <- ["SessionStart", "UserPromptSubmit"] do
          record = read_json(ctx, event <> ".json")
          assert record["event"] == event and record["scenario"] == ctx.scenario
          assert record["session_id"] == thread and record["namespace"] == state(ctx)["child"]
          assert record["turn_id"] == if(event == "SessionStart", do: nil, else: turn)
          refute File.exists?("/proc/#{record["pid"]}")
        end

        expected_calls = if ctx.scenario in ["blocked", "stopped"], do: 0, else: 1
        assert length(read_json(ctx, "requests.json")) == expected_calls
      end

      assert :ok = Session.close(pid)
    end
  end

  defp hooks(pid, ctx) do
    assert [entry] = call(pid, "hooks/list", %{"cwds" => [ctx.workspace]})["data"]
    assert entry["cwd"] == ctx.workspace and entry["warnings"] == [] and entry["errors"] == []

    assert Enum.sort(Enum.map(entry["hooks"], & &1["eventName"])) == [
             "sessionStart",
             "userPromptSubmit"
           ]

    for hook <- entry["hooks"], do: assert_hook(hook, ctx)

    entry["hooks"]
  end

  defp assert_hook(hook, ctx) do
    event = if hook["eventName"] == "sessionStart", do: "SessionStart", else: "UserPromptSubmit"
    assert hook["command"] == state(ctx)["commands"][event]
    assert hook["handlerType"] == "command" and hook["async"] == false
    assert hook["sourcePath"] == Path.join(ctx.root, "codex/config.toml")
    assert hook["source"] == "user" and hook["isManaged"] == false and hook["pluginId"] == nil
    assert is_binary(hook["key"]) and byte_size(hook["key"]) > 0
    assert is_binary(hook["currentHash"]) and byte_size(hook["currentHash"]) > 0
    assert hook["timeoutSec"] == 5
    assert hook["statusMessage"] == "Owned synthetic #{event}"
  end

  defp assert_pair(events, hooks, ctx, thread, turn, event_name, expected_status) do
    [started] =
      for event <- events,
          event.wire["method"] == "hook/started",
          event.wire["params"]["run"]["eventName"] == event_name,
          do: event.wire["params"]

    [completed] =
      for event <- events,
          event.wire["method"] == "hook/completed",
          event.wire["params"]["run"]["eventName"] == event_name,
          do: event.wire["params"]

    for notice <- [started, completed],
        do: assert(notice["threadId"] == thread and notice["turnId"] == turn)

    first = started["run"]
    last = completed["run"]
    hook = Enum.find(hooks, &(&1["eventName"] == event_name))
    assert_run_identity(first, last, hook, ctx, event_name)
    assert_run_lifecycle(first, last, expected_status)

    assert Enum.find_index(
             events,
             &(&1.wire["method"] == "hook/started" and &1.wire["params"] == started)
           ) <
             Enum.find_index(
               events,
               &(&1.wire["method"] == "hook/completed" and &1.wire["params"] == completed)
             )

    last
  end

  defp assert_run_identity(first, last, hook, ctx, event_name) do
    identity = [
      "id",
      "eventName",
      "handlerType",
      "executionMode",
      "scope",
      "sourcePath",
      "source",
      "displayOrder",
      "statusMessage"
    ]

    assert Map.take(first, identity) == Map.take(last, identity)
    assert first["handlerType"] == "command" and first["executionMode"] == "sync"

    assert first["source"] == "user" and
             first["sourcePath"] == Path.join(ctx.root, "codex/config.toml")

    assert first["displayOrder"] == hook["displayOrder"]
    label = if event_name == "sessionStart", do: "session-start", else: "user-prompt-submit"
    assert first["id"] == "#{label}:#{hook["displayOrder"]}:#{hook["sourcePath"]}"
    assert first["scope"] == if(event_name == "sessionStart", do: "thread", else: "turn")
  end

  defp assert_run_lifecycle(first, last, expected_status) do
    assert first["status"] == "running" and first["entries"] == []
    assert first["completedAt"] == nil and first["durationMs"] == nil
    assert is_integer(first["startedAt"])
    assert last["status"] == expected_status and is_integer(last["startedAt"])
    assert is_integer(last["completedAt"]) and last["completedAt"] >= last["startedAt"]
    assert is_integer(last["durationMs"]) and last["durationMs"] >= 0
  end

  defp expected_entries("blocked"),
    do: [%{"kind" => "feedback", "text" => "Owned synthetic hook denied input"}]

  defp expected_entries("failed"), do: [%{"kind" => "error", "text" => "hook exited with code 7"}]

  defp expected_entries("stopped"),
    do: [%{"kind" => "stop", "text" => "Owned synthetic hook stopped input"}]

  defp expected_entries("success"), do: []

  defp lifecycle(events),
    do: Enum.filter(events, &(&1.wire["method"] in ["hook/started", "hook/completed"]))

  defp read_json(ctx, file), do: ctx.root |> Path.join(file) |> File.read!() |> JSON.decode!()
  defp state(ctx), do: read_json(ctx, "state.json")

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || now() + 5_000
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    if predicate.(acc) do
      acc
    else
      assert Session.status(pid).phase == :ready
      assert now() < deadline, "native hook lifecycle deadline: #{inspect(Session.status(pid))}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, gap}} -> flunk("native hook event gap: #{inspect(gap)}")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, description, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    unless predicate.() do
      assert now() < deadline, description

      receive do
      after
        20 -> :ok
      end

      await(predicate, description, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
