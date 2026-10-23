defmodule SamgitaCodexDriver.NativeGatewayOAuthProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_gateway_oauth
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_gateway_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @read "account/gatewayOAuth/read"
  @login "account/gatewayOAuth/login"
  @cancel "account/gatewayOAuth/cancel"
  @changed "account/gatewayOAuth/changed"
  @canary "OWNED_GATEWAY_ISSUER_PRIVATE_CANARY"
  @failure "Gateway sign-in failed; check the gateway configuration and credential store."
  @canceled "Gateway sign-in was canceled"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-gateway-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    ctx = %{binary: Path.expand(binary), root: root, scenario: tags[:scenario] || "cancel"}

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert events(ctx, "native_closed") != []
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  @tag scenario: "no-gateway"
  test "stable passive read and idle cancel work without a gateway and login rejects", ctx do
    pid = start(ctx)
    read(pid, false, nil, nil)
    assert call(pid, @cancel) == %{}

    assert error(pid, @login) == %{
             "code" => -32_600,
             "message" => "The current provider does not use gateway OAuth"
           }

    assert events(ctx, "auth_handoff") == []
    finish(ctx, pid)
  end

  @tag scenario: "primary-required"
  test "primary account gate rejects before a gateway browser handoff or issuer request", ctx do
    pid = start(ctx)
    read(pid, true, "notReady", nil)

    assert error(pid, @login) == %{
             "code" => -32_600,
             "message" => "Sign in to your primary account before signing in to the gateway"
           }

    assert call(pid, @cancel) == %{}
    assert events(ctx, "auth_handoff") == []
    finish(ctx, pid)
  end

  @tag scenario: "opt-out"
  test "opting out of changed notices rejects login before starting authorization", ctx do
    pid = start(ctx)
    read(pid, true, "notReady", nil)

    assert error(pid, @login) == %{
             "code" => -32_600,
             "message" => "Gateway login requires account/gatewayOAuth/changed notifications"
           }

    assert call(pid, @cancel) == %{}
    assert {:ok, received} = Session.drain(pid)
    refute Enum.any?(received, &(&1.wire["method"] == @changed))
    assert events(ctx, "auth_handoff") == []
    finish(ctx, pid)
  end

  test "passive reads model readiness duplicate login cancellation and immediate retry", ctx do
    pid = start(ctx)
    read(pid, true, "notReady", nil)
    initial = collect(pid, &Enum.any?(&1, fn event -> changed(event, "notReady", nil) end))
    assert Enum.any?(initial, &changed(&1, "notReady", nil))
    assert error(pid, "model/list", %{})["message"] =~ "Gateway sign-in required"
    received = collect(pid, &Enum.any?(&1, fn event -> changed(event, "notReady", nil) end))
    assert Enum.any?(received, &changed(&1, "notReady", nil))

    first = pending_login(pid)
    assert_started(pid)
    assert call(pid, @cancel) == %{}
    # Start the retry on cancel ACK, without consuming the old login response.
    second = pending_login(pid)
    received = assert_started(pid)
    assert_pending_error(first, @canceled)
    assert Enum.count(received, &changed(&1, "failed", @canceled)) == 1
    assert call(pid, @cancel) == %{}
    assert_pending_error(second, @canceled)
    received = collect(pid, &Enum.any?(&1, fn event -> changed(event, "failed", @canceled) end))
    assert Enum.count(received, &changed(&1, "failed", @canceled)) == 1
    read(pid, true, "failed", @canceled)
    assert length(events(ctx, "auth_handoff")) == 2

    assert call(pid, @cancel) == %{}
    assert events(ctx, "token_exchange") == []
    finish(ctx, pid)
  end

  @tag scenario: "token-failure"
  test "real native callback and PKCE exchange preserve sanitized terminal error and readiness",
       ctx do
    pid = start(ctx)
    read(pid, true, "notReady", nil)
    pending = pending_login(pid)
    received = collect(pid, &Enum.any?(&1, fn event -> changed(event, "failed", @failure) end))
    assert_pending_error(pending, @failure)
    assert Enum.count(received, &handoff?/1) == 1
    assert Enum.count(received, &changed(&1, "failed", @failure)) == 1
    read(pid, true, "failed", @failure)
    assert call(pid, @cancel) == %{}

    assert events(ctx, "native_callback") == [
             %{"event" => "native_callback", "status" => 200, "state_from_native" => true}
           ]

    assert events(ctx, "token_exchange") == [
             %{
               "event" => "token_exchange",
               "pkce_verified" => true,
               "body_verified" => true,
               "authorization_absent" => true,
               "host_verified" => true
             }
           ]

    finish(ctx, pid)
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               @script,
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--scenario",
               ctx.scenario
             ],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    capabilities = %{"explicitGatewayOauth" => true, "experimentalApi" => false}

    capabilities =
      if ctx.scenario == "opt-out",
        do: Map.put(capabilities, "optOutNotificationMethods", [@changed]),
        else: capabilities

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_gateway", "version" => "1"},
               capabilities
             )

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp state(required, status, error),
    do: %{
      "providerId" => "gateway",
      "providerName" => "Owned gateway",
      "required" => required,
      "status" => status,
      "error" => error
    }

  defp read(pid, required, status, error) do
    result = call(pid, @read)
    assert result == state(required, status, error)
    result
  end

  defp request(pid, method, params \\ nil) do
    wire = %{"id" => "owned-gateway-#{System.unique_integer([:positive])}", "method" => method}
    wire = if params == nil, do: wire, else: Map.put(wire, "params", params)
    Session.request_native(pid, wire)
  end

  defp call(pid, method) do
    assert {:ok, %{"result" => result}} = request(pid, method)
    result
  end

  defp error(pid, method, params \\ nil) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => failure}}} =
             request(pid, method, params)

    refute JSON.encode!(failure) =~ @canary
    failure
  end

  defp pending_login(pid) do
    owner = self()

    {worker, monitor} =
      spawn_monitor(fn -> send(owner, {:owned_gateway_login, self(), request(pid, @login)}) end)

    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    {worker, monitor}
  end

  defp assert_started(pid) do
    received =
      collect(pid, fn events ->
        Enum.any?(events, &handoff?/1) and Enum.any?(events, &changed(&1, "started", nil))
      end)

    assert Enum.count(received, &handoff?/1) == 1
    read(pid, true, "started", nil)

    assert error(pid, @login) == %{
             "code" => -32_600,
             "message" => "Gateway sign-in is already in progress"
           }

    received
  end

  defp assert_pending_error({worker, monitor}, message) do
    assert_receive {:owned_gateway_login, ^worker,
                    {:error, %Error{code: :upstream_error, wire: %{"error" => failure}}}},
                   5_000

    assert failure == %{"code" => -32_603, "message" => message}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}, 5_000
  end

  defp changed(event, status, error),
    do:
      event.wire["method"] == @changed and
        event.wire["params"] == %{
          "providerId" => "gateway",
          "authUrl" => nil,
          "status" => status,
          "error" => error
        }

  defp handoff?(event) do
    params = event.wire["params"]

    event.wire["method"] == @changed and is_binary(params["authUrl"]) and
      params["status"] == "started" and params["providerId"] == "gateway" and
      params["error"] == nil
  end

  defp collect(pid, predicate, received \\ [], remaining \\ 500)
  defp collect(_pid, _predicate, _received, 0), do: flunk("Owned gateway notification deadline")

  defp collect(pid, predicate, received, remaining) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current

    for event <- current do
      refute event.kind == :server_request

      refute event.wire["method"] in [
               "turn/started",
               "modelProvider/authRecoveryStarted",
               "modelProvider/authRecoveryCompleted"
             ]

      unless handoff?(event), do: refute(JSON.encode!(event.wire) =~ @canary)
    end

    if predicate.(received),
      do: received,
      else:
        (
          Process.sleep(10)
          collect(pid, predicate, received, remaining - 1)
        )
  end

  defp finish(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    refute File.exists?(Path.join(ctx.root, "codex/secrets/gateway_oauth.age"))
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert :ok = Session.close(pid)
    wait(fn -> events(ctx, "native_closed") != [] end)
    for name <- ~w(unexpected_http fixture_error peer_closed), do: assert(events(ctx, name) == [])
    assert events(ctx, "secret_scan") == [%{"event" => "secret_scan", "passed" => true}]
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned gateway observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.(),
      do: value,
      else:
        (
          Process.sleep(10)
          wait(predicate, remaining - 1)
        )
  end
end
