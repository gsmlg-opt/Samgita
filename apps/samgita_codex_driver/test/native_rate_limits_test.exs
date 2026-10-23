defmodule SamgitaCodexDriver.NativeRateLimitsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/rate_limits_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @canary "OWNED_RATE_LIMITS_PRIVATE_CANARY"
  @method "account/rateLimits/updated"
  @empty_snapshot %{
    "limitId" => "codex",
    "limitName" => nil,
    "normalModelSlug" => nil,
    "primary" => nil,
    "secondary" => nil,
    "credits" => nil,
    "individualLimit" => nil,
    "spendControlReached" => nil,
    "planType" => nil,
    "rateLimitReachedType" => nil
  }

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
        "samgita-rate-limits-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    File.mkdir!(root)

    for directory <- ["home", "codex", "workspace", "tmp", "bin"],
        do: File.mkdir_p!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      scenario: tags.scenario,
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
          ctx.scenario
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
      assert length(read_json(ctx, "requests.json")) == 1
      refute File.exists?(Path.join(root, "unexpected-inference.json"))

      if File.exists?(Path.join(root, "state.json")) do
        proof = read_json(ctx, "state.json")

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do:
              await(
                fn -> not File.exists?("/proc/#{os_pid}") end,
                "owned rate-limit process reaping"
              )
      end
    end)

    await(fn -> ready?(ctx) end, "private rate-limit namespace/native UDS startup")
    proof = read_json(ctx, "state.json")
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert File.read!(Path.join(root, "codex/config.toml")) =~ @canary
    ctx
  end

  @tag scenario: "windows"
  test "native stable notice rounds windows and preserves named quota and decimal credit strings",
       ctx do
    expected =
      Map.merge(@empty_snapshot, %{
        "limitName" => "Owned Codex quota",
        "primary" => %{
          "usedPercent" => 13,
          "windowDurationMins" => 60,
          "resetsAt" => 1_704_069_000
        },
        "secondary" => %{
          "usedPercent" => 99,
          "windowDurationMins" => 10_080,
          "resetsAt" => 1_704_673_800
        },
        "credits" => %{"hasCredits" => true, "unlimited" => false, "balance" => "123.4500"}
      })

    assert_rate_limits(ctx, expected, false)
  end

  @tag scenario: "alternate"
  test "additional header family normalizes identity and supersedes the default before fanout",
       ctx do
    expected =
      Map.merge(@empty_snapshot, %{
        "limitId" => "codex_other",
        "limitName" => "Owned alternate quota",
        "primary" => %{"usedPercent" => 0, "windowDurationMins" => nil, "resetsAt" => 0},
        "secondary" => %{"usedPercent" => 43, "windowDurationMins" => 1_440, "resetsAt" => -1}
      })

    assert_rate_limits(ctx, expected, true)
  end

  @tag scenario: "credits-only"
  test "credits-only sparse update retains false and true with a null blank balance", ctx do
    expected =
      Map.put(@empty_snapshot, "credits", %{
        "hasCredits" => false,
        "unlimited" => true,
        "balance" => nil
      })

    assert_rate_limits(ctx, expected, false)
  end

  @tag scenario: "sparse"
  test "partial window retains nullable metadata while empty zero window and invalid credits drop",
       ctx do
    expected =
      Map.put(@empty_snapshot, "primary", %{
        "usedPercent" => 2,
        "windowDurationMins" => nil,
        "resetsAt" => nil
      })

    assert_rate_limits(ctx, expected, false)
  end

  @tag scenario: "malformed"
  test "nonfinite and malformed headers produce native nulls without invented account fields",
       ctx do
    assert_rate_limits(ctx, @empty_snapshot, false)
  end

  @tag scenario: "empty"
  test "absent headers still produce the pinned default sparse rolling update", ctx do
    assert_rate_limits(ctx, @empty_snapshot, true)
  end

  defp assert_rate_limits(ctx, expected, experimental) do
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
               %{"name" => "owned_rate_limits", "version" => "0.1.0"},
               %{"experimentalApi" => experimental}
             )

    thread =
      call(pid, "thread/start", %{
        "cwd" => ctx.workspace,
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request"
      })["thread"]["id"]

    startup = drain(pid)
    assert read_json(ctx, "requests.json") == []
    assert notifications(startup, @method) == []

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:rate-limits:" <> ctx.scenario}]
      })["turn"]["id"]

    events = collect(pid, thread, turn, startup)
    rates = notifications(events, @method)
    assert rates != []
    assert Enum.all?(rates, &(&1 == %{"rateLimits" => expected}))

    for event <- Enum.filter(events, &(&1.wire["method"] == @method)),
        do: assert(event.kind == :notification)

    assert_completed_turn(events, thread, turn)
    assert length(read_json(ctx, "requests.json")) == 1
    refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))
    refute JSON.encode!(Enum.map(events, & &1.wire)) =~ @canary
    refute JSON.encode!(read_json(ctx, "requests.json")) =~ @canary
    assert %{phase: :ready, pending: 0, uncertain: 0, interactions: 0} = Session.status(pid)
  end

  defp assert_completed_turn(events, thread, turn) do
    assert Enum.any?(notifications(events, "turn/completed"), fn params ->
             params["threadId"] == thread and params["turn"]["id"] == turn and
               params["turn"]["status"] == "completed"
           end)

    for event <- Enum.filter(events, &(&1.wire["method"] in ["item/started", "item/completed"])),
        do: assert(event.wire["params"]["item"]["type"] in ["userMessage", "agentMessage"])

    assert Enum.any?(notifications(events, "item/completed"), fn params ->
             params["threadId"] == thread and params["turnId"] == turn and
               params["item"]["type"] == "agentMessage" and
               params["item"]["text"] == "Owned rate-limit response."
           end)
  end

  defp notifications(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

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

  defp collect(pid, thread, turn, events, deadline \\ nil) do
    deadline = deadline || now() + 5_000
    events = events ++ drain(pid)

    completed =
      Enum.any?(notifications(events, "turn/completed"), fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if completed and notifications(events, @method) != [] do
      events
    else
      assert now() < deadline, "native rate-limit barrier: #{inspect(Session.status(pid))}"

      receive do
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, deadline)
    end
  end

  defp ready?(ctx) do
    if File.exists?(Path.join(ctx.root, "state.json")),
      do: read_json(ctx, "state.json")["ready"] and File.exists?(ctx.socket),
      else: false
  end

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
