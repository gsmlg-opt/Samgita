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
    assert call(pid, "config/mcpServer/reload", nil) == %{}
    assert_authenticated(ctx, pid, thread)
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

  defp assert_authenticated(ctx, pid, thread) do
    assert %{"data" => [row], "nextCursor" => nil} =
             call(pid, "mcpServerStatus/list", %{"threadId" => thread, "serverName" => "oauth"})

    assert row["authStatus"] == "oAuth" and row["toolsError"] == nil
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
