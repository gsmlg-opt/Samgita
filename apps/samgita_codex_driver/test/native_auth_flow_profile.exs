defmodule SamgitaCodexDriver.NativeAuthFlowProfile do
  use ExUnit.Case, async: false

  import Bitwise
  alias SamgitaCodexDriver.{Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_auth
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_auth_fixture.py", __DIR__)

  # Explicit Linux profile, deliberately outside default *_test.exs discovery.
  # Run this file directly. Missing isolation is a failing prerequisite, never a skip.
  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert System.find_executable("unshare"), "BLOCKED_ENV: unshare required"
    assert System.find_executable("ip"), "BLOCKED_ENV: ip required"

    root =
      Path.join(System.tmp_dir!(), "samgita-isolated-auth-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, binary: binary, journal: Path.join(root, "isolated-auth-journal.json")}
  end

  test "browser callback rejects wrong state then exchanges PKCE and persists native account",
       ctx do
    pid = start(ctx, "browser_success")
    result = call(pid, "account/login/start", %{"type" => "chatgpt"})
    assert result["type"] == "chatgpt"
    assert is_binary(result["loginId"])
    assert URI.parse(result["authUrl"]).host == "127.0.0.1"
    events = completion(pid, result["loginId"], true)
    assert updated(events) == %{"authMode" => "chatgpt", "planType" => "pro"}
    assert_account(pid)
    journal = journal(ctx)
    names = Enum.map(journal["events"], & &1["event"])

    assert Enum.filter(names, &(&1 in ["browser_wrong_state", "authorization_code_exchange"])) ==
             ["browser_wrong_state", "authorization_code_exchange"]

    assert count(journal, "authorization_code_exchange") == 1
    assert count(journal, "api_key_exchange") == 1
    assert count(journal, "browser_success_page") == 1
    assert persisted(ctx)["auth_mode"] == "chatgpt"
    assert band(File.stat!(auth_path(ctx)).mode, 0o777) == 0o600
    assert_profile(ctx, pid)
    close(ctx, pid)

    cold = start(ctx, "browser_success")
    assert_account(cold)
    assert count(journal(ctx), "authorization_code_exchange") == 0
    logout(cold)
    assert count(journal(ctx), "revocation") == 1
    refute File.exists?(auth_path(ctx))
    assert call(cold, "account/read", %{})["account"] == nil
    assert_profile(ctx, cold)
    close(ctx, cold)
  end

  test "browser cancellation emits the actual failed completion and leaves no credentials", ctx do
    pid = start(ctx, "browser_cancel")
    result = call(pid, "account/login/start", %{"type" => "chatgpt"})
    assert result["type"] == "chatgpt"
    cancel(pid, result["loginId"])
    events = completion(pid, result["loginId"], false)

    assert TurnFixture.notification(events, "account/login/completed")["error"] ==
             "Login server error: Login was not completed"

    refute updated(events)
    refute File.exists?(auth_path(ctx))
    assert count(journal(ctx), "authorization_code_exchange") == 0

    assert call(pid, "account/login/cancel", %{"loginId" => result["loginId"]}) == %{
             "status" => "notFound"
           }

    assert_absent_account(pid)
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "device code success uses native polling exchange persistence and cold account reads",
       ctx do
    pid = start(ctx, "device_success")
    result = call(pid, "account/login/start", %{"type" => "chatgptDeviceCode"})
    assert result["type"] == "chatgptDeviceCode"
    assert result["userCode"] == "SYNTHETIC-CODE"
    assert URI.parse(result["verificationUrl"]).host == "127.0.0.1"
    events = completion(pid, result["loginId"], true)
    assert updated(events) == %{"authMode" => "chatgpt", "planType" => "pro"}
    assert_account(pid)
    assert count(journal(ctx), "device_usercode") == 1
    assert count(journal(ctx), "device_poll_started") == 1
    assert count(journal(ctx), "authorization_code_exchange") == 1
    assert count(journal(ctx), "api_key_exchange") == 0
    assert persisted(ctx)["auth_mode"] == "chatgpt"
    assert_profile(ctx, pid)
    close(ctx, pid)

    cold = start(ctx, "device_success")
    assert_account(cold)
    assert count(journal(ctx), "device_usercode") == 0
    assert count(journal(ctx), "authorization_code_exchange") == 0
    logout(cold)
    assert count(journal(ctx), "revocation") == 1
    refute File.exists?(auth_path(ctx))
    assert_profile(ctx, cold)
    close(ctx, cold)
  end

  test "device cancellation interrupts an observed held poll without token exchange", ctx do
    pid = start(ctx, "device_cancel")
    result = call(pid, "account/login/start", %{"type" => "chatgptDeviceCode"})
    await_fixture(ctx, "device_poll_started")
    cancel(pid, result["loginId"])
    events = completion(pid, result["loginId"], false)

    assert TurnFixture.notification(events, "account/login/completed")["error"] ==
             "Login was not completed"

    refute updated(events)
    assert count(journal(ctx), "native_cancelled") == 1
    assert count(journal(ctx), "authorization_code_exchange") == 0
    refute File.exists?(auth_path(ctx))
    assert_absent_account(pid)
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "device polling error emits correlated native failure without account update", ctx do
    pid = start(ctx, "device_error")
    result = call(pid, "account/login/start", %{"type" => "chatgptDeviceCode"})
    events = completion(pid, result["loginId"], false)
    payload = TurnFixture.notification(events, "account/login/completed")
    assert payload["error"] =~ "device auth failed with status 500"
    refute updated(events)
    assert count(journal(ctx), "device_poll_started") == 1
    assert count(journal(ctx), "authorization_code_exchange") == 0
    refute File.exists?(auth_path(ctx))
    assert_absent_account(pid)
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "disabled device endpoint returns explicit native error before a login is created", ctx do
    pid = start(ctx, "device_disabled")

    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, "account/login/start", %{"type" => "chatgptDeviceCode"})

    assert error == %{
             "code" => -32_600,
             "message" =>
               "device code login is not enabled for this Codex server. Use the browser login or verify the server URL."
           }

    assert count(journal(ctx), "device_usercode") == 1
    assert count(journal(ctx), "device_poll_started") == 0
    refute File.exists?(auth_path(ctx))
    assert_absent_account(pid)
    assert_profile(ctx, pid)
    close(ctx, pid)
  end

  test "session owner death reaps the owned login controller namespace and native process", ctx do
    pid = start(ctx, "browser_cancel")
    result = call(pid, "account/login/start", %{"type" => "chatgpt"})
    assert result["type"] == "chatgpt"
    owned = owned_pids(ctx)
    %{connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    Process.unlink(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5_000
    assert :ok = Stdio.close(connection)
    assert_reaped(owned)
    refute File.exists?(auth_path(ctx))
  end

  defp start(ctx, scenario) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [@script, "--codex", ctx.binary, "--root", ctx.root, "--scenario", scenario],
             env: %{"CODEX_HOME" => Path.join(ctx.root, "codex")}
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_isolated_auth", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp cancel(pid, id),
    do: assert(call(pid, "account/login/cancel", %{"loginId" => id}) == %{"status" => "canceled"})

  defp completion(pid, id, success) do
    events =
      events_until(pid, fn events ->
        completed =
          TurnFixture.notification(events, "account/login/completed", &(&1["loginId"] == id))

        completed && (not success || updated(events))
      end)

    completed =
      TurnFixture.notification(events, "account/login/completed", &(&1["loginId"] == id))

    assert completed["success"] == success
    assert completed["onboardingEntrypoint"] == nil
    if success, do: assert(completed["error"] == nil), else: assert(is_binary(completed["error"]))
    events
  end

  defp events_until(pid, done),
    do: collect(pid, done, [], System.monotonic_time(:millisecond) + 10_000)

  defp collect(pid, done, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    if done.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline, "native isolated-auth event deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected isolated-auth event gap")
      after
        10 -> :ok
      end

      collect(pid, done, acc, deadline)
    end
  end

  defp await_fixture(ctx, event),
    do: await_fixture(ctx, event, System.monotonic_time(:millisecond) + 5_000)

  defp await_fixture(ctx, event, deadline) do
    if count(journal(ctx), event) > 0 do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "owned fixture barrier #{event}"

      receive do
      after
        10 -> :ok
      end

      await_fixture(ctx, event, deadline)
    end
  end

  defp updated(events), do: TurnFixture.notification(events, "account/updated")

  defp logout(pid) do
    assert call(pid, "account/logout", nil) == %{}

    events =
      events_until(pid, fn events ->
        TurnFixture.notification(events, "account/updated", &is_nil(&1["authMode"]))
      end)

    # Cold startup may independently queue its routed account snapshot. Retain
    # it without prescribing the spawned task's scheduling relative to logout.
    # Require the actual logout update rather than accepting an arbitrary update.
    updates =
      for event <- events, event.wire["method"] == "account/updated", do: event.wire["params"]

    assert %{"authMode" => nil, "planType" => nil} in updates

    assert Enum.all?(updates, fn update ->
             update in [
               %{"authMode" => "chatgpt", "planType" => "pro"},
               %{"authMode" => nil, "planType" => nil}
             ]
           end)
  end

  defp journal(ctx), do: ctx.journal |> File.read!() |> JSON.decode!()
  defp count(journal, event), do: Enum.count(journal["events"], &(&1["event"] == event))
  defp auth_path(ctx), do: Path.join([ctx.root, "codex", "auth.json"])
  defp persisted(ctx), do: ctx |> auth_path() |> File.read!() |> JSON.decode!()

  defp assert_account(pid) do
    account = call(pid, "account/read", %{"refreshToken" => false})

    assert account["account"] == %{
             "type" => "chatgpt",
             "email" => "isolated-auth@synthetic.invalid",
             "planType" => "pro"
           }

    assert account["requiresOpenaiAuth"]
    assert account["workspaceRouting"]["chatgptAccountId"] == "isolated-auth-account"
  end

  defp assert_absent_account(pid) do
    assert call(pid, "account/read", %{})["account"] == nil
    assert {:ok, later} = Session.drain(pid)
    refute updated(later)
  end

  defp assert_profile(ctx, pid) do
    journal = journal(ctx)
    assert journal["namespace"]["parent"] != journal["namespace"]["child"]
    assert journal["namespace"]["interfaces"] == ["lo"]
    assert journal["namespace"]["default_route"] == false
    assert count(journal, "unexpected_request") == 0
    assert count(journal, "fixture_error") == 0
    text = File.read!(ctx.journal)
    refute text =~ "synthetic-isolated-refresh-canary"
    refute text =~ "sk-synthetic-isolated-exchange-canary"

    if File.exists?(auth_path(ctx)) do
      for token <- Map.values(persisted(ctx)["tokens"] || %{}), is_binary(token), token != "" do
        refute text =~ token
      end
    end

    assert {:ok, %{"result" => %{"data" => []}}} = Session.request(pid, "thread/loaded/list", %{})
    assert Session.status(pid).phase == :ready
  end

  defp close(ctx, pid) do
    owned = owned_pids(ctx)
    assert :ok = Session.close(pid)
    assert_reaped(owned)
  end

  defp owned_pids(ctx) do
    started = Enum.find(journal(ctx)["events"], &(&1["event"] == "native_started"))
    Enum.map(["pid", "controller_pid", "namespace_owner_pid"], &Map.fetch!(started, &1))
  end

  defp assert_reaped(pids) do
    for pid <- pids do
      refute File.exists?("/proc/#{pid}"), "owned process must be reaped before teardown"
    end
  end

  defp call(pid, method, params) do
    id = "isolated-auth-request-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, %{"id" => id, "method" => method, "params" => params})

    result
  end
end
