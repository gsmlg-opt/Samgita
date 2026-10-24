defmodule SamgitaCodexDriver.NativeProviderErrorsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/provider_error_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @rate_message "rate limit exceeded: Owned provider rate limit."
  @overload_message "Selected model is at capacity. Please try a different model."

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
        "samgita-provider-errors-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
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
          "PATH" =>
            Path.join(root, "bin") <>
              ":" <>
              System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = read_json(ctx, "state.json")

        for os_pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do:
              await(fn -> not File.exists?("/proc/#{os_pid}") end, "owned error process reaping")
      end
    end)

    await(fn -> ready?(ctx) end, "owned provider error namespace/native startup")
    proof = read_json(ctx, "state.json")
    assert proof["parent_namespace"] == ctx.parent_namespace
    assert proof["namespace"] != ctx.parent_namespace
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    ctx
  end

  for scenario <- ["rate-recovered", "rate-exhausted", "overload-terminal"] do
    @tag scenario: scenario
    test "#{scenario} distinguishes retry notices, terminal errors and explicit next-turn recovery",
         ctx do
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
                 %{"name" => "owned_provider_errors", "version" => "0.1.0"},
                 %{"experimentalApi" => false}
               )

      thread =
        call(pid, "thread/start", %{
          "cwd" => ctx.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request"
        })[
          "thread"
        ]["id"]

      drain(pid)
      assert read_json(ctx, "requests.json") == []
      marker = "synthetic:provider-error:" <> ctx.scenario
      turn = turn(pid, thread, marker)
      events = collect(pid, thread, turn)
      errors = notices(events, "error")
      expected_retries = if ctx.scenario == "overload-terminal", do: [], else: [true]

      expected_retries =
        if ctx.scenario == "rate-recovered",
          do: expected_retries,
          else: expected_retries ++ [false]

      assert Enum.map(errors, & &1["willRetry"]) == expected_retries
      assert Enum.all?(errors, &(&1["threadId"] == thread and &1["turnId"] == turn))

      assert Enum.all?(
               Enum.filter(events, &(&1.wire["method"] == "error")),
               &(&1.kind == :notification)
             )

      for retry <- Enum.filter(errors, & &1["willRetry"]) do
        assert retry["error"] == %{
                 "message" => "Reconnecting... 1/1",
                 "codexErrorInfo" => %{"responseStreamDisconnected" => %{"httpStatusCode" => nil}},
                 "additionalDetails" => @rate_message,
                 "misalignment" => nil
               }
      end

      completed = completed(events, thread, turn)
      initial_count = if ctx.scenario == "overload-terminal", do: 1, else: 2
      initial_requests = read_json(ctx, "requests.json")
      assert length(initial_requests) == initial_count
      assert Enum.all?(initial_requests, &(&1["input"] == hd(initial_requests)["input"]))

      if ctx.scenario == "rate-recovered" do
        assert completed["turn"]["status"] == "completed"
        assert Map.fetch!(completed["turn"], "error") == nil
        assert_answer(events, thread, turn)
      else
        assert completed["turn"]["status"] == "failed"
        terminal = List.last(errors)["error"]

        expected_info =
          if ctx.scenario == "rate-exhausted",
            do: "rateLimitExceeded",
            else: "serverOverloaded"

        expected_message =
          if ctx.scenario == "rate-exhausted",
            do: @rate_message,
            else: @overload_message

        assert terminal == %{
                 "message" => expected_message,
                 "codexErrorInfo" => expected_info,
                 "additionalDetails" => nil,
                 "misalignment" => nil
               }

        assert completed["turn"]["error"] == terminal

        refute Enum.any?(
                 notices(events, "item/completed"),
                 &(&1["item"]["type"] == "agentMessage")
               )
      end

      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)

      # A new caller operation is explicit recovery; the driver never replays
      # the failed turn or silently starts another sampling/execution operation.
      next_turn = turn(pid, thread, marker <> ":explicit-next-turn")
      refute next_turn == turn
      next_events = collect(pid, thread, next_turn)
      assert notices(next_events, "error") == []
      next_completed = completed(next_events, thread, next_turn)
      assert next_completed["turn"]["status"] == "completed"
      assert Map.fetch!(next_completed["turn"], "error") == nil
      assert_answer(next_events, thread, next_turn)
      assert length(read_json(ctx, "requests.json")) == initial_count + 1
      refute File.exists?(Path.join(ctx.root, "unexpected-inference.json"))
      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)
    end
  end

  defp assert_answer(events, thread, turn) do
    assert Enum.count(notices(events, "item/completed"), fn p ->
             p["threadId"] == thread and p["turnId"] == turn and
               p["item"]["type"] == "agentMessage" and
               p["item"]["text"] == "Owned provider error recovery."
           end) == 1
  end

  defp turn(pid, thread, text),
    do:
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

  defp call(pid, method, params) do
    case Session.request(pid, method, params) do
      {:ok, %{"result" => result}} -> result
      {:error, failure} -> flunk("owned native #{method} failed: #{inspect(failure.wire)}")
    end
  end

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp completed(events, thread, turn),
    do:
      Enum.find(
        notices(events, "turn/completed"),
        &(&1["threadId"] == thread and &1["turn"]["id"] == turn)
      )

  defp drain(pid) do
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request)), "unapproved native server request"
    events
  end

  defp collect(pid, thread, turn, events \\ [], deadline \\ nil) do
    deadline = deadline || now() + 5_000
    events = events ++ drain(pid)

    if completed(events, thread, turn) do
      events
    else
      assert now() < deadline, "native provider error barrier: #{inspect(Session.status(pid))}"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("unexpected provider error event gap")
      after
        10 -> :ok
      end

      collect(pid, thread, turn, events, deadline)
    end
  end

  defp ready?(ctx),
    do:
      File.exists?(Path.join(ctx.root, "state.json")) and
        read_json(ctx, "state.json")["ready"] and File.exists?(ctx.socket)

  defp read_json(ctx, path), do: ctx.root |> Path.join(path) |> File.read!() |> JSON.decode!()
  defp now, do: System.monotonic_time(:millisecond)

  defp await(predicate, label, deadline \\ nil) do
    deadline = deadline || now() + 5_000

    unless predicate.() do
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(predicate, label, deadline)
    end
  end
end
