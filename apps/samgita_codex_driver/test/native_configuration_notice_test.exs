defmodule SamgitaCodexDriver.NativeConfigurationNoticeTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/configuration_notice_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @read_summary "Full-history hydration is deprecated for paginated threads; omit `includeTurns` or set it to `false`, then page with `thread/turns/list` and `thread/items/list`."
  @tier_warning "Configured service tier `priority` is not advertised as supported for model `mock-model` and will be omitted from requests."

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    for tool <- ["python3", "unshare", "ip"],
        do: assert(System.find_executable(tool), "BLOCKED_ENV: #{tool} required")

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-configuration-notice-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ["home", "codex", "workspace", "tmp", "bin"],
        do: File.mkdir_p!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      parent_namespace: File.read_link!("/proc/self/ns/net")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [
          @script,
          "--root",
          root,
          "--codex",
          Path.expand(binary),
          "--scenario",
          tags[:scenario] || "clean"
        ],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      assert length(read_json(ctx, "requests.json")) ==
               if(tags[:scenario] == "history", do: 1, else: 0)

      refute File.exists?(Path.join(root, "unexpected-inference.json"))

      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do:
              await(fn -> not File.exists?("/proc/#{os_pid}") end, "owned notice fixture reaping")
      end
    end)

    await(fn -> ready?(ctx) end, "private notice namespace/native UDS startup")
    proof = state(ctx)
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    ctx
  end

  @tag scenario: "ignored"
  test "startup ignored-key warnings redact values and do not repeat on plain thread registration",
       ctx do
    pid = client(ctx)

    events =
      collect(pid, fn events ->
        notification(events, "configWarning", &ignored_summary?/1)
      end)

    warning = notification(events, "configWarning", &ignored_summary?/1)
    assert warning["summary"] =~ "`network_proxy` is ignored."
    refute warning["summary"] =~ "owned-private-marker"
    assert Map.fetch!(warning, "details") == nil
    refute Map.has_key?(warning, "path")
    refute Map.has_key?(warning, "range")
    thread(pid, ctx)
    after_start = drain(pid)
    refute notification(after_start, "configWarning", &(&1 == warning))
    assert_no_work(ctx, events ++ after_start)
  end

  test "native thread registration reports a newly malformed owned rule with real path and range",
       ctx do
    pid = client(ctx)
    before = drain(pid)
    rules = Path.join(ctx.root, "codex/rules")
    File.mkdir_p!(rules)
    path = Path.join(rules, "broken.rules")
    File.write!(path, "prefix_rule(")
    thread(pid, ctx)

    events =
      collect(pid, fn events ->
        notification(
          events,
          "configWarning",
          &(&1["summary"] == "Error parsing rules; custom rules not applied.")
        )
      end)

    warning =
      notification(
        events,
        "configWarning",
        &(&1["summary"] == "Error parsing rules; custom rules not applied.")
      )

    assert warning["path"] == path

    assert warning["range"] == %{
             "start" => %{"line" => 1, "column" => 13},
             "end" => %{"line" => 1, "column" => 13}
           }

    assert warning["details"] =~ "failed to parse rules file"
    assert warning["details"] =~ "broken.rules"
    assert warning["details"] =~ "Parse error"
    assert File.read!(path) == "prefix_rule("
    assert_no_work(ctx, before ++ events)
  end

  test "empty paginated registration reports unsupported hydration without a false deprecation",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{"historyMode" => "paginated"})
    startup = drain(pid)
    assert call(pid, "thread/read", %{"threadId" => thread})["thread"]["turns"] == []

    assert {:error, failure} =
             Session.request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})

    assert failure.wire["error"] == %{
             "code" => -32_601,
             "message" => "list_turns is not supported yet"
           }

    events = drain(pid)
    refute notification(events, "deprecationNotice", fn _ -> true end)
    assert_no_work(ctx, startup ++ events)
  end

  @tag scenario: "history"
  test "actual persisted paginated thread emits deprecation only for full history hydration",
       ctx do
    pid = client(ctx)
    thread = thread(pid, ctx, %{"historyMode" => "paginated"})
    startup = drain(pid)
    assert_no_work(ctx, startup)

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:configuration-notice-history"}]
      })["turn"]["id"]

    history =
      collect(
        pid,
        &notification(&1, "turn/completed", fn params -> params["turn"]["id"] == turn end)
      )

    assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(history, "turn/completed", &(&1["turn"]["id"] == turn))

    assert Enum.any?(call(pid, "thread/list", %{})["data"], &(&1["id"] == thread))

    for options <- [%{}, %{"includeTurns" => false}] do
      assert call(pid, "thread/read", Map.merge(%{"threadId" => thread}, options))["thread"]["id"] ==
               thread
    end

    metadata_events = drain(pid)
    refute notification(metadata_events, "deprecationNotice", fn _ -> true end)
    response = call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})
    assert response["thread"]["id"] == thread
    assert response["thread"]["historyMode"] == "paginated"

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             response["thread"]["turns"]

    assert Enum.any?(
             items,
             &(&1["type"] == "agentMessage" and &1["text"] == "Owned notice history.")
           )

    assert Enum.all?(items, &(&1["type"] in ["userMessage", "agentMessage"]))
    events = collect(pid, &notification(&1, "deprecationNotice", fn _ -> true end))

    assert notification(events, "deprecationNotice", fn _ -> true end) == %{
             "summary" => @read_summary,
             "details" => nil
           }

    assert length(read_json(ctx, "requests.json")) == 1
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))

    refute Enum.any?(
             startup ++ history ++ metadata_events ++ events,
             &(&1.kind == :server_request)
           )
  end

  @tag scenario: "tier"
  test "unsupported configured priority produces a native thread-scoped warning without inference",
       ctx do
    pid = client(ctx)
    before = drain(pid)
    thread = thread(pid, ctx)

    events =
      collect(pid, fn events ->
        notification(events, "warning", &(&1["message"] == @tier_warning))
      end)

    assert notification(events, "warning", &(&1["message"] == @tier_warning)) == %{
             "threadId" => thread,
             "message" => @tier_warning
           }

    assert call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => false})["thread"][
             "turns"
           ] == []

    assert_no_work(ctx, before ++ events ++ drain(pid))
  end

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
               %{"name" => "samgita_owned_notices", "version" => "0.1.0"},
               %{
                 "experimentalApi" => true
               }
             )

    pid
  end

  defp thread(pid, ctx, extra \\ %{}) do
    call(
      pid,
      "thread/start",
      Map.merge(
        %{
          "cwd" => ctx.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request"
        },
        extra
      )
    )["thread"]["id"]
  end

  defp ignored_summary?(params), do: params["summary"] =~ "`network_proxy` is ignored."

  defp assert_no_work(ctx, events) do
    assert read_json(ctx, "requests.json") == []
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))
    refute Enum.any?(events, &(&1.kind == :server_request))
    refute Enum.any?(events, &(&1.wire["method"] in ["turn/started", "item/started"]))
  end

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, failure} -> flunk("owned native #{method} failed: #{inspect(failure.wire)}")
    end
  end

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request)), "unapproved native server request"
    events
  end

  defp notification(events, method, predicate) do
    Enum.find_value(events, fn event ->
      if event.wire["method"] == method and predicate.(event.wire["params"]),
        do: event.wire["params"]
    end)
  end

  defp collect(pid, predicate, events \\ [], deadline \\ nil) do
    deadline = deadline || now() + 5_000
    events = events ++ drain(pid)

    if predicate.(events) do
      events
    else
      assert now() < deadline, "native local notice barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      collect(pid, predicate, events, deadline)
    end
  end

  defp ready?(ctx) do
    if File.exists?(Path.join(ctx.root, "state.json")),
      do: state(ctx)["ready"] and File.exists?(ctx.socket),
      else: false
  end

  defp state(ctx), do: read_json(ctx, "state.json")
  defp read_json(ctx, path), do: ctx.root |> Path.join(path) |> File.read!() |> JSON.decode!()

  defp await(predicate, label, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    if predicate.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(predicate, label, deadline)
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
