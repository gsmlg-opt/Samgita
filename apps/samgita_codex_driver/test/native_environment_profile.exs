defmodule SamgitaCodexDriver.NativeEnvironmentProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_environment
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_environment_fixture.py", __DIR__)
  @token "synthetic-isolated-executor-credential-canary"

  # Explicit Linux profile: missing namespace prerequisites fail, never skip.
  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-isolated-environment-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, binary: binary, journal: Path.join(root, "isolated-environment-journal.json")}
  end

  test "native executor registration acknowledges before verified readiness and identity", ctx do
    pid = start(ctx)
    assert add(ctx, pid, "approved") == %{}
    assert_ready(pid, "approved")
    assert_info(ctx, pid, "approved")
    assert inputs(ctx, "environment/add") == 1
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "native authentication rejects absent and wrong tokens then retains corrected auth on reconnect",
       ctx do
    pid = start(ctx)

    for {id, credential} <- [{"anonymous", nil}, {"wrong", "incorrect-synthetic-token"}] do
      assert add(ctx, pid, id, credential) == %{}
      assert wait_status(pid, id, "disconnected")["error"] =~ "401"
      assert upstream_error(pid, "environment/info", %{"environmentId" => id})["message"] =~ "401"
    end

    # Credentials are immutable connection options. Correcting them uses the
    # native explicit upsert, then a transport reconnect needs no further add.
    assert add(ctx, pid, "wrong") == %{}
    assert_ready(pid, "wrong")
    assert_info(ctx, pid, "wrong")
    connections = count(ctx, "proxy_connected")
    control(ctx, "disconnect")
    await_connections(ctx, connections, System.monotonic_time(:millisecond) + 10_000)
    assert_ready(pid, "wrong")
    assert_info(ctx, pid, "wrong")
    assert count(ctx, "proxy_connected") > connections
    assert inputs(ctx, "environment/add") == 3
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "invalid replacement preserves a registered environment and duplicate add is explicit upsert",
       ctx do
    pid = start(ctx)
    assert add(ctx, pid, "approved") == %{}
    assert_ready(pid, "approved")
    params = registration(ctx, "approved") |> Map.put("execServerUrl", "none")
    assert upstream_error(pid, "environment/add", params)["code"] == -32_600
    assert_info(ctx, pid, "approved")
    assert_ready(pid, "approved")

    assert upstream_error(pid, "environment/info", %{"environmentId" => "unknown"}) == %{
             "code" => -32_600,
             "message" => "unknown environment id `unknown`"
           }

    assert call(pid, "environment/status", %{"environmentId" => "unknown"}) == %{
             "status" => "unknown",
             "error" => "unknown environment id `unknown`"
           }

    assert add(ctx, pid, "approved") == %{}
    assert_ready(pid, "approved")
    assert_info(ctx, pid, "approved")
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "owned executor disappearance reports disconnected and native info failure without losing registration",
       ctx do
    pid = start(ctx)
    assert add(ctx, pid, "approved") == %{}
    assert_ready(pid, "approved")
    assert_info(ctx, pid, "approved")
    control(ctx, "stop_executor")
    status = wait_status(pid, "approved", "disconnected")
    assert is_binary(status["error"]) and status["error"] != ""
    error = upstream_error(pid, "environment/info", %{"environmentId" => "approved"})
    assert error["code"] == -32_603
    assert error["message"] =~ "failed to get info for environment `approved`"

    assert call(pid, "environment/status", %{"environmentId" => "approved"})["status"] ==
             "disconnected"

    assert inputs(ctx, "environment/add") == 1
    assert count(ctx, "executor_stopped") == 1
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root],
             env: %{"CODEX_HOME" => Path.join(ctx.root, "app")}
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_isolated_environment", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp registration(ctx, id) do
    started = Enum.find(journal(ctx)["events"], &(&1["event"] == "native_started"))

    %{
      "environmentId" => id,
      "execServerUrl" => started["executor_url"],
      "authBearerToken" => @token,
      "websocketRequestId" => "synthetic-environment-request",
      "connectTimeoutMs" => 250
    }
  end

  defp add(ctx, pid, id, credential \\ @token) do
    params = registration(ctx, id) |> Map.put("authBearerToken", credential)
    call(pid, "environment/add", params)
  end

  defp assert_info(ctx, pid, id) do
    assert %{"cwd" => cwd, "shell" => %{"name" => name, "path" => path}} =
             call(pid, "environment/info", %{"environmentId" => id})

    assert cwd == "file://" <> Path.join(ctx.root, "executor-workspace")
    assert is_binary(name) and name != ""
    assert is_binary(path) and path != ""
    true
  end

  defp assert_ready(pid, id), do: assert(wait_status(pid, id, "ready") == %{"status" => "ready"})

  defp wait_status(pid, id, status),
    do: wait_status(pid, id, status, System.monotonic_time(:millisecond) + 10_000)

  defp wait_status(pid, id, expected, deadline) do
    result = call(pid, "environment/status", %{"environmentId" => id})

    if result["status"] == expected do
      result
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "native environment status deadline: #{inspect(result)}"

      receive do
      after
        10 -> :ok
      end

      wait_status(pid, id, expected, deadline)
    end
  end

  defp control(ctx, action) do
    id = System.unique_integer([:positive])
    pending = Path.join(ctx.root, "control.pending")
    File.write!(pending, JSON.encode!(%{"id" => id, "action" => action}))
    File.rename!(pending, Path.join(ctx.root, "control.json"))
    await_control(ctx, id, System.monotonic_time(:millisecond) + 5_000)
  end

  defp await_connections(ctx, previous, deadline) do
    if count(ctx, "proxy_connected") > previous do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "native executor reconnect deadline"

      receive do
      after
        10 -> :ok
      end

      await_connections(ctx, previous, deadline)
    end
  end

  defp await_control(ctx, id, deadline) do
    if Enum.any?(journal(ctx)["events"], &(&1["event"] == "control_completed" and &1["id"] == id)) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "owned environment control deadline"

      receive do
      after
        10 -> :ok
      end

      await_control(ctx, id, deadline)
    end
  end

  defp assert_profile(ctx, pid) do
    data = journal(ctx)
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"]
    assert count(ctx, "unexpected_http") == 0
    assert count(ctx, "fixture_error") == 0
    probes = for event <- data["events"], event["event"] == "native_auth_probe", do: event

    assert Enum.map(probes, &{&1["credential"], &1["status"]}) == [
             {"absent", 401},
             {"wrong", 401},
             {"valid", 101}
           ]

    for file <- [
          ctx.journal,
          Path.join(ctx.root, "app-stderr.log"),
          Path.join(ctx.root, "executor-stderr.log")
        ] do
      refute File.read!(file) =~ @token
    end

    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
  end

  defp close(ctx, pid) do
    started = Enum.find(journal(ctx)["events"], &(&1["event"] == "native_started"))
    assert :ok = Session.close(pid)

    for key <- ["pid", "executor_pid", "controller_pid", "namespace_owner_pid"] do
      refute File.exists?("/proc/#{Map.fetch!(started, key)}"),
             "owned environment process must be reaped"
    end
  end

  defp journal(ctx), do: ctx.journal |> File.read!() |> JSON.decode!()
  defp count(ctx, event), do: Enum.count(journal(ctx)["events"], &(&1["event"] == event))

  defp inputs(ctx, method),
    do:
      Enum.count(
        journal(ctx)["events"],
        &(&1["event"] == "native_input" and &1["method"] == method)
      )

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp upstream_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params)

    error
  end
end
