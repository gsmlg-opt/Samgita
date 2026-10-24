defmodule SamgitaCodexDriver.NativeEnvironmentRequestIdProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_environment_request_id
  @moduletag timeout: 60_000
  @script Path.expand(
            "../../../scripts/codex/isolated_environment_request_id_fixture.py",
            __DIR__
          )
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
        "samgita-environment-request-id-" <>
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

  test "native upgrade preserves exact request ID across a controlled executor reconnect", ctx do
    pid = start(ctx)
    [started] = events(ctx, "native_started")
    destination = started["executor_url"]
    request_id = "Owned-Request-ID-20261025"

    assert call(pid, "environment/add", %{
             "environmentId" => "request-id",
             "execServerUrl" => destination,
             "authBearerToken" => @token,
             "connectTimeoutMs" => 15_000,
             "websocketRequestId" => request_id
           }) == %{}

    assert_info(ctx, pid)

    assert call(pid, "environment/status", %{"environmentId" => "request-id"}) == %{
             "status" => "ready"
           }

    assert events(ctx, "request_id_verified") == [
             %{"event" => "request_id_verified", "connection" => 1, "request_id" => request_id}
           ]

    control(ctx, "pause_proxy")
    await(fn -> Enum.any?(events(ctx, "proxy_disconnected"), &(&1["connection"] == 1)) end)
    status = call(pid, "environment/status", %{"environmentId" => "request-id"})
    assert status["status"] == "disconnected"
    assert is_binary(status["error"]) and status["error"] != ""
    control(ctx, "resume_proxy")
    # Explicit metadata recovery may resume a transport; it never re-registers or launches work.
    assert_info(ctx, pid)

    assert call(pid, "environment/status", %{"environmentId" => "request-id"}) == %{
             "status" => "ready"
           }

    assert events(ctx, "request_id_verified") == [
             %{"event" => "request_id_verified", "connection" => 1, "request_id" => request_id},
             %{"event" => "request_id_verified", "connection" => 2, "request_id" => request_id}
           ]

    assert Enum.map(events(ctx, "proxy_connected"), & &1["connection"]) == [1, 2]
    assert length(events(ctx, "proxy_waiting")) == 2
    assert Enum.count(events(ctx, "native_input"), &(&1["method"] == "environment/add")) == 1

    assert Enum.all?(
             events(ctx, "exec_rpc"),
             &(&1["connection"] in [1, 2] and
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

  defp assert_info(ctx, pid) do
    info = call(pid, "environment/info", %{"environmentId" => "request-id"})
    assert info["cwd"] == "file://" <> Path.join(ctx.root, "executor-workspace")
    assert is_binary(info["shell"]["name"]) and info["shell"]["name"] != ""
    assert is_binary(info["shell"]["path"]) and info["shell"]["path"] != ""
  end

  defp control(ctx, action) do
    id = System.unique_integer([:positive])
    path = Path.join(ctx.root, "control.json")
    File.write!(path <> ".pending", JSON.encode!(%{"id" => id, "action" => action}))
    File.rename!(path <> ".pending", path)
    await(fn -> Enum.any?(events(ctx, "control_completed"), &(&1["id"] == id)) end)
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
               %{"name" => "samgita_owned_environment_request_id", "version" => "1"},
               %{"experimentalApi" => true}
             )

    await(fn -> length(events(ctx, "native_started")) == 1 end)
    pid
  end

  defp call(pid, method, params) do
    id = "owned-environment-request-id-#{System.unique_integer([:positive])}"

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
      assert System.monotonic_time(:millisecond) < deadline,
             "owned environment request-ID deadline"

      Process.sleep(10)
      await(predicate, deadline)
    end
  end
end
