defmodule SamgitaCodexDriver.NativeEnvironmentTimeoutProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_environment_timeout
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_environment_timeout_fixture.py", __DIR__)
  @sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @token "synthetic-isolated-executor-credential-canary"
  @shared_sources %{
    "../../../scripts/codex/isolated_environment_fixture.py" =>
      "f2097b358d182d87e1cf8b8203527c62e1ee6be945db72027dfb97acb90408c7",
    "../../../scripts/codex/isolated_thread_environment_fixture.py" =>
      "a494ce9b4999bb89391f7f363a63a1038d00ad7172bb16e92692fb89504b4482"
  }

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert digest(binary) == @sha256
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-environment-timeout-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    ctx = %{root: root, binary: Path.expand(binary)}

    on_exit(fn ->
      if File.exists?(Path.join(root, "isolated-environment-journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
            do: await(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert length(events(ctx, "native_started")) == length(events(ctx, "native_closed"))
      end

      File.rm_rf!(root)
    end)

    assert_immutable_sources(ctx)
    ctx
  end

  test "native connect timeout closes a held upgrade while a longer delayed control becomes ready",
       ctx do
    pid = start(ctx)
    [started] = events(ctx, "native_started")
    destination = started["executor_url"]

    assert add(pid, destination, "timeout", 500) == %{}
    await(fn -> length(events(ctx, "upgrade_held")) == 1 end)
    assert events(ctx, "upgrade_released") == []
    await(fn -> length(events(ctx, "upgrade_peer_closed")) == 1 end)
    await(fn -> length(events(ctx, "proxy_disconnected")) == 1 end)

    [held] = events(ctx, "upgrade_held")
    [closed] = events(ctx, "upgrade_peer_closed")
    assert held["connection"] == 1 and closed["connection"] == 1
    assert closed["monotonic_ns"] >= held["monotonic_ns"]
    assert events(ctx, "proxy_connected") == [] and events(ctx, "exec_rpc") == []

    expected = %{
      "status" => "disconnected",
      "error" =>
        "exec-server connection attempt failed: timed out connecting to exec-server websocket " <>
          "`#{destination}` after 500ms"
    }

    for _ <- 1..3 do
      assert call(pid, "environment/status", %{"environmentId" => "timeout"}) == expected
      assert length(events(ctx, "proxy_waiting")) == 1
    end

    assert add(pid, destination, "control", 5000) == %{}
    await(fn -> length(events(ctx, "upgrade_held")) == 2 end)

    assert call(pid, "environment/status", %{"environmentId" => "control"}) == %{
             "status" => "pending"
           }

    assert events(ctx, "proxy_connected") == []
    control = System.unique_integer([:positive])
    path = Path.join(ctx.root, "control.json")

    File.write!(
      path <> ".pending",
      JSON.encode!(%{"id" => control, "action" => "release_control_upgrade"})
    )

    File.rename!(path <> ".pending", path)
    await(fn -> Enum.any?(events(ctx, "control_completed"), &(&1["id"] == control)) end)
    [released] = events(ctx, "upgrade_released")
    assert released["connection"] == 2
    assert released["held_ns"] >= 1_000_000_000 and released["held_ns"] < 4_000_000_000
    await(fn -> length(events(ctx, "proxy_connected")) == 1 end)
    # The real executor's initialized message is the barrier before metadata reads.
    await(fn -> Enum.any?(events(ctx, "exec_rpc"), &(&1["method"] == "initialized")) end)

    info = call(pid, "environment/info", %{"environmentId" => "control"})
    assert info["cwd"] == "file://" <> Path.join(ctx.root, "executor-workspace")
    assert is_binary(info["shell"]["name"]) and info["shell"]["name"] != ""
    assert is_binary(info["shell"]["path"]) and info["shell"]["path"] != ""

    assert call(pid, "environment/status", %{"environmentId" => "control"}) == %{
             "status" => "ready"
           }

    assert call(pid, "environment/status", %{"environmentId" => "timeout"}) == expected

    assert events(ctx, "registration_checked") == [
             %{
               "event" => "registration_checked",
               "environment_id" => "timeout",
               "connect_timeout_ms" => 500,
               "approved_destination" => true
             },
             %{
               "event" => "registration_checked",
               "environment_id" => "control",
               "connect_timeout_ms" => 5000,
               "approved_destination" => true
             }
           ]

    assert length(events(ctx, "proxy_waiting")) == 2
    assert Enum.map(events(ctx, "proxy_connected"), & &1["connection"]) == [2]
    assert Enum.map(events(ctx, "upgrade_peer_closed"), & &1["connection"]) == [1]

    assert Enum.all?(
             events(ctx, "exec_rpc"),
             &(&1["connection"] == 2 and
                 &1["method"] in ~w(initialize initialized environment/info environment/status))
           )

    assert_profile(ctx, pid)
    assert :ok = Session.close(pid)
    await(fn -> length(events(ctx, "native_closed")) == 1 end)

    assert [
             %{
               "children_reaped" => true,
               "workers_stopped" => true,
               "redaction_checked" => true
             }
           ] = events(ctx, "resources_closed")

    for key <- ~w(pid executor_pid controller_pid namespace_owner_pid),
        do: refute(File.exists?("/proc/#{started[key]}"))

    for name <- ~w(app executor) do
      data = File.read!(Path.join(ctx.root, "#{name}-stderr.log"))
      assert byte_size(data) <= 262_144
      refute data =~ @token
    end

    refute File.read!(Path.join(ctx.root, "isolated-environment-journal.json")) =~ @token
    assert_immutable_sources(ctx)
  end

  defp start(ctx) do
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
               %{"name" => "samgita_owned_environment_timeout", "version" => "1"},
               %{"experimentalApi" => true}
             )

    await(fn -> length(events(ctx, "native_started")) == 1 end)
    pid
  end

  defp add(pid, destination, identity, timeout) do
    call(pid, "environment/add", %{
      "environmentId" => identity,
      "execServerUrl" => destination,
      "authBearerToken" => @token,
      "connectTimeoutMs" => timeout
    })
  end

  defp call(pid, method, params) do
    id = "owned-environment-timeout-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    result
  end

  defp assert_profile(ctx, pid) do
    data = journal(ctx)
    assert data["namespace"]["parent"] != data["namespace"]["child"]
    assert data["namespace"]["parent_user"] != data["namespace"]["child_user"]
    assert data["namespace"]["interfaces"] == ["lo"]
    refute data["namespace"]["default_route"]
    refute data["namespace"]["ipv6_default_route"]

    for event <- ~w(fixture_error forbidden_exec_rpc unexpected_http),
        do: assert(events(ctx, event) == [])

    probes =
      for probe <- events(ctx, "native_auth_probe"),
          do: {probe["credential"], probe["status"]}

    assert probes == [{"absent", 401}, {"wrong", 401}, {"valid", 101}]

    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, notifications} = Session.drain(pid)
    refute Enum.any?(notifications, &(&1.kind == :server_request))

    assert Enum.all?(
             events(ctx, "native_input"),
             &(&1["method"] in ~w(initialize initialized environment/add environment/info environment/status thread/loaded/list))
           )
  end

  defp assert_immutable_sources(ctx) do
    assert digest(ctx.binary) == @sha256

    for {relative, expected} <- @shared_sources,
        do: assert(digest(Path.expand(relative, __DIR__)) == expected)
  end

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp journal(ctx),
    do:
      ctx.root |> Path.join("isolated-environment-journal.json") |> File.read!() |> JSON.decode!()

  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))

  defp await(predicate) do
    deadline = System.monotonic_time(:millisecond) + 10_000
    await(predicate, deadline)
  end

  defp await(predicate, deadline) do
    if value = predicate.() do
      value
    else
      assert System.monotonic_time(:millisecond) < deadline, "owned environment timeout deadline"
      Process.sleep(10)
      await(predicate, deadline)
    end
  end
end
