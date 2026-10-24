defmodule SamgitaCodexDriver.NativeNetworkAmendmentProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_network_amendment
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_network_amendment_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @host "127.0.0.3"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip mount), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-network-amendment-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)

    for directory <- ~w(home codex workspace tmp system bin),
        do: File.mkdir!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    File.write!(Path.join(root, "origin-hits.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    parents = Map.new(~w(user mnt net), &{&1, File.read_link!("/proc/self/ns/" <> &1)})

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: ["-I", @script, "--root", root, "--codex", Path.expand(binary)],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{root: root, socket: Path.join(root, "native.sock"), owner: owner}

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        for key <- ~w(native_pid controller_pid namespace_owner_pid),
            do:
              await(
                fn -> not File.exists?("/proc/#{read(ctx, "state.json")[key]}") end,
                "owned network process reaping"
              )

        closed = read(ctx, "closed.json")
        assert closed["native_reaped"] and closed["native_group_gone"]
        assert closed["owned_children_remaining"] == [], inspect(closed)

        for peer <- ~w(provider origin),
            do: assert(closed[peer] == %{"stopped" => true, "workers" => 0, "sockets" => 0})

        assert closed["cleanup_seconds"] <= 0.75
        assert closed["stderr_path"] == Path.join(root, "native-stderr.log")
        assert byte_size(File.read!(closed["stderr_path"])) <= 65_536
      end
    end)

    await(
      fn ->
        if File.exists?(Path.join(root, "startup-failure.json")) do
          failure = read(ctx, "startup-failure.json")

          flunk(
            "BLOCKED_ENV: #{JSON.encode!(failure)}\n" <>
              File.read!(Path.join(root, "native-stderr.log"))
          )
        end

        File.exists?(Path.join(root, "state.json"))
      end,
      "BLOCKED_ENV: private mount namespace/managed proxy fixture startup"
    )

    proof = read(ctx, "state.json")
    assert proof["parents"] == parents
    for name <- ~w(user mnt net), do: assert(proof["namespaces"][name] != parents[name])
    assert proof["interfaces"] == ["lo"]
    assert proof["requirements_path"] == "/etc/codex/requirements.toml"
    assert proof["requirements_read_only"] and proof["private_etc_tmpfs"]
    refute proof["default_route"] or proof["ipv6_default_route"]
    ctx
  end

  for action <- ~w(allow deny) do
    @action action
    test "real managed proxy persists an exact #{@action} amendment and reuses its host policy",
         ctx do
      pid = client(ctx)

      thread =
        call(pid, "thread/start", %{
          "cwd" => Path.join(ctx.root, "workspace"),
          "historyMode" => "legacy",
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "approvalsReviewer" => "user"
        })["thread"]["id"]

      first = turn(pid, thread, "1")
      {events, [approval]} = finish(pid, thread, first, @action, true)
      assert_approval(approval, thread, first)

      output =
        if @action == "allow",
          do: command_outputs(events) |> Enum.join("\n"),
          else: tool_outputs(ctx, "owned-network-1") |> Enum.join("\n")

      assert output =~
               if(@action == "allow",
                 do: "owned network request succeeded",
                 else: "rejected by user"
               )

      assert length(read(ctx, "origin-hits.json")) == if(@action == "allow", do: 1, else: 0)

      rules_path = Path.join(ctx.root, "codex/rules/default.rules")
      rules = File.read!(rules_path)
      assert rules =~ ~s|network_rule(host="#{@host}", protocol="http", decision="#{@action}"|
      refute rules =~ "prefix_rule("

      second = turn(pid, thread, "2")
      {next, []} = finish(pid, thread, second, @action, false)
      assert length(read(ctx, "origin-hits.json")) == if(@action == "allow", do: 2, else: 0)
      assert File.read!(rules_path) == rules
      assert length(read(ctx, "requests.json")) == 4

      if @action == "allow" do
        for current <- [events, next] do
          output = command_outputs(current) |> Enum.join("\n")
          assert output =~ "owned direct access blocked"
          assert output =~ "owned network request succeeded"
        end
      else
        refute command_outputs(next) |> Enum.join("\n") =~ "owned network request succeeded"
      end

      assert Session.status(pid).interactions == 0
      assert :ok = Session.close(pid)
    end
  end

  test "plain network acceptance permits one request and requires another explicit decision",
       ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    {events, [approval]} = finish_decision(pid, thread, first, "accept", true)
    assert_approval(approval, thread, first)
    assert_network_success(events)
    assert length(read(ctx, "origin-hits.json")) == 1
    refute File.exists?(rules_path(ctx))

    second = turn(pid, thread, "2")
    {next, [current]} = finish_decision(pid, thread, second, "decline", true)
    assert_approval(current, thread, second)
    assert current.handle != approval.handle
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "rejected by user"
    refute command_outputs(next) |> Enum.join("\n") =~ "owned network request succeeded"
    assert length(read(ctx, "origin-hits.json")) == 1
    refute File.exists?(rules_path(ctx))
    assert length(read(ctx, "requests.json")) == 4
    assert Session.status(pid).interactions == 0
    assert :ok = Session.close(pid)
  end

  test "session network acceptance permits a later request without writing a persistent rule",
       ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    {events, [approval]} = finish_decision(pid, thread, first, "acceptForSession", true)
    assert_approval(approval, thread, first)
    assert_network_success(events)
    assert length(read(ctx, "origin-hits.json")) == 1
    refute File.exists?(rules_path(ctx))

    second = turn(pid, thread, "2")
    {next, []} = finish_decision(pid, thread, second, "acceptForSession", false)
    assert_network_success(next)
    assert length(read(ctx, "origin-hits.json")) == 2
    refute File.exists?(rules_path(ctx))
    assert length(read(ctx, "requests.json")) == 4
    assert Session.status(pid).interactions == 0
    assert :ok = Session.close(pid)
  end

  test "an equivalent edited network host persists only the canonical approved destination",
       ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    decision = network_decision(" 127.0.0.3. ", "allow")
    {events, [approval]} = finish_decision(pid, thread, first, decision, true)
    assert_approval(approval, thread, first)
    assert_network_success(events)
    assert length(read(ctx, "origin-hits.json")) == 1

    expected =
      ~s|network_rule(host="#{@host}", protocol="http", decision="allow", justification="Allow http access to #{@host}")\n|

    assert File.read!(rules_path(ctx)) == expected
    second = turn(pid, thread, "2")
    {next, []} = finish_decision(pid, thread, second, decision, false)
    assert_network_success(next)
    assert length(read(ctx, "origin-hits.json")) == 2
    assert File.read!(rules_path(ctx)) == expected
    assert length(read(ctx, "requests.json")) == 4
    assert Session.status(pid).interactions == 0
    assert :ok = Session.close(pid)
  end

  test "a different-host allow amendment warns and requires a new original-host decision", ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    decision = network_decision("127.0.0.4", "allow")
    {events, [approval]} = finish_decision(pid, thread, first, decision, true)
    assert_approval(approval, thread, first)
    assert_mismatch_warning(events, thread)
    assert tool_outputs(ctx, "owned-network-1") |> Enum.join("\n") =~ "blocked by policy"
    assert_no_network_effect(ctx, events)
    assert_stale(pid, approval)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 0)

    second = turn(pid, thread, "2")
    {next, [current]} = finish_decision(pid, thread, second, "decline", true)
    assert_approval(current, thread, second)
    assert current.handle != approval.handle
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, next)
    assert network_warnings(next) == []
    assert_stale(pid, current)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 2)
    assert :ok = Session.close(pid)
  end

  test "a different-host deny amendment warns but caches denial of the original host", ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    decision = network_decision("127.0.0.4", "deny")
    {events, [approval]} = finish_decision(pid, thread, first, decision, true)
    assert_approval(approval, thread, first)
    assert_mismatch_warning(events, thread)
    assert tool_outputs(ctx, "owned-network-1") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, events)
    assert_stale(pid, approval)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 0)

    second = turn(pid, thread, "2")
    {next, []} = finish_decision(pid, thread, second, "decline", false)
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "blocked"
    assert_no_network_effect(ctx, next)
    assert network_warnings(next) == []
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 2)
    assert :ok = Session.close(pid)
  end

  test "an explicit network approval error grants no access and permits a later explicit decision",
       ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    error = {:error, %{"code" => -32_001, "message" => "Synthetic explicit refusal"}}
    {events, [approval]} = finish_response(pid, thread, first, error, true, "completed")
    assert_approval(approval, thread, first)
    assert tool_outputs(ctx, "owned-network-1") |> Enum.join("\n") =~ "approval request failed"
    assert_no_network_effect(ctx, events)
    assert network_warnings(events) == []
    assert_stale(pid, approval)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 0)

    second = turn(pid, thread, "2")
    {next, [current]} = finish_decision(pid, thread, second, "decline", true)
    assert_approval(current, thread, second)
    assert current.handle != approval.handle
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, next)
    assert_stale(pid, current)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 2)
    assert :ok = Session.close(pid)
  end

  test "declining network access completes the turn without a session grant", ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    {events, [approval]} = finish_decision(pid, thread, first, "decline", true)
    assert_approval(approval, thread, first)
    assert tool_outputs(ctx, "owned-network-1") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, events)
    assert network_warnings(events) == []
    assert_stale(pid, approval)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 0)

    second = turn(pid, thread, "2")
    {next, [current]} = finish_decision(pid, thread, second, "decline", true)
    assert_approval(current, thread, second)
    assert current.handle != approval.handle
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, next)
    assert_stale(pid, current)
    assert_idle(pid)
    assert_provider_counts(ctx, 2, 2)
    assert :ok = Session.close(pid)
  end

  test "cancelling network approval interrupts the turn without granting host access",
       ctx do
    pid = client(ctx)
    thread = network_thread(pid, ctx)
    first = turn(pid, thread, "1")
    response = {:ok, %{"decision" => "cancel"}}
    {events, [approval]} = finish_response(pid, thread, first, response, true, "interrupted")
    assert_approval(approval, thread, first)
    assert_no_network_effect(ctx, events)
    assert network_warnings(events) == []
    assert_stale(pid, approval)
    assert_idle(pid)
    assert_provider_counts(ctx, 1, 0)

    # This is an explicitly new turn after interruption, never a timeout retry.
    second = turn(pid, thread, "2")
    {next, [current]} = finish_decision(pid, thread, second, "decline", true)
    assert_approval(current, thread, second)
    assert current.handle != approval.handle
    assert tool_outputs(ctx, "owned-network-2") |> Enum.join("\n") =~ "rejected by user"
    assert_no_network_effect(ctx, next)
    assert_stale(pid, current)
    assert_idle(pid)
    assert_provider_counts(ctx, 1, 2)
    assert :ok = Session.close(pid)
  end

  defp assert_no_network_effect(ctx, events) do
    assert read(ctx, "origin-hits.json") == []
    refute File.exists?(rules_path(ctx))
    refute command_outputs(events) |> Enum.join("\n") =~ "owned network request succeeded"
  end

  defp assert_mismatch_warning(events, thread) do
    message =
      "Failed to apply network policy amendment: network policy amendment host '127.0.0.4' " <>
        "does not match approved host '#{@host}'"

    assert network_warnings(events) == [%{"threadId" => thread, "message" => message}]
  end

  defp network_warnings(events) do
    for event <- events,
        event.wire["method"] == "warning",
        String.starts_with?(
          event.wire["params"]["message"],
          "Failed to apply network policy amendment:"
        ),
        do: event.wire["params"]
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp assert_idle(pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
  end

  defp assert_provider_counts(ctx, first, second) do
    counts =
      for request <- read(ctx, "requests.json") do
        markers =
          for item <- request["input"],
              item["role"] == "user",
              part <- item["content"] || [],
              part["type"] == "input_text",
              part["text"] in ["synthetic:network:1", "synthetic:network:2"],
              do: part["text"]

        assert markers != []
        List.last(markers)
      end
      |> Enum.frequencies()

    expected = %{"synthetic:network:1" => first}

    expected =
      if second == 0, do: expected, else: Map.put(expected, "synthetic:network:2", second)

    assert counts == expected
  end

  defp network_thread(pid, ctx) do
    call(pid, "thread/start", %{
      "cwd" => Path.join(ctx.root, "workspace"),
      "historyMode" => "legacy",
      "model" => "mock-model",
      "modelProvider" => "fixture",
      "sandbox" => "read-only",
      "approvalPolicy" => "on-request",
      "approvalsReviewer" => "user"
    })["thread"]["id"]
  end

  defp network_decision(host, action) do
    %{
      "applyNetworkPolicyAmendment" => %{
        "network_policy_amendment" => %{"host" => host, "action" => action}
      }
    }
  end

  defp assert_network_success(events) do
    output = command_outputs(events) |> Enum.join("\n")
    assert output =~ "owned direct access blocked"
    assert output =~ "owned network request succeeded"
  end

  defp rules_path(ctx), do: Path.join(ctx.root, "codex/rules/default.rules")

  defp client(ctx) do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_network", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp turn(pid, thread, marker) do
    call(pid, "turn/start", %{
      "threadId" => thread,
      "input" => [%{"type" => "text", "text" => "synthetic:network:" <> marker}]
    })["turn"]["id"]
  end

  defp assert_approval(event, thread, turn) do
    assert event.wire["method"] == "item/commandExecution/requestApproval"
    params = event.wire["params"]
    assert params["threadId"] == thread and params["turnId"] == turn
    assert params["networkApprovalContext"] == %{"host" => @host, "protocol" => "http"}

    assert params["proposedNetworkPolicyAmendments"] == [
             %{"host" => @host, "action" => "allow"},
             %{"host" => @host, "action" => "deny"}
           ]

    for key <- ~w(command cwd commandActions proposedExecpolicyAmendment),
        do: assert(params[key] == nil)

    assert event.handle.id == event.wire["id"]
    assert is_reference(event.handle.reference)
  end

  defp finish(pid, thread, turn, action, expected) do
    finish_decision(pid, thread, turn, network_decision(@host, action), expected)
  end

  defp finish_decision(pid, thread, turn, decision, expected) do
    finish_response(pid, thread, turn, {:ok, %{"decision" => decision}}, expected, "completed")
  end

  defp finish_response(pid, thread, turn, response, expected, terminal_status) do
    finish_loop(pid, thread, turn, response, {expected, terminal_status}, [], [], now() + 20_000)
  end

  defp finish_loop(
         pid,
         thread,
         turn,
         response,
         {expected, terminal_status},
         acc,
         approvals,
         deadline
       ) do
    assert {:ok, incoming} = Session.drain(pid)

    approvals =
      Enum.reduce(incoming, approvals, fn event, seen ->
        if event.kind == :server_request do
          assert expected and seen == [], "unexpected native approval; never auto-accept"
          assert_approval(event, thread, turn)

          assert :ok =
                   Session.respond(
                     pid,
                     event.handle,
                     response
                   )

          seen ++ [event]
        else
          seen
        end
      end)

    acc = acc ++ incoming

    completed =
      Enum.find(
        acc,
        &(get_in(&1, [:wire, "method"]) == "turn/completed" and
            get_in(&1, [:wire, "params", "turn", "id"]) == turn)
      )

    if completed do
      assert completed.wire["params"]["turn"]["status"] == terminal_status
      assert length(approvals) == if(expected, do: 1, else: 0)
      {acc, approvals}
    else
      assert now() < deadline, "native managed-network turn deadline"

      receive do
      after
        10 -> :ok
      end

      finish_loop(
        pid,
        thread,
        turn,
        response,
        {expected, terminal_status},
        acc,
        approvals,
        deadline
      )
    end
  end

  defp command_outputs(events) do
    for event <- events,
        event.wire["method"] == "item/completed",
        item = event.wire["params"]["item"],
        item["type"] == "commandExecution",
        do: item["aggregatedOutput"] || ""
  end

  defp tool_outputs(ctx, call_id) do
    for request <- read(ctx, "requests.json"),
        item <- request["input"],
        item["type"] == "function_call_output" and item["call_id"] == call_id,
        do: if(is_binary(item["output"]), do: item["output"], else: JSON.encode!(item["output"]))
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp read(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp now, do: System.monotonic_time(:millisecond)
  defp await(fun, label), do: await(fun, label, now() + 10_000)

  defp await(fun, label, deadline) do
    if fun.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(fun, label, deadline)
    end
  end
end
