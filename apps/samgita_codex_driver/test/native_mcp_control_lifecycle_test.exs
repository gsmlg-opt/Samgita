defmodule SamgitaCodexDriver.NativeMcpControlLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_mcp_control_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @missing "00000000-0000-4000-8000-000000000000"
  @stream_method "mcpServer/event/stream/notification"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-control-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))
    profile = tags[:profile] || "status"

    ctx = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      socket: Path.join(root, "native.sock")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary), "--profile", profile],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = Map.put(ctx, :owner, owner)

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)

        for pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do: wait(fn -> not File.exists?("/proc/#{pid}") end)

        assert events(ctx, "fixture_closed") != []
      end

      File.rm_rf!(root)
    end)

    wait(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    ctx
  end

  test "M1 full native status inventories preserve fields pages detail and live connection reuse",
       ctx do
    pid = connect(ctx)
    result = call(pid, "mcpServerStatus/list", %{})
    assert Enum.map(result["data"], & &1["name"]) == ["alpha", "beta"]
    assert result["nextCursor"] == nil
    assert_inventory(ctx, Enum.at(result["data"], 0), "alpha", "a", nil)
    assert_inventory(ctx, Enum.at(result["data"], 1), "beta", "b", nil)
    assert Enum.map(result["data"], &Map.fetch!(&1, "runtimeStatus")) === [nil, nil]

    first = call(pid, "mcpServerStatus/list", %{"limit" => 1})
    assert Enum.map(first["data"], & &1["name"]) == ["alpha"]
    assert first["nextCursor"] == "1"
    second = call(pid, "mcpServerStatus/list", %{"limit" => 1, "cursor" => first["nextCursor"]})
    assert Enum.map(second["data"], & &1["name"]) == ["beta"]
    assert second["nextCursor"] == nil
    assert call(pid, "mcpServerStatus/list", %{"limit" => 0}) == first

    assert error(pid, "mcpServerStatus/list", %{"cursor" => "not-a-cursor"})["message"] ==
             "invalid cursor: not-a-cursor"

    assert error(pid, "mcpServerStatus/list", %{"cursor" => "3"})["message"] ==
             "cursor 3 exceeds total MCP servers 2"

    thread = thread(ctx, pid)
    selected = %{"threadId" => thread, "serverName" => "alpha"}

    assert %{"data" => [full], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", Map.put(selected, "detail", "full"))

    assert_inventory(ctx, full, "alpha", "a", "connected")
    initializations = mcp_count(ctx, "/inventory/a", "initialize")
    resources = mcp_count(ctx, "/inventory/a", "resources/list")
    templates = mcp_count(ctx, "/inventory/a", "resources/templates/list")

    assert %{"data" => [short], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", Map.put(selected, "detail", "toolsAndAuthOnly"))

    assert short["name"] == "alpha" and short["tools"] == full["tools"]
    assert short["authStatus"] == "bearerToken" and short["runtimeStatus"] == "connected"
    assert short["resources"] == [] and short["resourceTemplates"] == []
    assert mcp_count(ctx, "/inventory/a", "initialize") == initializations
    assert mcp_count(ctx, "/inventory/a", "resources/list") == resources
    assert mcp_count(ctx, "/inventory/a", "resources/templates/list") == templates
    assert_profile(ctx, [pid])
  end

  test "M2 native reload updates a loaded thread and recovers after strict malformed config",
       ctx do
    pid = connect(ctx)
    thread = thread(ctx, pid)
    selected = %{"threadId" => thread, "serverName" => "beta", "detail" => "full"}
    assert %{"data" => [before]} = call(pid, "mcpServerStatus/list", selected)
    assert before["serverInfo"]["name"] == "owned-b"
    control(ctx, "config", %{"generation" => 2})
    assert call(pid, "config/mcpServer/reload", nil) == %{}
    assert %{"data" => [after_reload]} = call(pid, "mcpServerStatus/list", selected)
    assert_inventory(ctx, after_reload, "beta", "b-v2", "connected")
    assert mcp_count(ctx, "/inventory/b-v2", "initialize") > 0

    control(ctx, "malformed-config")
    failure = error(pid, "config/mcpServer/reload", nil)
    assert failure["message"] =~ "failed to refresh MCP servers:"
    # Native strict failure may follow partial publication. No rollback assertion.
    control(ctx, "config", %{"generation" => 2})
    assert call(pid, "config/mcpServer/reload", nil) == %{}
    assert %{"data" => [recovered]} = call(pid, "mcpServerStatus/list", selected)
    assert_inventory(ctx, recovered, "beta", "b-v2", "connected")
    assert_profile(ctx, [pid])
  end

  @tag profile: "oauth"
  test "M3 native OAuth correlates callback completion and cold file credential reuse", ctx do
    pid = connect(ctx)
    thread = thread(ctx, pid)
    %{instance_id: instance, generation: generation} = Session.status(pid)
    assert_oauth_logged_out(ctx, pid, thread, "notLoggedIn")
    assert events(ctx, "token_exchange") == []
    assert events(ctx, "callback_sent") == []
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))

    failed =
      startup_notice(
        thread,
        "oauth",
        "failed",
        "The oauth MCP server is not logged in. Run `codex mcp login oauth`."
      )

    received = collect(pid, &(failed in startup_notices(&1, thread, "oauth")))

    assert startup_notices(received, thread, "oauth") === [
             startup_notice(thread, "oauth", "starting"),
             failed
           ]

    assert_startup_observer_ready(ctx, pid, instance, generation, received)
    login = oauth_login(pid, thread)
    url = URI.parse(login["authorizationUrl"])
    assert url.scheme == "http" and url.path == "/oauth/authorize"
    assert URI.to_string(%{url | path: "", query: nil}) == state(ctx)["endpoint"]
    query = URI.decode_query(url.query)
    assert query["client_id"] == "owned-mcp-client"
    assert query["response_type"] == "code" and query["code_challenge_method"] == "S256"
    assert is_binary(query["code_challenge"]) and byte_size(query["code_challenge"]) > 20
    assert String.split(query["scope"]) == ["read:owned", "inspect:owned"]
    redirect = URI.parse(query["redirect_uri"])
    assert redirect.scheme == "http" and redirect.host == "127.0.0.1"
    assert is_integer(redirect.port) and redirect.path == "/callback/owned-mcp"
    control(ctx, "callback", %{"url" => login["authorizationUrl"], "variant" => "success"})
    received = collect(pid, &oauth_completion(&1, login["loginId"]))
    completion = oauth_completion(received, login["loginId"])

    assert completion == %{
             "name" => "oauth",
             "threadId" => thread,
             "loginId" => login["loginId"],
             "success" => true
           }

    assert [exchange] = events(ctx, "token_exchange")
    assert exchange["accepted"] and exchange["pkce_verified"] and exchange["redirect_verified"]
    assert control(ctx, "probe-callback")["callback_open"] == false
    assert File.regular?(Path.join(ctx.root, "codex/.credentials.json"))

    # OAuth completion invalidates runtimes and prewarms a fresh authenticated
    # client. Observe its real ready notice before a separate explicit reload.
    assert_authenticated(ctx, pid, thread)

    ready = startup_notice(thread, "oauth", "ready")
    recovered = collect(pid, &(ready in startup_notices(&1, thread, "oauth")), received)

    assert startup_notices(recovered, thread, "oauth") === [
             startup_notice(thread, "oauth", "starting"),
             ready
           ]

    assert_startup_observer_ready(ctx, pid, instance, generation, recovered)
    authenticated_before_reload = authenticated_initializations(ctx)
    assert call(pid, "config/mcpServer/reload", nil) == %{}
    assert_authenticated(ctx, pid, thread)

    # The pin republishes ready for a reused connection, with no new starting
    # or initialize. This is a distinct publication, not an arbitrary duplicate.
    reused = collect(pid, &(ready in startup_notices(&1, thread, "oauth")))
    assert startup_notices(reused, thread, "oauth") === [ready]
    assert authenticated_initializations(ctx) == authenticated_before_reload
    assert_startup_observer_ready(ctx, pid, instance, generation, reused)
    authenticated_before_restart = authenticated_initializations(ctx)

    assert :ok = Session.close(pid)
    old_native = state(ctx)["native_pid"]
    control(ctx, "restart")
    assert state(ctx)["native_pid"] != old_native
    refute File.exists?("/proc/#{old_native}")
    cold = connect(ctx)
    assert_authenticated(ctx, cold, thread(ctx, cold))
    assert authenticated_initializations(ctx) > authenticated_before_restart
    assert length(events(ctx, "token_exchange")) == 1
    assert length(events(ctx, "callback_sent")) == 1
    assert_profile(ctx, [cold])
  end

  @tag profile: "oauth"
  test "M4 native OAuth failures correlate and never persist usable credentials", ctx do
    pid = connect(ctx)

    for variant <- ["wrong-issuer", "denied"] do
      login = oauth_login(pid, nil)
      control(ctx, "callback", %{"url" => login["authorizationUrl"], "variant" => variant})
      received = collect(pid, &oauth_completion(&1, login["loginId"]))
      completion = oauth_completion(received, login["loginId"])
      assert completion["name"] == "oauth" and completion["threadId"] == nil
      assert completion["loginId"] == login["loginId"] and completion["success"] == false
      assert is_binary(completion["error"]) and completion["error"] != ""
      assert control(ctx, "probe-callback")["callback_open"] == false
      assert events(ctx, "token_exchange") == []
      refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    end

    assert error(pid, "mcpServer/oauth/login", %{"name" => "absent"})["message"] ==
             "No MCP server named 'absent' found."

    assert error(pid, "mcpServer/oauth/login", %{"name" => "oauth", "threadId" => @missing})[
             "message"
           ] == "thread not found: #{@missing}"

    assert error(pid, "mcpServer/oauth/login", %{"name" => "oauth", "threadId" => "invalid"})[
             "message"
           ] =~ "invalid thread id:"

    assert events(ctx, "token_exchange") == []
    assert_profile(ctx, [pid])
  end

  @tag profile: "events"
  test "M5 native event eligibility rejects other servers and unsubscribed invalid threads",
       ctx do
    pid = connect(ctx)
    thread = thread(ctx, pid)
    second = connect(ctx)
    nonhosted = stream_params(thread, "rejected-server") |> Map.put("server", "inventory")

    assert error(pid, "mcpServer/event/stream/start", nonhosted)["message"] ==
             "MCP event subscriptions are only supported for hosted apps"

    assert error(pid, "mcpServer/event/stream/start", stream_params("invalid", "invalid-thread"))[
             "message"
           ] =~ "invalid thread id:"

    assert error(pid, "mcpServer/event/stream/start", stream_params(@missing, "missing-thread"))[
             "message"
           ] =~ "connection is not subscribed to thread"

    assert error(second, "mcpServer/event/stream/start", stream_params(thread, "unsubscribed"))[
             "message"
           ] =~ "connection is not subscribed to thread"

    assert error(
             pid,
             "mcpServer/event/stream/start",
             Map.put(stream_params(thread, "bad-meta"), "_meta", [1])
           )["message"] =~ "_meta must be a JSON object"

    assert events(ctx, "stream_opened") == []
    assert_profile(ctx, [pid, second])
  end

  @tag profile: "events"
  test "M6 native activation gates start reserves duplicates and routes exact notices", ctx do
    pid = connect(ctx)
    other = connect(ctx)
    thread = thread(ctx, pid)
    params = stream_params(thread, "owned-subscription")
    task = Task.async(fn -> Session.request(pid, "mcpServer/event/stream/start", params) end)
    stream = wait(fn -> List.first(events(ctx, "stream_opened")) end)
    assert stream["params"]["name"] == params["name"]
    assert stream["params"]["arguments"] == params["arguments"]
    assert stream["params"]["_meta"]["source"] == "owned-client"
    assert Map.has_key?(stream["params"]["_meta"], "progressToken")
    assert Task.yield(task, 100) == nil

    assert error(pid, "mcpServer/event/stream/start", params)["message"] ==
             "MCP event subscription 'owned-subscription' already exists"

    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "wrong-id"})
    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "missing-id"})
    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "active"})
    await_started(task)
    active = collect(pid, &stream_notice(&1, "owned-subscription", "notifications/events/active"))

    assert stream_notice(active, "owned-subscription", "notifications/events/active") ==
             native_notice(stream, "owned-subscription", "active")

    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "event"})

    received =
      collect(pid, &stream_notice(&1, "owned-subscription", "notifications/events/event"))

    assert stream_notice(received, "owned-subscription", "notifications/events/event") ==
             native_notice(stream, "owned-subscription", "event")

    assert stream_notices(active ++ received) == [
             native_notice(stream, "owned-subscription", "active"),
             native_notice(stream, "owned-subscription", "event")
           ]

    assert stream_notices(drain(other)) == []

    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "owned-subscription"}) ==
             %{}

    cancelled(ctx, stream)
    assert_profile(ctx, [pid, other])
  end

  @tag profile: "events"
  test "M7 native stop unsubscribe and connection-close cancel only owned subscriptions", ctx do
    pid = connect(ctx)
    thread = thread(ctx, pid)
    stream = active_stream(ctx, pid, thread, "stop-owned")
    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "stop-owned"}) == %{}
    cancelled(ctx, stream)
    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "stop-owned"}) == %{}
    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "unknown-owned"}) == %{}
    assert stream_notices(drain(pid)) == []

    # Reuse the native MCP connection so the old request ID is truly stale.
    guard = active_stream(ctx, pid, thread, "guard-owned")
    assert guard["request_id"] != stream["request_id"]
    control(ctx, "emit", %{"stream" => guard["stream"], "kind" => "late"})
    control(ctx, "emit", %{"stream" => guard["stream"], "kind" => "event"})
    received = collect(pid, &stream_notice(&1, "guard-owned", "notifications/events/event"))
    assert stream_notices(received) == [native_notice(guard, "guard-owned", "event")]

    unsubscribe_thread = thread(ctx, pid)
    unsubscribed = active_stream(ctx, pid, unsubscribe_thread, "unsubscribe-owned")
    assert is_map(call(pid, "thread/unsubscribe", %{"threadId" => unsubscribe_thread}))
    cancelled(ctx, unsubscribed)
    control(ctx, "emit", %{"stream" => guard["stream"], "kind" => "event"})
    received = collect(pid, &stream_notice(&1, "guard-owned", "notifications/events/event"))

    assert stream_notice(received, "guard-owned", "notifications/events/event") ==
             native_notice(guard, "guard-owned", "event")

    second = connect(ctx)
    second_thread = thread(ctx, second)
    closed = active_stream(ctx, second, second_thread, "close-owned")
    assert :ok = Session.close(second)
    cancelled(ctx, closed)
    assert File.exists?("/proc/#{state(ctx)["native_pid"]}")
    control(ctx, "emit", %{"stream" => guard["stream"], "kind" => "event"})
    received = collect(pid, &stream_notice(&1, "guard-owned", "notifications/events/event"))

    assert stream_notice(received, "guard-owned", "notifications/events/event") ==
             native_notice(guard, "guard-owned", "event")

    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "guard-owned"}) == %{}
    cancelled(ctx, guard)
    assert_profile(ctx, [pid])
  end

  @tag profile: "events"
  test "M8 native terminal delivery reconnect continuity and preactivation failure", ctx do
    pid = connect(ctx)
    thread = thread(ctx, pid)
    terminal = active_stream(ctx, pid, thread, "terminal-owned")
    control(ctx, "emit", %{"stream" => terminal["stream"], "kind" => "terminated"})

    received =
      collect(pid, &stream_notice(&1, "terminal-owned", "notifications/events/terminated"))

    assert stream_notice(received, "terminal-owned", "notifications/events/terminated") ==
             native_notice(terminal, "terminal-owned", "terminated")

    cancelled(ctx, terminal)

    stream = active_stream(ctx, pid, thread, "reconnect-owned")
    # Opening this stream after terminal cancellation also detects an unwanted
    # reconnect: the expected count and request params must match this explicit start.
    assert length(events(ctx, "stream_opened")) == 2
    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "complete"})

    reconnected =
      wait(fn -> Enum.find(events(ctx, "stream_opened"), &(&1["stream"] > stream["stream"])) end)

    assert reconnected["request_id"] != stream["request_id"]
    assert reconnected["params"]["name"] == stream["params"]["name"]
    assert reconnected["params"]["arguments"] == stream["params"]["arguments"]

    assert Map.drop(reconnected["params"]["_meta"], ["progressToken"]) ==
             Map.drop(stream["params"]["_meta"], ["progressToken"])

    control(ctx, "emit", %{"stream" => reconnected["stream"], "kind" => "active"})
    collect(pid, &stream_notice(&1, "reconnect-owned", "notifications/events/active"))
    control(ctx, "emit", %{"stream" => reconnected["stream"], "kind" => "event"})
    received = collect(pid, &stream_notice(&1, "reconnect-owned", "notifications/events/event"))

    assert stream_notice(received, "reconnect-owned", "notifications/events/event") ==
             native_notice(reconnected, "reconnect-owned", "event")

    assert call(pid, "mcpServer/event/stream/stop", %{"subscriptionId" => "reconnect-owned"}) ==
             %{}

    cancelled(ctx, reconnected)

    task =
      Task.async(fn ->
        Session.request(
          pid,
          "mcpServer/event/stream/start",
          stream_params(thread, "inactive-owned")
        )
      end)

    inactive =
      wait(fn ->
        Enum.find(events(ctx, "stream_opened"), &(&1["stream"] > reconnected["stream"]))
      end)

    control(ctx, "emit", %{"stream" => inactive["stream"], "kind" => "complete"})
    assert {:error, %Error{wire: %{"error" => failure}}} = Task.await(task, 5_000)
    assert failure["message"] == "MCP event stream ended before becoming active"
    assert length(events(ctx, "stream_opened")) == 4
    assert_profile(ctx, [pid])
  end

  test "M9 fixture teardown is acknowledged before the live caller releases its guardian", ctx do
    assert_profile(ctx, [])
    assert [closed] = events(ctx, "fixture_closed")
    assert [ack] = Enum.filter(events(ctx, "control_done"), &(&1["op"] == "close"))
    assert closed["seq"] < ack["seq"]

    proof = state(ctx)
    for pid <- proof["native_pids"], do: refute(File.exists?("/proc/#{pid}"))
    assert File.exists?("/proc/#{proof["controller_pid"]}")
    assert File.exists?("/proc/#{proof["namespace_owner_pid"]}")
    assert Process.alive?(ctx.owner.owner.pid)
    assert :atomics.get(ctx.owner.owner.completion, 1) == 0

    assert {:error, reason} =
             :gen_tcp.connect(
               {:local, String.to_charlist(ctx.socket)},
               0,
               [:binary, active: false],
               100
             )

    assert reason in [:enoent, :econnrefused]
    assert control(ctx, "barrier") == %{}
    assert control(ctx, "close") == %{}
    assert events(ctx, "fixture_closed") == [closed]
  end

  test "M10 failed native MCP startup remains diagnosable and explicit reload recovers", ctx do
    control(ctx, "inventory-health", %{"variant" => "startup-failed", "generation" => 1})
    pid = connect(ctx)
    thread = thread(ctx, pid)
    selected = %{"threadId" => thread, "serverName" => "alpha", "detail" => "full"}

    failed =
      wait(fn ->
        assert %{"data" => [row], "nextCursor" => nil} =
                 call(pid, "mcpServerStatus/list", selected)

        if row["runtimeStatus"] == "failed", do: row
      end)

    assert failed["name"] == "alpha" and failed["httpOrigin"] == state(ctx)["endpoint"]
    assert failed["serverInfo"] == nil and failed["serverCapabilities"] == nil
    assert failed["tools"] == %{} and failed["resources"] == []
    assert failed["resourceTemplates"] == [] and failed["authStatus"] == "bearerToken"
    assert failed["toolsError"] =~ "MCP startup failed"
    assert failed["toolsError"] =~ "owned-inventory-initialize-rejected"

    rejected = events(ctx, "inventory_startup_rejected")
    assert rejected != []
    assert Enum.all?(rejected, &(&1["path"] == "/inventory/a-failed"))
    assert mcp_count(ctx, "/inventory/a-failed", "initialize") == length(rejected)
    assert mcp_count(ctx, "/inventory/a-failed", "tools/list") == 0

    assert %{"data" => [beta]} =
             call(pid, "mcpServerStatus/list", %{
               "threadId" => thread,
               "serverName" => "beta",
               "detail" => "full"
             })

    assert_inventory(ctx, beta, "beta", "b", "connected")
    control(ctx, "inventory-health", %{"variant" => "healthy", "generation" => 2})
    assert call(pid, "config/mcpServer/reload", nil) == %{}

    assert %{"data" => [recovered], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", selected)

    assert_inventory(ctx, recovered, "alpha", "a-v2", "connected")
    assert mcp_count(ctx, "/inventory/a-v2", "initialize") > 0
    assert mcp_count(ctx, "/inventory/a-v2", "tools/list") > 0

    assert :ok = Session.close(pid)
    old_native = state(ctx)["native_pid"]
    control(ctx, "restart")
    assert state(ctx)["native_pid"] != old_native
    refute File.exists?("/proc/#{old_native}")
    cold = connect(ctx)
    cold_thread = thread(ctx, cold)

    assert %{"data" => [cold_row]} =
             call(cold, "mcpServerStatus/list", %{
               "threadId" => cold_thread,
               "serverName" => "alpha",
               "detail" => "full"
             })

    assert_inventory(ctx, cold_row, "alpha", "a-v2", "connected")
    assert_profile(ctx, [cold])
  end

  test "M11 configured disabled native MCP never starts until explicit enable and reload", ctx do
    control(ctx, "inventory-health", %{"variant" => "disabled", "generation" => 1})
    pid = connect(ctx)
    thread = thread(ctx, pid)
    selected = %{"threadId" => thread, "serverName" => "alpha", "detail" => "full"}

    assert %{"data" => [disabled], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", selected)

    assert disabled["name"] == "alpha" and disabled["runtimeStatus"] == "disabled"
    assert disabled["serverInfo"] == nil and disabled["serverCapabilities"] == nil
    assert disabled["tools"] == %{} and disabled["toolsError"] == nil
    assert disabled["resources"] == [] and disabled["resourceTemplates"] == []
    assert mcp_count(ctx, "/inventory/a", "initialize") == 0
    refute Enum.any?(events(ctx, "mcp"), &(&1["path"] == "/inventory/a"))

    assert %{"data" => [beta]} =
             call(pid, "mcpServerStatus/list", %{
               "threadId" => thread,
               "serverName" => "beta",
               "detail" => "full"
             })

    assert_inventory(ctx, beta, "beta", "b", "connected")
    control(ctx, "inventory-health", %{"variant" => "healthy", "generation" => 2})
    assert call(pid, "config/mcpServer/reload", nil) == %{}

    assert %{"data" => [enabled], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", selected)

    assert_inventory(ctx, enabled, "alpha", "a-v2", "connected")
    assert mcp_count(ctx, "/inventory/a-v2", "initialize") > 0
    assert_profile(ctx, [pid])
  end

  # Pinned 83086188ae0614bd882818ff1aa23f3194962012:
  # turn_processor.rs:1625-1663 accepts empty-turn startup interrupts without a turn.
  # session/mod.rs:5309-5316 cancels unfinished MCP startup when no turn is active.
  # connection_manager.rs:160-164 keeps already-ready clients connected.
  # Ordinary server status awaits initialize metadata; do not fabricate Starting.
  test "M12 startup interrupt cancels held MCP initialization and preserves a ready sibling",
       ctx do
    control(ctx, "inventory-health", %{"variant" => "startup-held", "generation" => 1})
    pid = connect(ctx)
    thread = thread(ctx, pid)
    %{instance_id: instance, generation: generation} = Session.status(pid)
    held = wait(fn -> List.first(events(ctx, "inventory_initialize_held")) end)
    assert held["path"] == "/inventory/a-held"

    assert control(ctx, "inventory-startup-state") === %{
             "held" => true,
             "released" => false,
             "finished" => false
           }

    beta = %{"threadId" => thread, "serverName" => "beta", "detail" => "full"}

    assert %{"data" => [ready_beta], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", beta)

    assert_inventory(ctx, ready_beta, "beta", "b", "connected")
    assert mcp_count(ctx, "/inventory/b", "initialize") == 1

    selected = %{"threadId" => thread, "serverName" => "alpha", "detail" => "toolsAndAuthOnly"}
    cancelled = cancelled_startup_status(ctx)
    assert interrupt_pending_startup(pid, thread, selected) === cancelled

    cancellation = startup_notice(thread, "alpha", "cancelled")
    received = collect(pid, &(cancellation in startup_notices(&1, thread, "alpha")))

    assert startup_notices(received, thread, "alpha") === [
             startup_notice(thread, "alpha", "starting"),
             cancellation
           ]

    assert_startup_observer_ready(ctx, pid, instance, generation, received)

    assert call(pid, "mcpServerStatus/list", beta) ===
             %{"data" => [ready_beta], "nextCursor" => nil}

    # This barrier attempts the original dependency response after cancellation,
    # then waits for that handler to finish. Socket write success cannot revive it.
    assert control(ctx, "inventory-startup-release") === %{
             "held" => true,
             "released" => true,
             "finished" => true
           }

    assert [attempted] = events(ctx, "inventory_initialize_response_attempted")
    assert [finished] = events(ctx, "inventory_initialize_finished")
    assert attempted["request_id"] == held["request_id"]
    assert finished["request_id"] == held["request_id"]
    assert length(events(ctx, "inventory_initialize_release_requested")) == 1
    assert events(ctx, "inventory_initialize_abandoned") == []
    assert call(pid, "mcpServerStatus/list", selected) === cancelled

    assert call(pid, "mcpServerStatus/list", beta) ===
             %{"data" => [ready_beta], "nextCursor" => nil}

    assert mcp_count(ctx, "/inventory/a-held", "initialize") == 1
    assert mcp_count(ctx, "/inventory/a-held", "tools/list") == 0
    assert mcp_count(ctx, "/inventory/b", "initialize") == 1
    late = drain(pid)
    refute Enum.any?(startup_notices(late, thread, "alpha"), &(&1["status"] == "ready"))
    assert_startup_observer_ready(ctx, pid, instance, generation, late)

    control(ctx, "inventory-health", %{"variant" => "healthy", "generation" => 2})
    assert call(pid, "config/mcpServer/reload", nil) === %{}

    assert %{"data" => [recovered], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", %{selected | "detail" => "full"})

    assert_inventory(ctx, recovered, "alpha", "a-v2", "connected")
    assert mcp_count(ctx, "/inventory/a-v2", "initialize") == 1
    assert mcp_count(ctx, "/inventory/a-v2", "tools/list") == 1
    assert mcp_count(ctx, "/inventory/a-held", "initialize") == 1
    assert mcp_count(ctx, "/inventory/a-held", "tools/list") == 0

    ready = startup_notice(thread, "alpha", "ready")
    recovered_notices = collect(pid, &(ready in startup_notices(&1, thread, "alpha")))

    assert startup_notices(recovered_notices, thread, "alpha") === [
             startup_notice(thread, "alpha", "starting"),
             ready
           ]

    assert_startup_observer_ready(ctx, pid, instance, generation, recovered_notices)
    assert_profile(ctx, [pid])
  end

  # Pinned rmcp 4048ac40 auth.rs:2667-2692 treats a named issuer without
  # metadata as an error; Codex mcp/auth.rs:201-242 maps that probe to Unknown.
  # The peer serves real HTTP401/404; only pinned Codex emits status responses.
  @tag profile: "oauth"
  test "M13 native OAuth discovery failure reports unknown and explicit reload recovers",
       ctx do
    assert control(ctx, "oauth-discovery", %{"variant" => "missing-metadata"}) === %{
             "variant" => "missing-metadata"
           }

    pid = connect(ctx)
    thread = thread(ctx, pid)
    %{instance_id: instance, generation: generation} = Session.status(pid)
    assert_oauth_logged_out(ctx, pid, thread, "unknown")

    control(ctx, "barrier")
    faults = events(ctx, "named_issuer_metadata_fault")
    assert faults != []

    assert Enum.all?(faults, fn fault ->
             fault["path"] == "/oauth/.well-known/owned-missing-authorization-server" and
               fault["status"] == 404 and fault["response_written"] === true
           end)

    assert Enum.any?(events(ctx, "resource_metadata"), &(&1["discovery"] == "missing-metadata"))
    assert events(ctx, "oauth_metadata") == []
    assert events(ctx, "token_exchange") == []
    assert events(ctx, "callback_sent") == []
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert_startup_observer_ready(ctx, pid, instance, generation)

    assert control(ctx, "oauth-discovery", %{"variant" => "valid"}) === %{
             "variant" => "valid"
           }

    assert call(pid, "config/mcpServer/reload", nil) === %{}
    assert_oauth_logged_out(ctx, pid, thread, "notLoggedIn")
    assert events(ctx, "named_issuer_metadata_fault") === faults
    assert events(ctx, "token_exchange") == []
    assert events(ctx, "callback_sent") == []
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert_startup_observer_ready(ctx, pid, instance, generation)
    assert_profile(ctx, [pid])
  end

  # Every Session owns its own empty McpRuntime (session/session.rs:1614-1723);
  # previous-client reuse is confined to that runtime (connection_manager.rs:492-543).
  # Only Apps caches serverInfo; cached metadata/tools bypass pending startup
  # (connection_manager.rs:1082-1086 and rmcp_client.rs:616-629).
  @tag profile: "events"
  test "M14 native cached Apps status exposes a distinct starting client and explicit recovery",
       ctx do
    pid = connect(ctx)
    first = thread(ctx, pid)
    %{instance_id: instance, generation: generation} = Session.status(pid)
    ready = apps_status(pid, first)
    assert_apps_status(ctx, ready, "connected")
    metadata = events(ctx, "apps_resource_metadata")
    assert metadata != []
    assert Enum.all?(metadata, &(&1["resource"] == state(ctx)["endpoint"] <> "/api/codex/ps/mcp"))
    assert events(ctx, "token_exchange") == []
    assert events(ctx, "callback_sent") == []
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    cache = apps_cache(ctx, ready)
    initializations = mcp_count(ctx, "/api/codex/ps/mcp", "initialize")
    tool_lists = mcp_count(ctx, "/api/codex/ps/mcp", "tools/list")
    assert initializations > 0 and tool_lists > 0
    assert_startup_observer_ready(ctx, pid, instance, generation)

    assert control(ctx, "apps-startup-hold") === %{"armed" => true}
    second = thread(ctx, pid)
    refute second == first
    held = wait(fn -> List.first(events(ctx, "apps_initialize_held")) end)
    assert held["path"] == "/api/codex/ps/mcp"

    assert control(ctx, "apps-startup-state") === %{
             "armed" => true,
             "held" => true,
             "released" => false,
             "finished" => false
           }

    starting = apps_status(pid, second)
    assert_apps_status(ctx, starting, "starting")
    assert apps_cache(ctx, ready) === cache
    assert apps_status(pid, first) === ready
    assert mcp_count(ctx, "/api/codex/ps/mcp", "initialize") == initializations + 1
    assert mcp_count(ctx, "/api/codex/ps/mcp", "tools/list") == tool_lists

    assert control(ctx, "apps-startup-state") === %{
             "armed" => true,
             "held" => true,
             "released" => false,
             "finished" => false
           }

    assert events(ctx, "apps_initialize_response_attempted") == []
    assert events(ctx, "apps_initialize_finished") == []
    assert_startup_observer_ready(ctx, pid, instance, generation)

    assert control(ctx, "apps-startup-release") === %{
             "armed" => true,
             "held" => true,
             "released" => true,
             "finished" => true
           }

    assert [attempted] = events(ctx, "apps_initialize_response_attempted")
    assert [written] = events(ctx, "apps_initialize_response_written")
    assert [finished] = events(ctx, "apps_initialize_finished")
    assert attempted["request_id"] == held["request_id"]
    assert written["request_id"] == held["request_id"]
    assert Map.fetch!(written, "response_written") === true
    assert finished["request_id"] == held["request_id"]
    assert events(ctx, "apps_initialize_abandoned") == []
    assert events(ctx, "apps_initialize_peer_closed") == []

    recovered =
      wait(fn ->
        result = apps_status(pid, second)
        assert %{"data" => [row]} = result
        runtime = Map.fetch!(row, "runtimeStatus")
        assert runtime in ["starting", "connected"]
        if runtime == "connected", do: result
      end)

    assert recovered === ready
    assert apps_status(pid, first) === ready
    assert apps_cache(ctx, ready) === cache
    assert mcp_count(ctx, "/api/codex/ps/mcp", "initialize") == initializations + 1
    assert mcp_count(ctx, "/api/codex/ps/mcp", "tools/list") == tool_lists + 1
    assert length(events(ctx, "apps_initialize_hold_armed")) == 1
    assert length(events(ctx, "apps_initialize_release_requested")) == 1
    assert length(events(ctx, "apps_initialize_held")) == 1
    assert_startup_observer_ready(ctx, pid, instance, generation)
    assert_profile(ctx, [pid])
  end

  # Pinned SDK4048ac40 retains the real401 challenge when the rejected
  # access token has no refresh token. Native credentials remain in its File
  # store; only an explicit new OAuth login replaces them and recovers startup.
  @tag profile: "oauth"
  test "M15 native revoked stored OAuth reports reauthentication and explicit login recovers",
       ctx do
    pid = connect(ctx)
    %{instance_id: instance, generation: generation} = Session.status(pid)
    login = oauth_login(pid, nil)
    control(ctx, "callback", %{"url" => login["authorizationUrl"], "variant" => "success"})
    completed = collect(pid, &oauth_completion(&1, login["loginId"]))

    assert oauth_completion(completed, login["loginId"]) === %{
             "name" => "oauth",
             "threadId" => nil,
             "loginId" => login["loginId"],
             "success" => true
           }

    assert control(ctx, "probe-callback")["callback_open"] == false
    credential_path = Path.join(ctx.root, "codex/.credentials.json")
    assert File.regular?(credential_path)
    credential_digest = :crypto.hash(:sha256, File.read!(credential_path))
    warm_thread = thread(ctx, pid)
    assert_authenticated(ctx, pid, warm_thread)
    ready = startup_notice(warm_thread, "oauth", "ready")
    warmed = collect(pid, &(ready in startup_notices(&1, warm_thread, "oauth")), completed)

    assert startup_notices(warmed, warm_thread, "oauth") === [
             startup_notice(warm_thread, "oauth", "starting"),
             ready
           ]

    assert_startup_observer_ready(ctx, pid, instance, generation, warmed)
    assert [first_exchange] = events(ctx, "token_exchange")
    assert first_exchange["accepted"] and first_exchange["pkce_verified"]
    assert first_exchange["client_verified"] and first_exchange["redirect_verified"]
    assert first_exchange["access_generation"] === 1
    assert length(events(ctx, "callback_sent")) == 1
    tool_lists = mcp_count(ctx, "/oauth/mcp", "tools/list")
    authenticated = authenticated_initializations(ctx)
    assert tool_lists > 0 and authenticated > 0
    assert control(ctx, "oauth-revoke-access") === %{"revoked_generation" => 1}
    assert :crypto.hash(:sha256, File.read!(credential_path)) == credential_digest

    assert :ok = Session.close(pid)
    old_native = state(ctx)["native_pid"]
    control(ctx, "restart")
    assert state(ctx)["native_pid"] != old_native
    refute File.exists?("/proc/#{old_native}")
    cold = connect(ctx)
    cold_thread = thread(ctx, cold)
    %{instance_id: cold_instance, generation: cold_generation} = Session.status(cold)

    failed =
      startup_notice(
        cold_thread,
        "oauth",
        "failed",
        "The oauth MCP server requires OAuth reauthentication. Run `codex mcp login oauth`."
      )
      |> Map.put("failureReason", "reauthenticationRequired")

    rejected_notices = collect(cold, &(failed in startup_notices(&1, cold_thread, "oauth")))

    assert startup_notices(rejected_notices, cold_thread, "oauth") === [
             startup_notice(cold_thread, "oauth", "starting"),
             failed
           ]

    rejected = events(ctx, "oauth_revoked_access_response")
    assert rejected != []

    assert Enum.all?(rejected, fn event ->
             event["path"] == "/oauth/mcp" and event["method"] == "initialize" and
               event["access_generation"] === 1 and event["status"] === 401 and
               event["challenge_present"] === true and event["response_written"] === true
           end)

    selected = %{"threadId" => cold_thread, "serverName" => "oauth"}
    unavailable = call(cold, "mcpServerStatus/list", selected)
    assert_oauth_unavailable(ctx, unavailable, "notLoggedIn", "authenticationRequired")
    assert call(cold, "mcpServerStatus/list", selected) === unavailable
    control(ctx, "barrier")
    assert events(ctx, "oauth_revoked_access_response") === rejected
    assert authenticated_initializations(ctx) == authenticated
    assert mcp_count(ctx, "/oauth/mcp", "tools/list") == tool_lists
    assert length(events(ctx, "token_exchange")) == 1
    assert length(events(ctx, "callback_sent")) == 1
    assert :crypto.hash(:sha256, File.read!(credential_path)) == credential_digest

    assert_startup_observer_ready(
      ctx,
      cold,
      cold_instance,
      cold_generation,
      rejected_notices
    )

    recovery = oauth_login(cold, cold_thread)
    assert recovery["loginId"] != login["loginId"]
    control(ctx, "callback", %{"url" => recovery["authorizationUrl"], "variant" => "success"})
    recovered_completion = collect(cold, &oauth_completion(&1, recovery["loginId"]))

    assert oauth_completion(recovered_completion, recovery["loginId"]) === %{
             "name" => "oauth",
             "threadId" => cold_thread,
             "loginId" => recovery["loginId"],
             "success" => true
           }

    assert control(ctx, "probe-callback")["callback_open"] == false
    assert_authenticated(ctx, cold, cold_thread)
    recovered_ready = startup_notice(cold_thread, "oauth", "ready")

    recovered =
      collect(
        cold,
        &(recovered_ready in startup_notices(&1, cold_thread, "oauth")),
        recovered_completion
      )

    assert startup_notices(recovered, cold_thread, "oauth") === [
             startup_notice(cold_thread, "oauth", "starting"),
             recovered_ready
           ]

    assert [^first_exchange, second_exchange] = events(ctx, "token_exchange")
    assert second_exchange["accepted"] and second_exchange["pkce_verified"]
    assert second_exchange["client_verified"] and second_exchange["redirect_verified"]
    assert second_exchange["access_generation"] === 2
    assert length(events(ctx, "callback_sent")) == 2
    assert events(ctx, "oauth_revoked_access_response") === rejected
    assert :crypto.hash(:sha256, File.read!(credential_path)) != credential_digest

    assert Enum.any?(events(ctx, "mcp"), fn event ->
             event["path"] == "/oauth/mcp" and event["method"] == "initialize" and
               event["oauth_bearer_verified"] === true and event["oauth_access_generation"] === 2
           end)

    assert Enum.all?(events(ctx, "resource_metadata"), &(&1["discovery"] == "valid"))
    assert events(ctx, "named_issuer_metadata_fault") == []
    assert_startup_observer_ready(ctx, cold, cold_instance, cold_generation, recovered)
    assert_profile(ctx, [cold])
  end

  @tag profile: "form-bool"
  test "M16 native bool alone negotiates and resolves an out of turn legacy form", ctx do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    capabilities = %{"experimentalApi" => true, "mcpServerOpenaiFormElicitation" => true}
    refute Map.has_key?(capabilities, "extensions")

    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_bool_form", "version" => "0.1.0"},
               capabilities
             )

    thread = thread(ctx, pid)
    selected = %{"threadId" => thread, "serverName" => "form", "detail" => "full"}
    assert %{"data" => [connected]} = call(pid, "mcpServerStatus/list", selected)

    assert connected["runtimeStatus"] == "connected",
           inspect(%{
             status: Map.take(connected, ~w(name runtimeStatus toolsError)),
             peer: form_journal(ctx)
           })

    assert [initialization] = form_messages(ctx, "in", "initialize")
    assert initialization["params"]["capabilities"]["extensions"] === %{"openai/form" => %{}}
    assert form_messages(ctx, "in", "tools/call") == []
    assert connected["resources"] === [] and connected["resourceTemplates"] === []
    refute Map.has_key?(connected["serverCapabilities"], "resources")
    assert_form_inventory_reads(ctx, 1)
    assert form_rows(ctx, "decision_observed") == []

    task =
      Task.async(fn ->
        Session.request(pid, "mcpServer/tool/call", %{
          "threadId" => thread,
          "server" => "form",
          "tool" => "confirm",
          "arguments" => %{}
        })
      end)

    observed = collect_form(pid)
    assert [request] = Enum.filter(observed, &(&1.kind == :server_request))

    assert request.wire === %{
             "id" => request.handle.id,
             "method" => "mcpServer/elicitation/request",
             "params" => %{
               "threadId" => thread,
               "turnId" => nil,
               "serverName" => "form",
               "mode" => "openai/form",
               "message" => "Owned bool translation form",
               "_meta" => %{"fixture/request" => "bool-translation"},
               "requestedSchema" => form_schema()
             }
           }

    assert [peer_request] = form_messages(ctx, "out", "openai/form")

    assert peer_request["params"] ===
             Map.take(request.wire["params"], ~w(message _meta requestedSchema))

    assert call(pid, "mcpServerStatus/list", selected)["data"] == [connected]
    assert_form_inventory_reads(ctx, 2)
    assert %{pending: 1, interactions: 1, uncertain: 0, gap: nil} = Session.status(pid)
    assert Task.yield(task, 0) == nil
    assert form_rows(ctx, "decision_observed") == []
    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert control(ctx, "barrier") == %{}

    reply = %{
      "action" => "accept",
      "content" => %{"labels" => ["owned-λ"]},
      "_meta" => %{"fixture/response" => "explicit-owned-decision"}
    }

    assert :ok = Session.respond(pid, request.handle, {:ok, reply})

    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, request.handle, {:ok, reply})

    assert {:ok, %{"result" => result}} = Task.await(task, 5_000)

    assert result["content"] == [
             %{"type" => "text", "text" => "Owned explicit form decision observed"}
           ]

    assert result["isError"] == false
    request_id = request.handle.id

    resolved =
      collect(pid, fn all ->
        Enum.any?(notices(all, "serverRequest/resolved"), &(&1["requestId"] == request_id))
      end)

    assert [%{"threadId" => ^thread, "requestId" => ^request_id}] =
             notices(resolved, "serverRequest/resolved")

    assert [%{"decision_observed" => "accept"}] = form_rows(ctx, "decision_observed")
    assert [received] = form_responses(ctx)
    assert received === %{"jsonrpc" => "2.0", "id" => "owned-bool-form", "result" => reply}
    assert length(form_messages(ctx, "in", "tools/call")) == 1

    # This no-turn thread has a live paginated view but no indexed metadata.
    # Pinned local/thread_history/read.rs:203-231 returns Unsupported(list_turns)
    # for that state; thread_processor.rs:3334-3375 maps it to method-not-found.
    assert %{
             "thread" => %{
               "id" => ^thread,
               "historyMode" => "paginated",
               "ephemeral" => false,
               "turns" => []
             }
           } =
             call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})

    assert error(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true}) === %{
             "code" => -32_601,
             "message" => "list_turns is not supported yet"
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle == request.handle and outcome.status == :resolution_observed
    assert Session.uncertain_operations(pid) == []
    assert File.ls!(ctx.workspace) == []

    refute Enum.any?(
             observed ++ resolved,
             &String.starts_with?(&1.wire["method"] || "", ["turn/", "item/"])
           )

    assert form_rows(ctx, "forbidden_form") == []
    assert_profile(ctx, [pid])
    assert [peer] = form_rows(ctx, "peer_started")
    # Graceful fixture close leaves its controller and subreaper alive. Finish
    # checked owner shutdown before requiring its adopted peer to be reaped.
    assert :ok = Stdio.close(ctx.owner)
    wait(fn -> not File.exists?("/proc/#{peer["peer_started"]}") end)
  end

  @tag profile: "oauth-dcr"
  test "M17 native explicit dcr overrides advertised CIMD and completes real PKCE", ctx do
    pid = connect(ctx)
    config = File.read!(Path.join(ctx.root, "codex/config.toml"))
    refute String.contains?(config, "client_id")
    refute String.contains?(config, "callback_url")
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert events(ctx, "client_registered") == []

    login =
      call(pid, "mcpServer/oauth/login", %{
        "name" => "oauth",
        "clientRegistration" => "dcr",
        "scopes" => ["read:owned", "inspect:owned"],
        "timeoutSecs" => 10
      })

    assert login["loginId"] =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    url = URI.parse(login["authorizationUrl"])
    assert url.scheme == "http" and url.path == "/oauth/authorize"
    assert URI.to_string(%{url | path: "", query: nil}) == state(ctx)["endpoint"]
    query = URI.decode_query(url.query)
    assert query["client_id"] == "owned-dcr-client"
    assert query["response_type"] == "code" and query["code_challenge_method"] == "S256"
    assert is_binary(query["code_challenge"]) and byte_size(query["code_challenge"]) > 20
    redirect = URI.parse(query["redirect_uri"])
    assert redirect.scheme == "http" and redirect.host == "127.0.0.1"
    assert is_integer(redirect.port) and redirect.path == "/callback"
    assert String.split(query["scope"]) == ["read:owned", "inspect:owned"]
    assert events(ctx, "oauth_dcr_metadata") != []
    assert [registration] = events(ctx, "client_registered")
    assert registration["client_id"] == "owned-dcr-client"

    assert registration["request"] === %{
             "client_name" => "Codex",
             "redirect_uris" => [query["redirect_uri"]],
             "grant_types" => ["authorization_code", "refresh_token"],
             "token_endpoint_auth_method" => "none",
             "response_types" => ["code"],
             "scope" => "read:owned inspect:owned",
             "application_type" => "native"
           }

    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert events(ctx, "token_exchange") == []
    control(ctx, "callback", %{"url" => login["authorizationUrl"], "variant" => "success"})
    received = collect(pid, &oauth_completion(&1, login["loginId"]))

    assert oauth_completion(received, login["loginId"]) === %{
             "name" => "oauth",
             "threadId" => nil,
             "loginId" => login["loginId"],
             "success" => true
           }

    assert [exchange] = events(ctx, "token_exchange")
    assert exchange["accepted"] and exchange["pkce_verified"] and exchange["redirect_verified"]
    assert control(ctx, "probe-callback")["callback_open"] == false
    assert File.regular?(Path.join(ctx.root, "codex/.credentials.json"))
    thread = thread(ctx, pid)
    assert_authenticated(ctx, pid, thread)
    assert length(events(ctx, "client_registered")) == 1
    assert length(events(ctx, "token_exchange")) == 1
    assert length(events(ctx, "callback_sent")) == 1

    assert_startup_observer_ready(
      ctx,
      pid,
      Session.status(pid).instance_id,
      Session.status(pid).generation
    )

    assert_profile(ctx, [pid])
  end

  # These owned peers qualify native client selection/PKCE only. Native uses
  # the URL as client_id without fetching it; no real IAM/document is verified.
  @tag profile: "oauth-cimd"
  test "M18 native explicit auto matches omission and falls back only when CIMD is absent", ctx do
    default = selector_login(ctx, :omitted, "https://chatgpt.com/oauth/codex/client.json", false)

    automatic =
      selector_login(
        selector_context("oauth-cimd"),
        "auto",
        "https://chatgpt.com/oauth/codex/client.json",
        false
      )

    assert automatic == default

    fallback =
      selector_login(selector_context("oauth-auto-fallback"), "auto", "owned-dcr-client", true)

    assert fallback["client_id"] == "owned-dcr-client"
    assert fallback["registrations"] == 1 and fallback["exchanges"] == 1
  end

  @tag profile: "oauth-cimd"
  test "M19 native explicit cimd uses URL client identity and rejects unsupported discovery",
       ctx do
    result = selector_login(ctx, "cimd", "https://chatgpt.com/oauth/codex/client.json", false)
    assert result["registrations"] == 0 and result["exchanges"] == 1

    for {profile, cimd, public_none} <- [
          {"oauth-cimd-no-advertisement", false, true},
          {"oauth-cimd-no-none", true, false}
        ] do
      rejected = selector_context(profile)
      pid = connect(rejected)
      assert_unconfigured_selector(rejected)
      before = control(rejected, "selector-listeners")
      assert before["listening_ports"] == [URI.parse(state(rejected)["endpoint"]).port]

      assert error(pid, "mcpServer/oauth/login", %{
               "name" => "oauth",
               "clientRegistration" => "cimd",
               "scopes" => ["read:owned", "inspect:owned"],
               "timeoutSecs" => 10
             }) === %{
               "code" => -32_603,
               "message" =>
                 "failed to login to MCP server 'oauth': MCP authorization server does not advertise CIMD with token endpoint auth method `none`"
             }

      wait(fn -> control(rejected, "selector-listeners") == before end)
      metadata = events(rejected, "oauth_selector_metadata")
      assert metadata != []

      assert Enum.all?(
               metadata,
               &(&1["cimd_advertised"] == cimd and &1["public_none"] == public_none and
                   &1["dcr_advertised"])
             )

      assert events(rejected, "client_registered") == []
      assert events(rejected, "token_exchange") == []
      assert events(rejected, "selector_token_verified") == []
      assert events(rejected, "callback_sent") == []
      refute File.exists?(Path.join(rejected.root, "codex/.credentials.json"))
      observed = drain(pid)
      assert notices(observed, "mcpServer/oauthLogin/completed") == []

      assert_startup_observer_ready(
        rejected,
        pid,
        Session.status(pid).instance_id,
        Session.status(pid).generation,
        observed
      )

      assert_profile(rejected, [pid])
      assert :ok = Session.close(pid)
    end
  end

  defp assert_unconfigured_selector(ctx) do
    config = File.read!(Path.join(ctx.root, "codex/config.toml"))
    refute String.contains?(config, "client_id")
    refute String.contains?(config, "client_secret")
    refute String.contains?(config, "callback_url")
    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert events(ctx, "client_registered") == []
    assert events(ctx, "token_exchange") == []
    assert events(ctx, "callback_sent") == []
  end

  defp selector_login(ctx, selector, expected_client, registration?) do
    pid = connect(ctx)
    assert_unconfigured_selector(ctx)

    params = %{
      "name" => "oauth",
      "scopes" => ["read:owned", "inspect:owned"],
      "timeoutSecs" => 10
    }

    params =
      if selector == :omitted, do: params, else: Map.put(params, "clientRegistration", selector)

    if selector == :omitted do
      refute Map.has_key?(params, "clientRegistration")
    else
      assert params["clientRegistration"] == selector
    end

    login = call(pid, "mcpServer/oauth/login", params)

    {query, redirect} = assert_selector_authorization(ctx, login, expected_client)
    assert_selector_metadata(ctx, registration?)

    if registration? do
      assert [registration] = events(ctx, "client_registered")
      assert registration["client_id"] == "owned-dcr-client"

      assert registration["request"] === %{
               "client_name" => "Codex",
               "redirect_uris" => [query["redirect_uri"]],
               "grant_types" => ["authorization_code", "refresh_token"],
               "token_endpoint_auth_method" => "none",
               "response_types" => ["code"],
               "scope" => "read:owned inspect:owned",
               "application_type" => "native"
             }
    else
      assert events(ctx, "client_registered") == []
    end

    refute File.exists?(Path.join(ctx.root, "codex/.credentials.json"))
    assert events(ctx, "token_exchange") == []
    control(ctx, "callback", %{"url" => login["authorizationUrl"], "variant" => "success"})
    received = collect(pid, &oauth_completion(&1, login["loginId"]))

    assert oauth_completion(received, login["loginId"]) === %{
             "name" => "oauth",
             "threadId" => nil,
             "loginId" => login["loginId"],
             "success" => true
           }

    assert [exchange] = events(ctx, "token_exchange")
    assert exchange["accepted"] and exchange["pkce_verified"] and exchange["redirect_verified"]
    assert [verified] = events(ctx, "selector_token_verified")

    assert Map.take(verified, ~w(client_id no_client_secret no_authorization)) === %{
             "client_id" => expected_client,
             "no_client_secret" => true,
             "no_authorization" => true
           }

    assert control(ctx, "probe-callback")["callback_open"] == false
    credentials = Path.join(ctx.root, "codex/.credentials.json")
    assert File.regular?(credentials)
    digest = :crypto.hash(:sha256, File.read!(credentials))
    assert byte_size(digest) == 32
    thread = thread(ctx, pid)
    assert_authenticated(ctx, pid, thread)
    assert :crypto.hash(:sha256, File.read!(credentials)) == digest
    assert length(events(ctx, "client_registered")) == if(registration?, do: 1, else: 0)
    assert length(events(ctx, "token_exchange")) == 1
    assert length(events(ctx, "callback_sent")) == 1

    assert_startup_observer_ready(
      ctx,
      pid,
      Session.status(pid).instance_id,
      Session.status(pid).generation,
      received
    )

    summary = %{
      "client_id" => expected_client,
      "registrations" => length(events(ctx, "client_registered")),
      "exchanges" => length(events(ctx, "token_exchange")),
      "redirect_path" => redirect.path
    }

    assert_profile(ctx, [pid])
    assert :ok = Session.close(pid)
    summary
  end

  defp assert_selector_authorization(ctx, login, expected_client) do
    assert login["loginId"] =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    url = URI.parse(login["authorizationUrl"])
    assert url.scheme == "http" and url.path == "/oauth/authorize"
    assert URI.to_string(%{url | path: "", query: nil}) == state(ctx)["endpoint"]
    query = URI.decode_query(url.query)
    assert query["client_id"] == expected_client
    assert query["response_type"] == "code" and query["code_challenge_method"] == "S256"
    assert is_binary(query["code_challenge"]) and byte_size(query["code_challenge"]) > 20
    assert is_binary(query["state"]) and byte_size(query["state"]) > 20
    assert String.split(query["scope"]) == ["read:owned", "inspect:owned"]
    redirect = URI.parse(query["redirect_uri"])
    assert redirect.scheme == "http" and redirect.host == "127.0.0.1"
    assert is_integer(redirect.port) and redirect.path == "/callback"
    assert redirect.userinfo == nil and redirect.query == nil and redirect.fragment == nil
    {query, redirect}
  end

  defp assert_selector_metadata(ctx, registration?) do
    metadata = events(ctx, "oauth_selector_metadata")
    assert metadata != []

    assert Enum.all?(
             metadata,
             &(&1["cimd_advertised"] == not registration? and &1["public_none"] and
                 &1["dcr_advertised"])
           )
  end

  defp selector_context(profile) do
    tags = %{profile: profile}
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-mcp-control-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))
    profile = tags[:profile] || "status"

    ctx = %{
      root: root,
      workspace: Path.join(root, "workspace"),
      socket: Path.join(root, "native.sock")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary), "--profile", profile],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = Map.put(ctx, :owner, owner)

    on_exit(fn -> close_selector_context(ctx) end)

    wait(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    ctx
  end

  defp close_selector_context(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = state(ctx)

      for pid <- proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: wait_for_selector_exit(pid)

      assert events(ctx, "fixture_closed") != []
    end

    File.rm_rf!(ctx.root)
  end

  defp wait_for_selector_exit(pid),
    do: wait(fn -> not File.exists?("/proc/#{pid}") end)

  defp assert_form_inventory_reads(ctx, count) do
    for {method, key} <- [
          {"resources/list", "resources"},
          {"resources/templates/list", "resourceTemplates"}
        ] do
      requests = form_messages(ctx, "in", method)
      assert length(requests) == count

      for request <- requests, do: assert_form_inventory_read(ctx, request, key)
    end

    assert form_messages(ctx, "in", "prompts/list") == []
  end

  defp assert_form_inventory_read(ctx, request, key) do
    assert is_integer(request["id"])
    assert %{"_meta" => %{"progressToken" => token}} = request["params"]
    assert is_integer(token) and token >= 0
    assert request["params"] === %{"_meta" => %{"progressToken" => token}}

    assert [response] =
             for(
               %{"direction" => "out", "message" => message} <- form_journal(ctx),
               message["id"] == request["id"],
               Map.has_key?(message, "result"),
               do: message
             )

    assert response === %{
             "jsonrpc" => "2.0",
             "id" => request["id"],
             "result" => %{key => []}
           }
  end

  defp form_schema,
    do: %{
      "type" => "object",
      "properties" => %{"labels" => %{"type" => "array", "items" => %{"type" => "string"}}},
      "required" => ["labels"],
      "additionalProperties" => false
    }

  defp form_journal(ctx),
    do:
      Path.join(ctx.root, "form-peer.jsonl")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

  defp form_rows(ctx, key), do: Enum.filter(form_journal(ctx), &Map.has_key?(&1, key))

  defp form_messages(ctx, direction, method),
    do:
      for(
        %{"direction" => ^direction, "message" => message} <- form_journal(ctx),
        message["method"] == method,
        do: message
      )

  defp form_responses(ctx),
    do:
      for(
        %{"direction" => "in", "message" => message} <- form_journal(ctx),
        message["id"] == "owned-bool-form",
        do: message
      )

  defp collect_form(pid, accumulated \\ [], remaining \\ 500)
  defp collect_form(_pid, _accumulated, 0), do: flunk("Owned native form notice deadline")

  defp collect_form(pid, accumulated, remaining) do
    assert {:ok, received} = Session.drain(pid)
    refute Enum.any?(received, &String.starts_with?(&1.wire["method"] || "", ["turn/", "item/"]))

    assert Enum.all?(received, fn event ->
             event.kind != :server_request or
               event.wire["method"] == "mcpServer/elicitation/request"
           end)

    accumulated = accumulated ++ received

    if Enum.any?(accumulated, &(&1.kind == :server_request)) do
      accumulated
    else
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected form event gap")
      after
        10 -> :ok
      end

      collect_form(pid, accumulated, remaining - 1)
    end
  end

  defp apps_status(pid, thread),
    do:
      call(pid, "mcpServerStatus/list", %{
        "threadId" => thread,
        "serverName" => "codex_apps",
        "detail" => "toolsAndAuthOnly"
      })

  defp assert_apps_status(ctx, result, runtime) do
    capabilities =
      if runtime == "connected" do
        %{
          "tools" => %{},
          "resources" => %{"subscribe" => false, "listChanged" => false},
          "extensions" => %{"owned/inventory" => %{"generation" => "mcp"}}
        }
      end

    assert result === %{
             "data" => [
               %{
                 "name" => "codex_apps",
                 "runtimeStatus" => runtime,
                 "pluginId" => nil,
                 "httpOrigin" => state(ctx)["endpoint"],
                 "serverInfo" => %{
                   "name" => "owned-mcp",
                   "title" => "Owned mcp",
                   "version" => "1.0.0",
                   "description" => "Synthetic inventory λ",
                   "websiteUrl" => "https://synthetic.invalid/owned",
                   "icons" => nil
                 },
                 "serverCapabilities" => capabilities,
                 "tools" => %{},
                 "toolsError" => nil,
                 "resources" => [],
                 "resourceTemplates" => [],
                 "authStatus" => "notLoggedIn"
               }
             ],
             "nextCursor" => nil
           }
  end

  defp apps_cache(ctx, %{"data" => [ready]}) do
    [tools_path] = Path.wildcard(Path.join(ctx.root, "codex/cache/codex_apps_tools/*.json"))

    [info_path] =
      Path.wildcard(Path.join(ctx.root, "codex/cache/codex_apps_server_info/*.json"))

    assert Path.basename(tools_path) == Path.basename(info_path)
    tools = File.read!(tools_path)
    info = File.read!(info_path)
    assert JSON.decode!(tools) === %{"schema_version" => 4, "tools" => []}

    assert JSON.decode!(info) === %{
             "schema_version" => 1,
             "server_info" => Map.fetch!(ready, "serverInfo")
           }

    {tools, info}
  end

  defp interrupt_pending_startup(pid, thread, selected) do
    status_id = "owned-held-startup-status"
    interrupt_id = "owned-empty-turn-startup-interrupt"

    pending =
      Task.async(fn -> Session.request(pid, "mcpServerStatus/list", selected, id: status_id) end)

    try do
      wait(fn -> Session.status(pid).pending == 1 end)
      assert Task.yield(pending, 0) == nil

      assert {:ok, %{"id" => ^interrupt_id, "result" => acknowledgement}} =
               Session.request(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => ""},
                 id: interrupt_id
               )

      assert acknowledgement === %{}
      assert {:ok, %{"id" => ^status_id, "result" => result}} = Task.await(pending)
      result
    after
      Task.shutdown(pending, :brutal_kill)
    end
  end

  defp cancelled_startup_status(ctx) do
    %{
      "data" => [
        %{
          "name" => "alpha",
          "runtimeStatus" => "cancelled",
          "pluginId" => nil,
          "httpOrigin" => state(ctx)["endpoint"],
          "serverInfo" => nil,
          "serverCapabilities" => nil,
          "tools" => %{},
          "toolsError" => "MCP startup cancelled",
          "resources" => [],
          "resourceTemplates" => [],
          "authStatus" => "bearerToken"
        }
      ],
      "nextCursor" => nil
    }
  end

  defp startup_notice(thread, name, status, error \\ nil),
    do: %{
      "threadId" => thread,
      "name" => name,
      "status" => status,
      "error" => error,
      "failureReason" => nil
    }

  defp startup_notices(received, thread, name),
    do:
      received
      |> notices("mcpServer/startupStatus/updated")
      |> Enum.filter(&(&1["threadId"] == thread and &1["name"] == name))

  defp assert_startup_observer_ready(ctx, pid, instance, generation, observed \\ []) do
    refute Enum.any?(observed ++ drain(pid), fn event ->
             String.starts_with?(event.wire["method"] || "", ["turn/", "item/"])
           end)

    assert %{
             phase: :ready,
             instance_id: ^instance,
             generation: ^generation,
             pending: 0,
             interactions: 0,
             uncertain: 0,
             gap: nil
           } = Session.status(pid)

    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert File.ls!(ctx.workspace) == []
  end

  defp connect(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})
    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)

    assert {:ok, _} =
             Session.initialize(pid, %{"name" => "samgita_mcp_control", "version" => "0.1.0"}, %{
               "experimentalApi" => true
             })

    pid
  end

  defp thread(ctx, pid),
    do:
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request"
      })["thread"]["id"]

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => failure}}} =
             Session.request(pid, method, params)

    assert is_integer(failure["code"]) and failure["code"] < 0
    failure
  end

  defp oauth_login(pid, thread) do
    result =
      call(pid, "mcpServer/oauth/login", %{
        "name" => "oauth",
        "threadId" => thread,
        "scopes" => ["read:owned", "inspect:owned"],
        "timeoutSecs" => 10
      })

    assert result["loginId"] =~
             ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

    result
  end

  defp assert_oauth_logged_out(ctx, pid, thread, auth_status) do
    selected = %{"threadId" => thread, "serverName" => "oauth"}

    assert_oauth_unavailable(
      ctx,
      call(pid, "mcpServerStatus/list", selected),
      auth_status,
      "authenticationRequired"
    )

    assert_oauth_unauthenticated_response(ctx)
    before_threadless = length(events(ctx, "oauth_unauthenticated_response"))

    assert_oauth_unavailable(
      ctx,
      call(pid, "mcpServerStatus/list", %{"serverName" => "oauth"}),
      auth_status,
      nil
    )

    wait(fn ->
      length(events(ctx, "oauth_unauthenticated_response")) > before_threadless
    end)

    assert_oauth_unauthenticated_response(ctx)

    if auth_status == "notLoggedIn" do
      assert events(ctx, "oauth_metadata") != []
      assert Enum.any?(events(ctx, "resource_metadata"), &(&1["discovery"] == "valid"))
    end
  end

  defp assert_oauth_unavailable(ctx, result, auth_status, runtime_status) do
    assert %{"data" => [row], "nextCursor" => nil} = result
    tools_error = Map.fetch!(row, "toolsError")
    assert is_binary(tools_error) and tools_error != ""
    assert tools_error =~ "MCP startup failed:"
    assert tools_error =~ "handshaking with MCP server failed:"
    assert tools_error =~ "Auth required"

    # Full equality proves nullable keys physically exist; access with [] alone
    # would also accept missing keys. Preserve the actual native error string.
    assert result === %{"data" => [row], "nextCursor" => nil}

    assert row === %{
             "name" => "oauth",
             "runtimeStatus" => runtime_status,
             "pluginId" => nil,
             "httpOrigin" => state(ctx)["endpoint"],
             "serverInfo" => nil,
             "serverCapabilities" => nil,
             "tools" => %{},
             "toolsError" => tools_error,
             "resources" => [],
             "resourceTemplates" => [],
             "authStatus" => auth_status
           }
  end

  defp assert_oauth_unauthenticated_response(ctx) do
    wait(fn ->
      Enum.any?(events(ctx, "oauth_unauthenticated_response"), fn response ->
        response["path"] == "/oauth/mcp" and response["method"] == "initialize" and
          response["status"] == 401 and response["challenge_present"] === true and
          response["response_written"] === true
      end)
    end)
  end

  defp assert_authenticated(ctx, pid, thread) do
    assert %{"data" => [row], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", %{"threadId" => thread, "serverName" => "oauth"})

    assert row["authStatus"] == "oAuth" and row["toolsError"] == nil
    assert Map.fetch!(row, "runtimeStatus") === "connected"
    assert Map.fetch!(row, "toolsError") === nil
    assert Map.fetch!(row, "pluginId") === nil
    assert is_map(Map.fetch!(row, "serverInfo"))
    assert is_map(Map.fetch!(row, "serverCapabilities"))
    assert row["serverInfo"]["name"] == "owned-mcp"
    assert row["httpOrigin"] == state(ctx)["endpoint"]

    assert Enum.any?(
             events(ctx, "mcp"),
             &(&1["path"] == "/oauth/mcp" and &1["method"] == "initialize" and
                 &1["oauth_bearer_verified"])
           )
  end

  defp assert_inventory(ctx, row, name, label, runtime) do
    assert row["name"] == name and row["runtimeStatus"] == runtime and row["pluginId"] == nil
    assert row["httpOrigin"] == state(ctx)["endpoint"]

    assert row["serverInfo"] == %{
             "name" => "owned-" <> label,
             "title" => "Owned " <> label,
             "version" => "1.0.0",
             "description" => "Synthetic inventory λ",
             "websiteUrl" => "https://synthetic.invalid/owned",
             "icons" => nil
           }

    assert row["serverCapabilities"] == %{
             "tools" => %{},
             "resources" => %{"subscribe" => false, "listChanged" => false},
             "extensions" => %{"owned/inventory" => %{"generation" => label}}
           }

    assert row["tools"] == %{
             ("inspect." <> label) => %{
               "name" => "inspect." <> label,
               "description" => "Inventory only λ",
               "inputSchema" => %{
                 "type" => "object",
                 "properties" => %{"key" => %{"type" => "string"}}
               },
               "annotations" => %{"readOnlyHint" => true, "destructiveHint" => false}
             }
           }

    assert row["toolsError"] == nil and row["authStatus"] == "bearerToken"

    assert row["resources"] == [
             %{
               "uri" => "fixture://" <> label,
               "name" => "Owned " <> label,
               "mimeType" => "text/plain",
               "description" => "Owned resource"
             }
           ]

    assert row["resourceTemplates"] == [
             %{
               "uriTemplate" => "fixture://" <> label <> "/{key}",
               "name" => "Owned template " <> label,
               "mimeType" => "text/plain"
             }
           ]
  end

  defp stream_params(thread, subscription),
    do: %{
      "threadId" => thread,
      "server" => "codex_apps",
      "subscriptionId" => subscription,
      "name" => "owned.updated",
      "arguments" => %{"project" => "owned", "nested" => [1, nil, "λ🙂"]},
      "_meta" => %{"source" => "owned-client"}
    }

  defp active_stream(ctx, pid, thread, subscription) do
    count = length(events(ctx, "stream_opened"))

    task =
      Task.async(fn ->
        Session.request(pid, "mcpServer/event/stream/start", stream_params(thread, subscription))
      end)

    stream = wait(fn -> Enum.at(events(ctx, "stream_opened"), count) end)
    control(ctx, "emit", %{"stream" => stream["stream"], "kind" => "active"})
    await_started(task)
    received = collect(pid, &stream_notice(&1, subscription, "notifications/events/active"))

    assert stream_notice(received, subscription, "notifications/events/active") ==
             native_notice(stream, subscription, "active")

    stream
  end

  defp cancelled(ctx, stream) do
    wait(fn ->
      Enum.find(
        events(ctx, "stream_transport_closed"),
        &(&1["stream"] == stream["stream"] and &1["request_id"] == stream["request_id"] and
            &1["reason"] in ["peer-eof", "peer-reset"])
      )
    end)

    wait(fn -> Enum.any?(events(ctx, "stream_closed"), &(&1["stream"] == stream["stream"])) end)
  end

  defp await_started(task) do
    assert {:ok, %{"result" => result}} = Task.await(task, 5_000)
    assert result == %{}
  end

  defp authenticated_initializations(ctx),
    do:
      Enum.count(
        events(ctx, "mcp"),
        &(&1["path"] == "/oauth/mcp" and &1["method"] == "initialize" and
            &1["oauth_bearer_verified"])
      )

  defp native_notice(stream, subscription, kind) do
    params = %{
      "_meta" => %{
        "io.modelcontextprotocol/subscriptionId" => stream["request_id"],
        "provider" => "owned-events"
      }
    }

    params =
      case kind do
        "active" ->
          Map.put(params, "status", "active")

        "terminated" ->
          params

        "event" ->
          Map.merge(params, %{
            "name" => "owned.updated",
            "data" => %{"value" => "λ🙂", "nested" => [1, nil, false], "sentinel" => "event"}
          })
      end

    %{
      "subscriptionId" => subscription,
      "notification" => %{"method" => "notifications/events/" <> kind, "params" => params}
    }
  end

  defp oauth_completion(received, login),
    do: Enum.find(notices(received, "mcpServer/oauthLogin/completed"), &(&1["loginId"] == login))

  defp stream_notices(received), do: notices(received, @stream_method)

  defp stream_notice(received, subscription, method),
    do:
      Enum.find(
        stream_notices(received),
        &(&1["subscriptionId"] == subscription and &1["notification"]["method"] == method)
      )

  defp notices(received, method),
    do: for(event <- received, event.wire["method"] == method, do: event.wire["params"])

  defp drain(pid) do
    assert {:ok, received} = Session.drain(pid)

    refute Enum.any?(received, &(&1.kind == :server_request)),
           "No approval/tool response is authorized"

    refute Enum.any?(received, &(&1.wire["method"] == "turn/started")),
           "No inference is authorized"

    received
  end

  defp collect(pid, predicate, accumulated \\ [], remaining \\ 500)
  defp collect(_pid, _predicate, _accumulated, 0), do: flunk("Owned native MCP notice deadline")

  defp collect(pid, predicate, accumulated, remaining) do
    accumulated = accumulated ++ drain(pid)

    if predicate.(accumulated) do
      accumulated
    else
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected MCP event gap")
      after
        10 -> :ok
      end

      collect(pid, predicate, accumulated, remaining - 1)
    end
  end

  defp control(ctx, operation, extra \\ %{}) do
    identity = "owned-control-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             Stdio.send(
               ctx.owner,
               JSON.encode!(Map.merge(extra, %{"id" => identity, "op" => operation}))
             )

    result = wait(fn -> Enum.find(events(ctx, "control_done"), &(&1["id"] == identity)) end)
    result["result"]
  end

  defp mcp_count(ctx, path, method),
    do: Enum.count(events(ctx, "mcp"), &(&1["path"] == path and &1["method"] == method))

  defp events(ctx, event),
    do:
      Enum.filter(
        JSON.decode!(File.read!(Path.join(ctx.root, "journal.json")))["events"],
        &(&1["event"] == event)
      )

  defp state(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "state.json")))

  defp assert_profile(ctx, pids) do
    control(ctx, "barrier")

    for event <- ~w(forbidden_http forbidden_body forbidden_mcp fixture_error),
        do: assert(events(ctx, event) == [])

    for pid <- pids do
      assert Session.status(pid).interactions == 0
      drain(pid)
    end

    # Finish graceful fixture teardown while this caller still owns Stdio.
    # Its unchanged owner-death guardian remains the hard cleanup fallback.
    assert control(ctx, "close") == %{}
  end

  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned MCP fixture observation deadline")

  defp wait(predicate, remaining) do
    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        Process.sleep(10)
        wait(predicate, remaining - 1)
    end
  end
end
