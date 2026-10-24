defmodule SamgitaCodexDriver.NativePlatformGatesProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_platform_gates
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_platform_gates_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @unavailable "User verification is not available in this build or account."
  @verify %{"challenge" => "AQ", "title" => "Owned verification probe", "description" => ""}

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-platform-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      auth: tags.auth,
      experimental: tags.experimental
    }

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

  for auth <- ["none", "synthetic"] do
    @tag auth: auth, experimental: true
    test "Linux exact unavailable and cancellation behavior with #{auth} account", ctx do
      pid = start(ctx)
      assert {:ok, %{"result" => status}} = request(pid, "userVerification/status", %{}, 100)

      assert status == %{
               "credentialId" => nil,
               "unavailableReason" => "providerUnavailable",
               "unavailableMessage" => @unavailable
             }

      assert call(pid, "userVerification/status", %{}) == status

      # 100 has completed; string "100" and integer 404 are unknown targets.
      for target <- [100, 100, "100", "100", 404, 404] do
        assert call(pid, "userVerification/cancel", %{"requestId" => target}) == %{}
      end

      for {method, params} <- [
            {"userVerification/enroll", %{}},
            {"userVerification/delete", %{}},
            {"userVerification/verify", @verify}
          ] do
        assert error(pid, method, params) == %{
                 "code" => -32_603,
                 "message" => @unavailable,
                 "data" => %{"type" => "unavailable", "reason" => "providerUnavailable"}
               }
      end

      for challenge <- ["!", "AQ=="] do
        assert error(pid, "userVerification/verify", Map.put(@verify, "challenge", challenge)) ==
                 %{
                   "code" => -32_602,
                   "message" => "Invalid verification challenge or display text.",
                   "data" => %{"type" => "invalidRequest", "reason" => "invalidParams"}
                 }
      end

      windows_failure(ctx, pid)
      finish(ctx, pid)
    end
  end

  @tag auth: "none", experimental: false
  test "all five verification methods require experimental capability while Windows RPCs remain stable",
       ctx do
    pid = start(ctx)

    for {method, params} <- [
          {"userVerification/status", %{}},
          {"userVerification/enroll", %{}},
          {"userVerification/delete", %{}},
          {"userVerification/verify", @verify},
          {"userVerification/cancel", %{"requestId" => 100}}
        ] do
      assert error(pid, method, params) == %{
               "code" => -32_600,
               "message" => "#{method} requires experimentalApi capability"
             }
    end

    windows_failure(ctx, pid)
    finish(ctx, pid)
  end

  defp windows_failure(ctx, pid) do
    config = File.read!(Path.join(ctx.root, "codex/config.toml"))
    assert call(pid, "windowsSandbox/readiness") == %{"status" => "notConfigured"}

    for {mode, message} <- [
          {"elevated", "elevated Windows sandbox setup is only supported on Windows"},
          {"unelevated", "legacy Windows sandbox setup is only supported on Windows"}
        ] do
      assert call(pid, "windowsSandbox/setupStart", %{"mode" => mode}) == %{"started" => true}

      received =
        collect(
          pid,
          &Enum.any?(&1, fn event ->
            event.wire["method"] == "windowsSandbox/setupCompleted"
          end)
        )

      assert notices(received, "windowsSandbox/setupCompleted") == [
               %{"mode" => mode, "success" => false, "error" => message}
             ]

      assert notices(received, "windows/worldWritableWarning") == []
      assert File.read!(Path.join(ctx.root, "codex/config.toml")) == config
      assert call(pid, "windowsSandbox/readiness") == %{"status" => "notConfigured"}
    end
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               "-I",
               @script,
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--auth",
               ctx.auth,
               "--experimental",
               if(ctx.experimental, do: "yes", else: "no")
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

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_platform_gates", "version" => "1"},
               %{"experimentalApi" => ctx.experimental},
               id: "owned-platform-initialize"
             )

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp request(pid, method, params, id, opts \\ []) do
    wire = %{"id" => id, "method" => method}
    wire = if is_nil(params), do: wire, else: Map.put(wire, "params", params)
    Session.request_native(pid, wire, opts)
  end

  defp request(pid, method, params),
    do: request(pid, method, params, "owned-platform-#{System.unique_integer([:positive])}")

  defp call(pid, method, params \\ nil) do
    assert {:ok, %{"result" => result}} = request(pid, method, params)
    result
  end

  defp error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             request(pid, method, params, "owned-platform-#{System.unique_integer([:positive])}",
               validation: :wire
             )

    error
  end

  defp collect(pid, predicate, received \\ [], remaining \\ 500)
  defp collect(_pid, _predicate, _received, 0), do: flunk("Owned platform notification deadline")

  defp collect(pid, predicate, received, remaining) do
    assert {:ok, current} = Session.drain(pid)

    for event <- current do
      refute event.kind == :server_request

      refute event.wire["method"] in [
               "turn/started",
               "thread/started",
               "error",
               "windows/worldWritableWarning"
             ]
    end

    received = received ++ current

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
    assert {:ok, remaining} = Session.drain(pid)
    refute Enum.any?(remaining, &(&1.kind == :server_request))
    assert notices(remaining, "windowsSandbox/setupCompleted") == []
    assert notices(remaining, "windows/worldWritableWarning") == []
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]

    assert [
             %{
               "auth" => auth,
               "selected_workspace_claim_matches" => matches,
               "access_account_user_claim_present" => matches
             }
           ] =
             Enum.map(events(ctx, "configuration_ready"), &Map.delete(&1, "event"))

    assert auth == ctx.auth and matches == (ctx.auth == "synthetic")
    assert :ok = Session.close(pid)
    wait(fn -> events(ctx, "native_closed") != [] end)
    assert events(ctx, "fixture_error") == []

    assert events(ctx, "configuration_unchanged") == [
             %{"event" => "configuration_unchanged", "config_bytes" => true, "auth_bytes" => true}
           ]

    assert events(ctx, "secret_scan") == [%{"event" => "secret_scan", "passed" => true}]

    for event <- events(ctx, "http_denied") do
      assert event["status"] == 403 and event["method"] == "GET"

      assert event["path"] in [
               "/api/codex/config/bundle",
               "/api/codex/accounts/check",
               "/api/codex/settings/user"
             ]
    end
  end

  defp notices(received, method),
    do: for(event <- received, event.wire["method"] == method, do: event.wire["params"])

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned platform observation deadline")

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
