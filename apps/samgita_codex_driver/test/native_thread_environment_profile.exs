defmodule SamgitaCodexDriver.NativeThreadEnvironmentProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_thread_environment
  @moduletag timeout: 90_000
  @script Path.expand("../../../scripts/codex/isolated_thread_environment_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @token "synthetic-isolated-executor-credential-canary"
  @selected "selected-环境λ"
  @connected "thread/environment/connected"
  @disconnected "thread/environment/disconnected"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-thread-environment-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)

    ctx = %{
      root: root,
      binary: Path.expand(binary),
      parent_netns: File.read_link!("/proc/self/ns/net"),
      parent_userns: File.read_link!("/proc/self/ns/user")
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "isolated-environment-journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
            do: await(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert length(events(ctx, "native_started")) == length(events(ctx, "native_closed"))
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  test "selected threads receive actual connect disconnect and recovery without state or work replay",
       ctx do
    pid = start(ctx)
    assert add(ctx, pid, @selected) == %{}
    assert add(ctx, pid, "unselected") == %{}
    assert call(pid, "environment/status", %{"environmentId" => @selected})["status"] == "pending"

    first =
      thread(ctx, pid, [
        %{
          "environmentId" => @selected,
          "cwd" => executor_cwd(ctx),
          "runtimeWorkspaceRoots" => [executor_cwd(ctx), executor_cwd(ctx)]
        }
      ])

    assert connection_rows(drain(pid), @connected) == []
    control(ctx, "resume_proxy")
    first_events = collect(pid, @connected, [first])
    assert connection_rows(first_events, @connected) == [row(first)]
    assert_info(ctx, pid)

    # Creating this second listener while already connected must not replay
    # the first connection state. A later disconnect is the causal barrier.
    _ = drain(pid)
    second = thread(ctx, pid, [%{"environmentId" => @selected, "cwd" => executor_cwd(ctx)}])
    detached = thread(ctx, pid, [])
    control(ctx, "pause_proxy")
    down_events = collect(pid, @disconnected, [first, second])
    assert connection_rows(down_events, @connected) == []

    assert sorted(connection_rows(down_events, @disconnected)) ==
             sorted([row(first), row(second)])

    refute Enum.any?(connection_rows(down_events, @disconnected), &(&1["threadId"] == detached))

    control(ctx, "resume_proxy")
    # This is an explicit native metadata operation that may request recovery.
    # It is not an execution retry or another environment/add.
    assert_info(ctx, pid)
    recovered = collect(pid, @connected, [first, second])
    assert sorted(connection_rows(recovered, @connected)) == sorted([row(first), row(second)])

    assert call(pid, "environment/status", %{"environmentId" => @selected}) == %{
             "status" => "ready"
           }

    assert inputs(ctx, "environment/add") == 2 and inputs(ctx, "thread/start") == 3

    control(ctx, "stop_executor")
    stopped = collect(pid, @disconnected, [first, second])
    assert sorted(connection_rows(stopped, @disconnected)) == sorted([row(first), row(second)])
    assert connection_rows(stopped, @connected) == []
    status = wait_status(pid, "disconnected")

    assert status["status"] == "disconnected" and is_binary(status["error"]) and
             status["error"] != ""

    failure = error(pid, "environment/info", %{"environmentId" => @selected})
    assert failure["code"] == -32_603
    assert failure["message"] =~ "failed to get info for environment `#{@selected}`"

    for id <- [first, second, detached] do
      assert error(pid, "thread/read", %{"threadId" => id, "includeTurns" => true}) == %{
               "code" => -32_601,
               "message" => "list_turns is not supported yet"
             }

      result = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})
      assert result["thread"]["id"] == id and result["thread"]["turns"] == []

      expected =
        if id == detached,
          do: [],
          else: [
            %{
              "environmentId" => @selected,
              "cwd" => executor_cwd(ctx),
              "runtimeWorkspaceRoots" => [executor_cwd(ctx)]
            }
          ]

      assert result["thread"]["environments"] == expected
    end

    assert inputs(ctx, "environment/add") == 2 and inputs(ctx, "thread/start") == 3

    assert Enum.all?(
             events(ctx, "exec_rpc"),
             &(&1["method"] in ~w(initialize initialized environment/info environment/status))
           )

    assert length(events(ctx, "executor_stopped")) == 1
    finish(ctx, pid, [first, second, detached])
  end

  test "experimental field gate rejects native thread attachment before creating a thread", ctx do
    pid = start(ctx, false)
    params = thread_params(ctx, [])
    before = inputs(ctx, "thread/start")

    assert {:error, %Error{code: :experimental_api_required, uncertain: false}} =
             Session.request(pid, "thread/start", params)

    assert inputs(ctx, "thread/start") == before

    assert error(pid, "thread/start", params, validation: :wire) == %{
             "code" => -32_600,
             "message" => "thread/start.environments requires experimentalApi capability"
           }

    assert events(ctx, "exec_rpc") == []
    assert events(ctx, "proxy_connected") == []
    assert connection_rows(drain(pid), @connected) == []
    finish(ctx, pid, [])
  end

  test "unregistered selection rejects before thread creation and sends no connection lifecycle",
       ctx do
    pid = start(ctx)
    params = thread_params(ctx, [%{"environmentId" => "missing", "cwd" => executor_cwd(ctx)}])

    assert error(pid, "thread/start", params) == %{
             "code" => -32_600,
             "message" => "unknown turn environment id `missing`"
           }

    assert events(ctx, "exec_rpc") == []
    assert events(ctx, "proxy_connected") == []
    received = drain(pid)
    assert connection_rows(received, @connected) == []
    assert connection_rows(received, @disconnected) == []
    finish(ctx, pid, [])
  end

  defp start(ctx, experimental \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root],
             inherit_env: [],
             cwd: ctx.root,
             env: %{
               "HOME" => ctx.root,
               "CODEX_HOME" => Path.join(ctx.root, "app"),
               "TMPDIR" => ctx.root,
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_thread_environment", "version" => "1"},
               %{"experimentalApi" => experimental}
             )

    await(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp add(ctx, pid, environment) do
    [started] = events(ctx, "native_started")

    call(pid, "environment/add", %{
      "environmentId" => environment,
      "execServerUrl" => started["executor_url"],
      "authBearerToken" => @token,
      "connectTimeoutMs" => 15_000
    })
  end

  defp thread_params(ctx, environments),
    do: %{
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "cwd" => Path.join(ctx.root, "workspace"),
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "ephemeral" => false,
      "environments" => environments
    }

  defp thread(ctx, pid, environments) do
    result = call(pid, "thread/start", thread_params(ctx, environments))
    assert result["thread"]["turns"] == []

    expected =
      for environment <- environments,
          do: %{
            "environmentId" => environment["environmentId"],
            "cwd" => executor_cwd(ctx),
            "runtimeWorkspaceRoots" => [executor_cwd(ctx)]
          }

    assert result["thread"]["environments"] == expected
    result["thread"]["id"]
  end

  defp executor_cwd(ctx), do: Path.join(ctx.root, "executor-workspace")
  defp row(id), do: %{"threadId" => id, "environmentId" => @selected}
  defp sorted(rows), do: Enum.sort_by(rows, & &1["threadId"])

  defp connection_rows(received, method),
    do: for(event <- received, event.wire["method"] == method, do: event.wire["params"])

  defp assert_info(ctx, pid) do
    result = call(pid, "environment/info", %{"environmentId" => @selected})
    assert result["cwd"] == "file://" <> executor_cwd(ctx)
    assert is_binary(result["shell"]["name"]) and is_binary(result["shell"]["path"])
  end

  defp wait_status(pid, wanted) do
    await(fn ->
      status = call(pid, "environment/status", %{"environmentId" => @selected})
      if status["status"] == wanted, do: status
    end)
  end

  defp control(ctx, action) do
    id = System.unique_integer([:positive])
    path = Path.join(ctx.root, "control.json")
    File.write!(path <> ".pending", JSON.encode!(%{"id" => id, "action" => action}))
    File.rename!(path <> ".pending", path)
    await(fn -> Enum.any?(events(ctx, "control_completed"), &(&1["id"] == id)) end)
  end

  defp collect(pid, method, ids),
    do: collect(pid, method, ids, [], System.monotonic_time(:millisecond) + 10_000)

  defp collect(pid, method, ids, received, deadline) do
    received = received ++ drain(pid)
    rows = connection_rows(received, method)
    actual = Enum.map(rows, & &1["threadId"])
    assert length(actual) <= length(ids)
    assert Enum.all?(rows, &(&1["environmentId"] == @selected))

    if Enum.sort(actual) == Enum.sort(ids) do
      received
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Native thread environment event deadline"

      Process.sleep(10)
      collect(pid, method, ids, received, deadline)
    end
  end

  defp drain(pid) do
    assert {:ok, received} = Session.drain(pid, 10_000)

    refute Enum.any?(
             received,
             &(&1.kind == :server_request or &1.wire["method"] == "turn/started")
           )

    received
  end

  defp finish(ctx, pid, ids) do
    loaded = call(pid, "thread/loaded/list", %{})
    assert Enum.sort(loaded["data"]) == Enum.sort(ids) and loaded["nextCursor"] == nil
    assert Session.status(pid).phase == :ready and Session.status(pid).interactions == 0
    assert Session.uncertain_operations(pid) == []
    assert inputs(ctx, "turn/start") == 0
    _ = drain(pid)
    assert :ok = Session.close(pid)
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == ctx.parent_netns and proof["child"] != ctx.parent_netns
    assert proof["parent_user"] == ctx.parent_userns and proof["child_user"] != ctx.parent_userns
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]

    assert events(ctx, "native_auth_probe") |> Enum.map(&{&1["credential"], &1["status"]}) ==
             [{"absent", 401}, {"wrong", 401}, {"valid", 101}]

    for name <- ~w(fixture_error unexpected_http forbidden_exec_rpc),
        do: assert(events(ctx, name) == [])

    assert [%{"children_reaped" => true, "workers_stopped" => true, "redaction_checked" => true}] =
             events(ctx, "resources_closed")

    assert length(events(ctx, "native_closed")) == 1

    for started <- events(ctx, "native_started"),
        key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
        do: await(fn -> not File.exists?("/proc/#{started[key]}") end)
  end

  defp call(pid, method, params) do
    id = "owned-thread-environment-#{System.unique_integer([:positive])}"

    reply = Session.request(pid, method, params, id: id)

    errors =
      case reply do
        {:error, %Error{wire: %{"error" => failure}}} -> Map.take(failure, ["code", "message"])
        _ -> nil
      end

    assert match?({:ok, %{"id" => ^id, "result" => _}}, reply),
           "Native #{method} failed: #{inspect(errors)}"

    {:ok, %{"result" => result}} = reply

    result
  end

  defp error(pid, method, params, options \\ []) do
    id = "owned-thread-environment-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => failure}}} =
             Session.request(pid, method, params, Keyword.put(options, :id, id))

    failure
  end

  defp journal(ctx),
    do:
      ctx.root |> Path.join("isolated-environment-journal.json") |> File.read!() |> JSON.decode!()

  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp inputs(ctx, method), do: Enum.count(events(ctx, "native_input"), &(&1["method"] == method))
  defp await(predicate, remaining \\ 1_000)
  defp await(_predicate, 0), do: flunk("Owned thread environment observation deadline")

  defp await(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      await(predicate, remaining - 1)
    end
  end
end
