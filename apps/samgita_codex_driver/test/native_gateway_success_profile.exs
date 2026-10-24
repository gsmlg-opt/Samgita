defmodule SamgitaCodexDriver.NativeGatewaySuccessProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_gateway_oauth
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/private_gateway_uds_controller.py", __DIR__)
  @base Path.expand("../../../scripts/codex/isolated_gateway_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @read "account/gatewayOAuth/read"
  @login "account/gatewayOAuth/login"
  @cancel "account/gatewayOAuth/cancel"
  @changed "account/gatewayOAuth/changed"
  @allowed [@read, @login, @cancel, "account/logout"]
  @canaries [
    "OWNED_SYNTHETIC_GATEWAY_ACCESS",
    "OWNED_SYNTHETIC_GATEWAY_REFRESH",
    "OWNED_GATEWAY_ISSUER_PRIVATE_CANARY"
  ]

  setup do
    binary = executable!("CODEX_BINARY")
    keyring = executable!("GNOME_KEYRING_DAEMON", "gnome-keyring-daemon")
    dbus = executable!("DBUS_DAEMON", "dbus-daemon")
    gdbus = executable!("GDBUS", "gdbus")
    setpriv = executable!("SETPRIV", "setpriv")
    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    python = System.find_executable("python3")
    assert python
    for tool <- ~w(unshare ip), do: assert(System.find_executable(tool))
    base = @base
    script = @script
    assert File.regular?(base) and Path.type(base) == :absolute
    assert File.regular?(script) and Path.type(script) == :absolute

    root =
      Path.join(
        System.tmp_dir!(),
        "sg-gw-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      parent_netns: File.read_link!("/proc/self/ns/net")
    }

    # No nonexistent workspace cwd: controller creates all private dirs itself.
    {:ok, owner} =
      Stdio.open(
        executable: python,
        python: python,
        args: [
          script,
          "--root",
          root,
          "--codex",
          binary,
          "--base-fixture",
          base,
          "--gnome-keyring-daemon",
          keyring,
          "--dbus-daemon",
          dbus,
          "--gdbus",
          gdbus,
          "--setpriv",
          setpriv
        ],
        cwd: root,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => System.tmp_dir!(),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    # Register immediately, including when startup/preflight assertions fail.
    on_exit(fn ->
      try do
        unless File.exists?(Path.join(root, "state.json")) and state(ctx)["cleanup_complete"] do
          assert {:ok, _} = Stdio.send(owner, JSON.encode!(%{"operation" => "close"}))

          await(fn ->
            File.exists?(Path.join(root, "state.json")) and state(ctx)["cleanup_complete"]
          end)
        end
      after
        assert :ok = Stdio.close(owner)
      end

      final = state(ctx)

      for os_pid <-
            final["native_pids"] ++
              final["keyring_pids"] ++ [final["controller_pid"], final["namespace_owner_pid"]] do
        await(fn -> not File.exists?("/proc/#{os_pid}") end)
      end

      assert final["cleanup_errors"] == [] and final["secret_scan_passed"]

      diagnostics = root <> "-diagnostics"
      File.mkdir!(diagnostics)
      File.chmod!(diagnostics, 0o700)
      File.cp!(Path.join(root, "state.json"), Path.join(diagnostics, "state.json"))

      for log <- Path.wildcard(Path.join(root, "*.log")),
          do: File.cp!(log, Path.join(diagnostics, Path.basename(log)))

      for directory <- ~w(home codex workspace tmp runtime control data config cache),
          do: refute(File.exists?(Path.join(root, directory)))

      File.rm_rf!(root)
    end)

    await(fn -> ready?(ctx, 1) end)
    proof = state(ctx)
    assert proof["namespace"]["parent"] == ctx.parent_netns
    assert proof["namespace"]["child"] != ctx.parent_netns
    assert proof["namespace"]["interfaces"] == ["lo"]
    refute proof["namespace"]["default_route"]
    refute proof["namespace"]["ipv6_default_route"]
    privileges = proof["namespace"]["privileges"]

    for key <- ~w(CapInh CapPrm CapEff CapBnd CapAmb),
        do: assert(String.to_integer(privileges[key], 16) == 0)

    assert privileges["NoNewPrivs"] == "1"
    assert proof["keyring"]["real_secret_service"] and proof["keyring"]["login_unlocked"]
    refute proof["keyring"]["host_bus_inherited"]
    assert is_binary(proof["keyring"]["daemon_version"])
    Map.put(ctx, :owner, owner)
  end

  test "real keyring native success persists across native restart and primary logout", ctx do
    pid = client(ctx)
    assert call(pid, @read) == projection("notReady")
    parent = self()

    {worker, monitor} =
      spawn_monitor(fn -> send(parent, {:login_result, self(), request(pid, @login)}) end)

    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    events = collect(pid, &Enum.any?(&1, fn event -> handoff?(event.wire) end))
    handoffs = Enum.filter(events, &handoff?(&1.wire))
    assert length(handoffs) == 1
    assert call(pid, @read) == projection("started")

    assert {:error, %Error{code: :upstream_error, wire: %{"error" => duplicate}}} =
             request(pid, @login)

    assert duplicate == %{
             "code" => -32_600,
             "message" => "Gateway sign-in is already in progress"
           }

    control(ctx, %{"operation" => "callback", "native_frame" => hd(handoffs).wire})
    assert_receive {:login_result, ^worker, {:ok, response}}, 5_000
    assert response["result"] == %{} and response["id"] != nil
    assert Map.keys(response) -- ["id", "result", "jsonrpc"] == []
    refute Map.has_key?(response, "error")
    assert Map.get(response, "jsonrpc", "2.0") == "2.0"
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000

    events =
      collect(pid, &Enum.any?(&1, fn event -> changed?(event.wire, "succeeded") end), events)

    assert Enum.count(events, &changed?(&1.wire, "succeeded")) == 1
    assert call(pid, @read) == projection("succeeded")
    assert call(pid, @cancel) == %{}
    assert_clean_session(pid)
    snapshot(ctx, 1)
    first = hd(state(ctx)["snapshots"])
    assert first["generation"] == 1 and first["token_exchanges"] == 1 and first["handoffs"] == 1
    assert :ok = Session.close(pid)
    old_native = hd(state(ctx)["native_pids"])
    control(ctx, %{"operation" => "restart"})
    await(fn -> ready?(ctx, 2) end)
    refute File.exists?("/proc/#{old_native}")
    cold = client(ctx)
    assert call(cold, @read) == projection("succeeded")
    {:ok, cold_events} = Session.drain(cold)
    assert Enum.all?(cold_events, &(not handoff?(&1.wire)))
    snapshot(ctx, 2)
    second = Enum.at(state(ctx)["snapshots"], 1)
    assert second["generation"] == 2
    assert Map.drop(second, ["generation"]) == Map.drop(first, ["generation"])
    assert call(cold, "account/logout") == %{}

    logout_events =
      collect(cold, &Enum.any?(&1, fn event -> event.wire["method"] == "account/updated" end))

    assert Enum.any?(
             logout_events,
             &(&1.wire["method"] == "account/updated" and
                 &1.wire["params"] == %{"authMode" => nil, "planType" => nil})
           )

    assert Enum.all?(logout_events, &(not handoff?(&1.wire)))
    # requires_openai_auth=false; primary logout retains this independent token.
    assert call(cold, @read) == projection("succeeded")
    snapshot(ctx, 3)
    assert Enum.at(state(ctx)["snapshots"], 2) == second
    assert state(ctx)["callbacks"] == 1
    assert_clean_session(cold)
    assert :ok = Session.close(cold)
  end

  defp executable!(name, fallback \\ nil) do
    path = System.get_env(name) || (fallback && System.find_executable(fallback))

    assert is_binary(path) and Path.type(path) == :absolute and System.find_executable(path),
           "BLOCKED_ENV: #{name} executable required"

    path
  end

  defp client(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_gateway_success", "version" => "1"},
               %{"explicitGatewayOauth" => true, "experimentalApi" => false}
             )

    pid
  end

  defp projection(status),
    do: %{
      "providerId" => "gateway",
      "providerName" => "Owned gateway",
      "required" => true,
      "status" => status,
      "error" => nil
    }

  defp request(pid, method) do
    assert method in @allowed

    Session.request_native(pid, %{
      "id" => "owned-gateway-success-#{:erlang.unique_integer([:positive])}",
      "method" => method
    })
  end

  defp call(pid, method) do
    assert {:ok, %{"result" => result}} = request(pid, method)
    result
  end

  defp handoff?(wire),
    do:
      wire["method"] == @changed and is_binary(wire["params"]["authUrl"]) and
        wire["params"]["providerId"] == "gateway" and wire["params"]["status"] == "started" and
        wire["params"]["error"] == nil

  defp changed?(wire, status),
    do:
      wire["method"] == @changed and
        wire["params"] == %{
          "providerId" => "gateway",
          "status" => status,
          "authUrl" => nil,
          "error" => nil
        }

  defp control(ctx, value), do: assert({:ok, _owner} = Stdio.send(ctx.owner, JSON.encode!(value)))

  defp snapshot(ctx, count) do
    control(ctx, %{"operation" => "snapshot"})
    await(fn -> length(state(ctx)["snapshots"]) == count end)
  end

  defp assert_clean_session(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
  end

  defp collect(pid, predicate, previous \\ [], remaining \\ 500)
  defp collect(_pid, _predicate, _previous, 0), do: flunk("native Gateway notification deadline")

  defp collect(pid, predicate, previous, remaining) do
    assert {:ok, current} = Session.drain(pid)

    for event <- current do
      refute event.kind == :server_request

      refute event.wire["method"] in [
               "turn/started",
               "modelProvider/authRecoveryStarted",
               "modelProvider/authRecoveryCompleted"
             ]

      unless handoff?(event.wire),
        do: Enum.each(@canaries, &refute(JSON.encode!(event.wire) =~ &1))
    end

    events = previous ++ current

    if predicate.(events),
      do: events,
      else:
        (
          Process.sleep(10)
          collect(pid, predicate, events, remaining - 1)
        )
  end

  defp state(ctx), do: ctx.root |> Path.join("state.json") |> File.read!() |> JSON.decode!()

  defp ready?(ctx, generation),
    do:
      File.exists?(Path.join(ctx.root, "state.json")) and state(ctx)["ready"] and
        state(ctx)["generation"] == generation and File.exists?(ctx.socket)

  defp await(predicate, remaining \\ 500)
  defp await(_predicate, 0), do: flunk("private Gateway observation deadline")

  defp await(predicate, remaining) do
    if predicate.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await(predicate, remaining - 1)
        )
  end
end
