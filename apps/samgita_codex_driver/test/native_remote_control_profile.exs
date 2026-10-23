defmodule SamgitaCodexDriver.NativeRemoteControlProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_remote_control
  @moduletag timeout: 90_000
  @script Path.expand("../../../scripts/codex/isolated_remote_control_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @installation "11111111-2222-4333-8444-555555555555"
  @environment "owned-environment"
  @encoded_environment "owned/环境 λ"
  @pairing "synthetic-owned-remote-pairing"
  @manual "SYNTHETIC-MANUAL"
  @changed "remoteControl/status/changed"
  @methods [
    {"remoteControl/enable", %{"ephemeral" => true}},
    {"remoteControl/disable", %{"ephemeral" => true}},
    {"remoteControl/status/read", nil},
    {"remoteControl/pairing/start", %{}},
    {"remoteControl/pairing/status", %{"pairingCode" => @pairing}},
    {"remoteControl/client/list", %{"environmentId" => @environment}},
    {"remoteControl/client/revoke",
     %{"environmentId" => @environment, "clientId" => "owned-phone"}}
  ]

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-remote-control-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    ctx = %{
      binary: Path.expand(binary),
      root: root,
      auth: tags[:auth] || "chatgpt",
      invalid_url: tags[:invalid_url] || false
    }

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid) do
          wait(fn -> not File.exists?("/proc/#{started[key]}") end)
        end

        assert length(events(ctx, "native_started")) == length(events(ctx, "native_closed"))
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  test "disabled status and pairing/client validation reject before backend dispatch", ctx do
    pid = start(ctx)
    status = call(pid, "remoteControl/status/read", nil)
    assert_status(status, "disabled", nil)
    assert notification(pid, "disabled") == status

    for {method, params, message} <- [
          {"remoteControl/pairing/start", %{}, "requires remote control to be enabled"},
          {"remoteControl/pairing/status", %{"pairingCode" => @pairing},
           "requires remote control to be enabled"},
          {"remoteControl/pairing/status", %{}, "requires pairingCode or manualPairingCode"},
          {"remoteControl/pairing/status",
           %{"pairingCode" => @pairing, "manualPairingCode" => @manual}, "not both"},
          {"remoteControl/client/list", %{"environmentId" => ""}, "requires environmentId"},
          {"remoteControl/client/list", %{"environmentId" => @environment, "limit" => 0},
           "between 1 and 100"},
          {"remoteControl/client/list", %{"environmentId" => @environment, "limit" => 101},
           "between 1 and 100"},
          {"remoteControl/client/revoke", %{"environmentId" => "", "clientId" => "owned-phone"},
           "requires environmentId"},
          {"remoteControl/client/revoke", %{"environmentId" => @environment, "clientId" => ""},
           "requires clientId"}
        ] do
      failure = error(pid, method, params)
      assert failure["code"] == -32_600
      assert failure["message"] =~ message
    end

    assert requests(ctx) == []
    finish(ctx, pid)
  end

  test "all seven experimental methods are gated independently by driver and native", ctx do
    pid = start(ctx, false)
    assert_status(notification(pid, "disabled"), "disabled", nil)

    for {method, params} <- @methods do
      count = length(events(ctx, "native_input"))

      assert {:error, %Error{code: :experimental_api_required, uncertain: false}} =
               Session.request(pid, method, params)

      assert length(events(ctx, "native_input")) == count
      failure = error(pid, method, params, validation: :wire)
      assert failure["code"] == -32_600
      assert failure["message"] =~ "experimentalApi"
    end

    assert requests(ctx) == []
    finish(ctx, pid)
  end

  test "enrollment hold exposes native connecting then real WS connected and disabled", ctx do
    plan(ctx, "enroll", [%{"hold" => "enrollment"}])
    pid = start(ctx)
    notification(pid, "disabled")
    assert_status(call(pid, "remoteControl/enable", %{"ephemeral" => true}), "connecting", nil)
    assert_status(notification(pid, "connecting"), "connecting", nil)
    wait(fn -> length(requests(ctx, "enroll")) == 1 end)
    assert_status(call(pid, "remoteControl/status/read", nil), "connecting", nil)
    assert events(ctx, "websocket_connected") == []
    release(ctx, "enrollment")
    connected = notification(pid, "connected")
    assert_status(connected, "connected", @environment)
    assert call(pid, "remoteControl/status/read", nil) == connected
    wait(fn -> length(events(ctx, "websocket_connected")) == 1 end)
    disabled = call(pid, "remoteControl/disable", %{"ephemeral" => true})
    assert_status(disabled, "disabled", nil)
    assert notification(pid, "disabled") == disabled
    wait(fn -> length(events(ctx, "websocket_closed")) == 1 end)
    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1}
    finish(ctx, pid)
    assert [%{"remote_control_enabled" => nil}] = rows(ctx)
  end

  test "ephemeral enrollment persists identity without auto-enabling on owned restart", ctx do
    pid = start(ctx)
    enable(ctx, pid)
    restart(ctx, pid)
    assert [%{"remote_control_enabled" => nil}] = rows(ctx)
    assert_status(notification(pid, "disabled"), "disabled", nil)
    assert_status(call(pid, "remoteControl/status/read", nil), "disabled", nil)
    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1}
    assert events(ctx, "native_started") |> Enum.map(& &1["generation"]) == [1, 2]
    finish(ctx, pid)
  end

  test "omitted enable and null disable persist preference across native replacements", ctx do
    pid = start(ctx)

    assert call(pid, "remoteControl/enable", nil, params_present: false)["environmentId"] ==
             @environment

    before = notification(pid, "connected")
    assert_status(before, "connected", @environment)
    restart(ctx, pid)
    assert [%{"remote_control_enabled" => true, "server_id" => "owned-server"}] = rows(ctx)
    assert notification(pid, "connected") == before
    wait(fn -> length(events(ctx, "websocket_connected")) == 2 end)
    assert counts(ctx) == %{"enroll" => 1, "refresh" => 1, "websocket" => 2}
    assert Enum.map(events(ctx, "websocket_connected"), & &1["bearer_slot"]) == [1, 2]
    assert_status(call(pid, "remoteControl/disable", %{"ephemeral" => true}), "disabled", nil)
    notification(pid, "disabled")
    restart(ctx, pid)
    assert [%{"remote_control_enabled" => true}] = rows(ctx)
    assert notification(pid, "connected") == before
    wait(fn -> length(events(ctx, "websocket_connected")) == 3 end)
    assert_status(call(pid, "remoteControl/disable", nil), "disabled", nil)
    notification(pid, "disabled")
    restart(ctx, pid)
    assert [%{"remote_control_enabled" => false}] = rows(ctx)
    assert_status(notification(pid, "disabled"), "disabled", nil)
    assert counts(ctx) == %{"enroll" => 1, "refresh" => 2, "websocket" => 3}
    finish(ctx, pid)
  end

  test "both pairing modes and both claim states preserve native public mapping", ctx do
    pid = start(ctx)
    enable(ctx, pid)

    for manual <- [false, true] do
      result = call(pid, "remoteControl/pairing/start", %{"manualCode" => manual})

      assert result == %{
               "pairingCode" => @pairing,
               "manualPairingCode" => if(manual, do: @manual, else: nil),
               "environmentId" => @environment,
               "expiresAt" => 2_082_758_400
             }

      params =
        if manual, do: %{"manualPairingCode" => @manual}, else: %{"pairingCode" => @pairing}

      for claimed <- [false, true] do
        plan(ctx, "pair_status", [%{"body" => %{"claimed" => claimed}}])
        assert call(pid, "remoteControl/pairing/status", params) == %{"claimed" => claimed}
      end
    end

    assert Enum.map(requests(ctx, "pair"), & &1["manual_code"]) == [false, true]

    assert Enum.map(requests(ctx, "pair_status"), & &1["code_kind"]) == [
             "pairing",
             "pairing",
             "manual",
             "manual"
           ]

    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "pair" => 2, "pair_status" => 4}
    finish(ctx, pid)
  end

  test "pairing server-token denial refreshes once and retries with replacement bearer", ctx do
    plan(ctx, "pair", [%{"status" => 401, "body" => %{"error" => "owned token expired"}}, %{}])
    pid = start(ctx)
    enable(ctx, pid)
    assert call(pid, "remoteControl/pairing/start", %{})["pairingCode"] == @pairing
    assert Enum.map(requests(ctx, "pair"), & &1["bearer_slot"]) == [1, 2]
    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "pair" => 2, "refresh" => 1}
    finish(ctx, pid)
  end

  test "pairing status server-token denial refreshes once before returning claimed", ctx do
    plan(ctx, "pair_status", [
      %{"status" => 401, "body" => %{"error" => "owned token expired"}},
      %{"body" => %{"claimed" => true}}
    ])

    pid = start(ctx)
    enable(ctx, pid)

    assert call(pid, "remoteControl/pairing/status", %{"pairingCode" => @pairing}) == %{
             "claimed" => true
           }

    assert Enum.map(requests(ctx, "pair_status"), & &1["bearer_slot"]) == [1, 2]
    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "pair_status" => 2, "refresh" => 1}
    finish(ctx, pid)
  end

  test "pairing expired codes and malformed or mismatched backend data retain native errors",
       ctx do
    pid = start(ctx)
    enable(ctx, pid)
    plan(ctx, "pair_status", [%{"status" => 410, "body" => %{"error" => "owned expired code"}}])

    assert error(pid, "remoteControl/pairing/status", %{"pairingCode" => @pairing})["code"] ==
             -32_600

    for change <- [
          %{"body_patch" => %{"server_id" => "owned-wrong-server"}},
          %{"body_patch" => %{"expires_at" => "owned-invalid-time"}},
          %{"raw_response" => "owned-invalid-json"}
        ] do
      plan(ctx, "pair", [change])
      assert error(pid, "remoteControl/pairing/start", %{})["code"] == -32_603
    end

    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "pair" => 3, "pair_status" => 1}
    finish(ctx, pid)
  end

  test "disabled client pagination and URL encoding preserve metadata and actual revoke effects",
       ctx do
    pid = start(ctx)

    params = %{
      "environmentId" => @encoded_environment,
      "cursor" => "owned-first λ",
      "limit" => 1,
      "order" => "desc"
    }

    first = call(pid, "remoteControl/client/list", params)
    assert first["nextCursor"] == "owned-next"
    assert [client] = first["data"]

    assert client == %{
             "clientId" => "owned-phone",
             "displayName" => "Owned λ phone",
             "deviceType" => "phone",
             "platform" => "synthetic",
             "osVersion" => "1",
             "deviceModel" => "owned",
             "appVersion" => "2",
             "lastSeenAt" => 1_781_395_200
           }

    second = call(pid, "remoteControl/client/list", Map.put(params, "cursor", "owned-next"))
    assert second["nextCursor"] == nil
    assert [minimal] = second["data"]
    assert minimal["clientId"] == "owned/client λ"
    assert minimal |> Map.delete("clientId") |> Map.values() |> Enum.all?(&is_nil/1)

    assert call(pid, "remoteControl/client/revoke", %{
             "environmentId" => @encoded_environment,
             "clientId" => "owned-phone"
           }) == %{}

    assert call(pid, "remoteControl/client/list", %{"environmentId" => @encoded_environment}) ==
             %{"data" => [minimal], "nextCursor" => nil}

    assert call(pid, "remoteControl/client/revoke", %{
             "environmentId" => @encoded_environment,
             "clientId" => "owned/client λ"
           }) == %{}

    assert call(pid, "remoteControl/client/list", %{"environmentId" => @encoded_environment}) ==
             %{"data" => [], "nextCursor" => nil}

    assert_status(call(pid, "remoteControl/status/read", nil), "disabled", nil)
    assert counts(ctx) == %{"list" => 4, "revoke" => 2}
    assert Enum.all?(requests(ctx), & &1["encoded_path_verified"])
    finish(ctx, pid)
  end

  test "enabled client management uses account bearer and deterministic native backend errors",
       ctx do
    pid = start(ctx)
    enable(ctx, pid)
    params = %{"environmentId" => @environment}
    assert length(call(pid, "remoteControl/client/list", params)["data"]) == 2

    assert call(pid, "remoteControl/client/revoke", Map.put(params, "clientId", "owned-phone")) ==
             %{}

    assert [%{"clientId" => "owned/client λ"}] =
             call(pid, "remoteControl/client/list", params)["data"]

    for {reply, code} <- [
          {%{"status" => 403, "body" => %{"error" => "owned denied"}}, -32_600},
          {%{"status" => 404, "body" => %{"error" => "owned absent"}}, -32_600},
          {%{"status" => 500, "body" => %{"error" => "owned server failure"}}, -32_603},
          {%{"raw_response" => "owned-invalid-json"}, -32_603},
          {%{
             "body" => %{
               "items" => [%{"client_id" => "owned-phone", "last_seen_at" => "invalid-time"}]
             }
           }, -32_603}
        ] do
      plan(ctx, "list", [reply])
      assert error(pid, "remoteControl/client/list", params)["code"] == code
    end

    plan(ctx, "revoke", [%{"status" => 500, "body" => %{"error" => "owned revoke failure"}}])

    assert error(pid, "remoteControl/client/revoke", Map.put(params, "clientId", "owned-phone"))[
             "code"
           ] == -32_603

    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "list" => 7, "revoke" => 2}
    finish(ctx, pid)
  end

  test "malformed parameters fail client schema and actual native parsing independently", ctx do
    pid = start(ctx)

    for {method, params} <- [
          {"remoteControl/enable", %{"ephemeral" => "yes"}},
          {"remoteControl/disable", %{"ephemeral" => 1}},
          {"remoteControl/pairing/start", %{"manualCode" => "yes"}},
          {"remoteControl/pairing/status", %{"pairingCode" => 7}},
          {"remoteControl/client/list", %{"environmentId" => @environment, "order" => "newest"}},
          {"remoteControl/client/revoke", %{"environmentId" => @environment}}
        ] do
      count = length(events(ctx, "native_input"))

      assert {:error, %Error{code: :schema_violation, uncertain: false}} =
               Session.request(pid, method, params)

      assert length(events(ctx, "native_input")) == count
      failure = error(pid, method, params, validation: :wire)
      assert failure["code"] == -32_600
      assert failure["message"] =~ "Invalid request:"
      assert length(events(ctx, "native_input")) == count + 1
    end

    assert requests(ctx) == []
    finish(ctx, pid)
  end

  for auth <- ~w(no_auth api_key) do
    @tag auth: auth
    test "#{auth} persistent auth gate and ephemeral errored status make no enrollment", ctx do
      pid = start(ctx)
      failure = error(pid, "remoteControl/enable", nil)
      assert failure["code"] == -32_600

      reason =
        if ctx.auth == "api_key",
          do: "remote control requires ChatGPT authentication; API key auth is not supported",
          else: "remote control requires ChatGPT authentication"

      assert failure["message"] == reason
      initial = call(pid, "remoteControl/enable", %{"ephemeral" => true})
      assert initial["status"] in ["connecting", "errored"]
      assert_status(initial, initial["status"], nil)
      assert_status(notification(pid, "errored"), "errored", nil)
      assert_status(call(pid, "remoteControl/status/read", nil), "errored", nil)
      assert requests(ctx) == []
      finish(ctx, pid)
    end
  end

  @tag invalid_url: true
  test "invalid backend URL emits native errored without attempting an unapproved destination",
       ctx do
    pid = start(ctx)
    call(pid, "remoteControl/enable", %{"ephemeral" => true})
    assert_status(notification(pid, "errored"), "errored", nil)
    assert_status(call(pid, "remoteControl/status/read", nil), "errored", nil)
    assert_status(call(pid, "remoteControl/disable", %{"ephemeral" => true}), "disabled", nil)
    assert requests(ctx) == []
    finish(ctx, pid)
  end

  test "timed-out pairing retains uncertainty through late response and owned reconnect without replay",
       ctx do
    plan(ctx, "pair", [%{"hold" => "pairing"}])
    pid = start(ctx)
    enable(ctx, pid)

    task =
      Task.async(fn ->
        Session.request(pid, "remoteControl/pairing/start", %{},
          id: "owned-ambiguous-pair",
          timeout_ms: 1_000
        )
      end)

    wait(fn -> length(requests(ctx, "pair")) == 1 end)
    assert {:error, %Error{code: :deadline_exceeded, uncertain: true}} = Task.await(task)

    assert [%{id: "owned-ambiguous-pair", method: "remoteControl/pairing/start"}] =
             Session.uncertain_operations(pid)

    release(ctx, "pairing")

    received =
      collect(pid, fn event ->
        event.kind == :late_response and event.wire["id"] == "owned-ambiguous-pair"
      end)

    assert Enum.any?(
             received,
             &(&1.kind == :late_response and &1.wire["result"]["pairingCode"] == @pairing)
           )

    restart(ctx, pid)
    assert [%{id: "owned-ambiguous-pair"}] = Session.uncertain_operations(pid)
    assert_status(notification(pid, "disabled"), "disabled", nil)
    assert counts(ctx) == %{"enroll" => 1, "websocket" => 1, "pair" => 1}
    finish(ctx, pid)
  end

  defp start(ctx, experimental \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args:
               [@script, "--codex", ctx.binary, "--root", ctx.root, "--auth", ctx.auth] ++
                 if(ctx.invalid_url, do: ["--invalid-url"], else: []),
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
    initialize(ctx, pid, experimental)
    pid
  end

  defp initialize(ctx, pid, experimental) do
    generation = Session.status(pid).generation

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_remote_control", "version" => "1"}, %{
               "experimentalApi" => experimental
             })

    wait(fn ->
      Enum.any?(
        events(ctx, "native_input"),
        &(&1["method"] == "initialized" and &1["generation"] == generation)
      )
    end)
  end

  defp restart(ctx, pid) do
    atomic(ctx, "launch.json", %{"force_disabled" => false})
    count = length(events(ctx, "native_started"))
    assert :ok = Session.reconnect(pid)
    initialize(ctx, pid, true)
    assert length(events(ctx, "native_started")) == count + 1
    assert length(events(ctx, "native_closed")) == count
  end

  defp enable(ctx, pid) do
    plan(ctx, "enroll", [%{"hold" => "helper-enrollment"}])
    assert_status(call(pid, "remoteControl/enable", %{"ephemeral" => true}), "connecting", nil)
    wait(fn -> length(requests(ctx, "enroll")) == 1 end)
    assert events(ctx, "websocket_connected") == []
    assert_status(call(pid, "remoteControl/status/read", nil), "connecting", nil)
    release(ctx, "helper-enrollment")
    status = notification(pid, "connected")
    assert_status(status, "connected", @environment)
    wait(fn -> length(events(ctx, "websocket_connected")) == 1 end)
  end

  defp finish(ctx, pid) do
    assert call(pid, "thread/loaded/list", %{}) == %{"data" => [], "nextCursor" => nil}
    assert Session.status(pid).phase == :ready
    assert Session.status(pid).interactions == 0
    assert {:ok, received} = Session.drain(pid, 10_000)

    assert Enum.all?(
             received,
             &(&1.kind != :server_request and &1.wire["method"] != "turn/started")
           )

    assert :ok = Session.close(pid)
    assert length(events(ctx, "native_started")) == length(events(ctx, "native_closed"))
    assert_isolation(ctx)
    assert_backend(ctx)
    assert_closed(ctx)
  end

  defp assert_isolation(ctx) do
    for proof <- journal(ctx)["namespaces"] do
      assert proof["parent"] == File.read_link!("/proc/self/ns/net")
      assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
      assert proof["parent_user"] != proof["child_user"]
      refute proof["default_route"]
      refute proof["ipv6_default_route"]
    end
  end

  defp assert_backend(ctx) do
    for event <- requests(ctx) do
      assert event["bearer_verified"] and event["host_verified"] and event["body_verified"]

      if event["resource"] in ~w(enroll refresh list revoke),
        do: assert(event["account_verified"])
    end

    for event <- events(ctx, "websocket_connected"), do: assert(event["headers_verified"])
  end

  defp assert_closed(ctx) do
    for event <- events(ctx, "native_closed") do
      assert event["canary_absent"] and event["redaction_checked"] and event["reader_stopped"]
      assert event["native_reaped"] and event["backend_stopped"] and event["sqlite_tokens_absent"]
    end

    for name <-
          ~w(unexpected_http forbidden_body fixture_error forbidden_native forbidden_output unexpected_request forbidden_websocket),
        do: assert(events(ctx, name) == [])
  end

  defp assert_status(status, expected, environment) do
    assert Map.keys(status) |> Enum.sort() == ~w(environmentId installationId serverName status)
    assert status["status"] == expected and status["environmentId"] == environment
    assert status["installationId"] == @installation and is_binary(status["serverName"])
  end

  defp notification(pid, status) do
    received =
      collect(pid, fn event ->
        event.wire["method"] == @changed and event.wire["params"]["status"] == status
      end)

    received
    |> Enum.find(&(&1.wire["method"] == @changed and &1.wire["params"]["status"] == status))
    |> Map.fetch!(:wire)
    |> Map.fetch!("params")
  end

  defp collect(pid, predicate, acc \\ [], remaining \\ 1_000)
  defp collect(_pid, _predicate, _acc, 0), do: flunk("Owned remote-control native event deadline")

  defp collect(pid, predicate, acc, remaining) do
    assert {:ok, current} = Session.drain(pid, 10_000)
    received = acc ++ current

    if Enum.any?(received, predicate) do
      received
    else
      Process.sleep(10)
      collect(pid, predicate, received, remaining - 1)
    end
  end

  defp plan(ctx, resource, replies) do
    path = Path.join(ctx.root, "responses.json")
    current = if File.exists?(path), do: path |> File.read!() |> JSON.decode!(), else: %{}

    atomic(
      ctx,
      "responses.json",
      Map.put(current, resource, %{
        "revision" => System.unique_integer([:positive]),
        "replies" => replies
      })
    )
  end

  defp atomic(ctx, name, value) do
    path = Path.join(ctx.root, name)
    File.write!(path <> ".pending", JSON.encode!(value))
    File.rename!(path <> ".pending", path)
  end

  defp release(ctx, name),
    do: File.write!(Path.join(ctx.root, "release-#{name}"), "owned release")

  defp call(pid, method, params, opts \\ []) do
    id = "owned-call-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, Keyword.put(opts, :id, id))

    result
  end

  defp error(pid, method, params, opts \\ []) do
    id = "owned-error-#{System.unique_integer([:positive])}"

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => failure}}} =
             Session.request(pid, method, params, Keyword.put(opts, :id, id))

    failure
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp requests(ctx), do: events(ctx, "http")
  defp requests(ctx, resource), do: Enum.filter(requests(ctx), &(&1["resource"] == resource))
  defp counts(ctx), do: Enum.frequencies_by(requests(ctx), & &1["resource"])
  defp rows(ctx), do: events(ctx, "native_closed") |> List.last() |> Map.fetch!("enrollments")

  defp wait(predicate, remaining \\ 1_000)
  defp wait(_predicate, 0), do: flunk("Owned remote-control fixture observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      wait(predicate, remaining - 1)
    end
  end
end
