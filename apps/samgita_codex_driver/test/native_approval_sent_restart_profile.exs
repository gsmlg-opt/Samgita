defmodule SamgitaCodexDriver.SentRestartTransport do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport

  alias SamgitaCodexDriver.Transport.UnixSocket

  # Test-only loss at the client transport boundary. Every delivered app-server
  # frame is unchanged native output. This wrapper never generates wire frames.
  @impl true
  def open(opts) do
    control = Keyword.fetch!(opts, :control)
    opts = Keyword.delete(opts, :control)

    with {:ok, socket} <- UnixSocket.open(opts) do
      Agent.update(control, &%{&1 | opens: &1.opens + 1, blackhole: false})
      {:ok, %{socket: socket, control: control}}
    end
  end

  @impl true
  def send(state, encoded) do
    wire = JSON.decode!(encoded)

    disposition =
      Agent.get_and_update(state.control, fn control ->
        reply = Map.has_key?(wire, "id") and not Map.has_key?(wire, "method")
        targeted = reply and wire["id"] == control.target

        {disposition, control} =
          case {targeted, control.mode} do
            {true, :drop_reply_once} ->
              {:dropped, %{control | mode: :normal}}

            {true, :suppress_notifications_after_reply} ->
              {:forwarded, %{control | mode: :normal, blackhole: true}}

            _ ->
              {:forwarded, control}
          end

        entry = %{
          generation: control.opens,
          kind: if(reply, do: :reply, else: :method),
          id: wire["id"],
          method: wire["method"],
          digest: Base.encode16(:crypto.hash(:sha256, encoded), case: :lower),
          disposition: disposition
        }

        true = length(control.outbound) < 128
        {disposition, %{control | outbound: control.outbound ++ [entry]}}
      end)

    case disposition do
      # A successful local send followed by loss before peer receipt is one
      # possible network outcome. It does not establish remote acceptance.
      :dropped -> {:ok, state}
      :forwarded -> wrap(UnixSocket.send(state.socket, encoded), state)
    end
  end

  @impl true
  def handle_info(message, state) do
    case UnixSocket.handle_info(message, state.socket) do
      {:ok, events, socket} ->
        events = Enum.reject(events, &discard?(&1, state.control))
        {:ok, events, %{state | socket: socket}}

      other ->
        wrap(other, state)
    end
  end

  defp discard?({:message, encoded}, control) do
    wire = JSON.decode!(encoded)

    Agent.get_and_update(control, fn state ->
      if state.blackhole and Map.has_key?(wire, "method") and not Map.has_key?(wire, "id") do
        params = wire["params"] || %{}

        entry = %{
          generation: state.opens,
          method: wire["method"],
          thread_id: params["threadId"],
          request_id: params["requestId"],
          turn_id: get_in(params, ["turn", "id"]),
          turn_status: get_in(params, ["turn", "status"]),
          digest: :crypto.hash(:sha256, encoded)
        }

        true = length(state.discarded) < 256
        {true, %{state | discarded: state.discarded ++ [entry]}}
      else
        {false, state}
      end
    end)
  end

  defp discard?(_event, _control), do: false

  defp wrap({:ok, socket}, state), do: {:ok, %{state | socket: socket}}
  defp wrap({:error, error, socket}, state), do: {:error, error, %{state | socket: socket}}
  defp wrap(:unknown, _state), do: :unknown

  @impl true
  def close(state), do: UnixSocket.close(state.socket)

  @impl true
  def metadata(state),
    do: Map.put(UnixSocket.metadata(state.socket), "test_fault_injection", true)
end

defmodule SamgitaCodexDriver.NativeApprovalSentRestartProfileTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{SentRestartTransport, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Error, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_approval_sent_restart_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @input "Owned sent-unconfirmed cold approval"
  @command "echo 'owned recovered command' >> loss-command.txt; printf samgita_loss_command"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-sent-cold-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, directory))

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary), "--branch", tags.branch],
        cwd: Path.join(root, "workspace"),
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => Path.join(root, "bin") <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    ctx = %{root: root, owner: owner, branch: tags.branch}
    on_exit(fn -> cleanup(ctx) end)
    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = json(ctx, "state.json")
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false

    assert [%{"branch" => branch, "source_provider_requests" => 0, "request_auth" => "none"}] =
             Enum.map(
               events(ctx, "sent_provider_ready"),
               &Map.take(&1, ~w(branch source_provider_requests request_auth))
             )

    assert branch == tags.branch
    config = File.read!(Path.join(root, "codex/config.toml"))

    for value <- [
          "cli_auth_credentials_store = \"file\"",
          "requires_openai_auth = false",
          "supports_websockets = false",
          "enable_request_compression = false",
          "[analytics]\nenabled = false"
        ],
        do: assert(config =~ value)

    refute config =~ "experimental_bearer_token"
    refute config =~ "experimental_realtime"
    refute File.exists?(Path.join(root, "codex/auth.json"))

    {:ok, control} =
      Agent.start_link(fn ->
        %{opens: 0, mode: :normal, target: nil, blackhole: false, outbound: [], discarded: []}
      end)

    on_exit(fn -> if Process.alive?(control), do: Agent.stop(control) end)

    {:ok, pid} =
      Session.start_link(
        transport:
          {SentRestartTransport, [socket_path: Path.join(root, "native.sock"), control: control]},
        request_timeout_ms: 10_000,
        interaction_timeout_ms: 60_000
      )

    on_exit(fn -> if Process.alive?(pid), do: assert(:ok = Session.close(pid)) end)
    initialize(pid)
    Map.merge(ctx, %{pid: pid, control: control})
  end

  for branch <- ~w(dropped forwarded) do
    @tag branch: branch
    test "#{branch} sent-unconfirmed approval survives native loss without response or command replay",
         ctx do
      pid = ctx.pid

      thread =
        call(pid, "thread/start", %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => Path.join(ctx.root, "workspace"),
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "historyMode" => "paginated",
          "ephemeral" => false
        })["thread"]["id"]

      turn =
        call(pid, "turn/start", %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => @input}]
        })["turn"]["id"]

      initial = collect(pid, &Enum.any?(&1, fn e -> e.kind == :server_request end))
      assert [approval] = Enum.filter(initial, &(&1.kind == :server_request))
      assert approval.wire["method"] == "item/commandExecution/requestApproval"
      params = approval.wire["params"]
      assert params["threadId"] == thread and params["turnId"] == turn
      assert params["itemId"] == "sent-cold-command-1" and params["kind"] == "command"
      assert params["cwd"] == Path.join(ctx.root, "workspace")
      assert params["reason"] == "Owned sent-unconfirmed approval only"
      assert OptionParser.split(params["command"]) == argv(ctx)
      assert params["proposedExecpolicyAmendment"] == [Path.join(ctx.root, "bin/sh")]
      assert is_integer(params["startedAtMs"]) and params["startedAtMs"] > 0
      assert_effect(ctx, 0, 1)
      path = read(pid, thread)["path"]
      assert String.starts_with?(path, ctx.root <> "/")
      await(fn -> File.regular?(path) and File.read!(path) =~ @input end)
      original_instance = Session.status(pid).instance_id
      generation = Session.status(pid).generation
      native = json(ctx, "state.json")["native_pid"]

      mode =
        if ctx.branch == "dropped",
          do: :drop_reply_once,
          else: :suppress_notifications_after_reply

      Agent.update(ctx.control, &%{&1 | target: approval.wire["id"], mode: mode})
      expected_wire = %{"id" => approval.wire["id"], "result" => %{"decision" => "accept"}}
      assert {:ok, encoded} = Wire.encode(expected_wire)
      digest = Base.encode16(:crypto.hash(:sha256, encoded), case: :lower)
      assert :ok = Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
      assert_outcome(pid, approval, digest, :sent_unconfirmed)
      assert [sent] = replies(ctx)
      assert sent.digest == digest and sent.id == approval.wire["id"]
      assert sent.disposition == if(ctx.branch == "dropped", do: :dropped, else: :forwarded)

      if ctx.branch == "forwarded" do
        # Observe genuine native completion, but never deliver those notices to Session.
        await(fn ->
          discarded = Agent.get(ctx.control, & &1.discarded)

          Enum.any?(
            discarded,
            &(&1.method == "serverRequest/resolved" and &1.thread_id == thread and
                &1.request_id == approval.wire["id"])
          ) and
            Enum.any?(
              discarded,
              &(&1.method == "turn/completed" and &1.thread_id == thread and
                  &1.turn_id == turn and &1.turn_status == "completed")
            )
        end)

        assert_effect(ctx, 1, 2)
        assert_completed_history(read(pid, thread), turn, ctx)
        # Independently observe an actual persisted command checkpoint before killing.
        await(fn -> persisted_checkpoint?(path, thread, turn, ctx) end)
      else
        assert Agent.get(ctx.control, & &1.discarded) == []
        assert_effect(ctx, 0, 1)
      end

      control(ctx, "crashSentUnconfirmed")

      assert [
               %{
                 "native_pid" => ^native,
                 "returncode" => -9,
                 "reaped" => true,
                 "branch" => branch,
                 "provider_requests" => count
               }
             ] = json(ctx, "sent-crashes.json")

      assert branch == ctx.branch
      assert count == if(ctx.branch == "dropped", do: 1, else: 2)
      refute File.exists?("/proc/#{native}")
      await(fn -> Session.status(pid).phase == :disconnected end)
      assert_outcome(pid, approval, digest, :uncertain)
      assert_stale(pid, approval)
      assert replies(ctx) == [sent]
      # Drain old delivered pre-crash notices; no synthetic app-server frames are used.
      assert {:ok, _old_events} = Session.drain(pid)
      control(ctx, "restart")
      restarted = json(ctx, "state.json")["native_pid"]
      refute restarted == native
      assert :ok = Session.reconnect(pid)
      initialize(pid)
      assert Session.status(pid).instance_id == original_instance
      assert Session.status(pid).generation == generation + 1
      assert_outcome(pid, approval, digest, :uncertain)
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      before_resume = read(pid, thread)
      assert before_resume["status"] == %{"type" => "notLoaded"}
      assert_cold_history(before_resume, turn, ctx)
      assert call(pid, "thread/resume", %{"threadId" => thread})["thread"]["id"] == thread
      assert_cold_history(read(pid, thread), turn, ctx)
      assert_outcome(pid, approval, digest, :uncertain)
      for _ <- 1..2, do: assert_stale(pid, approval)
      assert replies(ctx) == [sent]
      # A native query is an observation barrier, never a response/execution retry.
      call(pid, "thread/loaded/list", %{})
      assert {:ok, cold_events} = Session.drain(pid)

      refute Enum.any?(cold_events, fn event ->
               event.kind == :server_request or
                 event.wire["method"] in [
                   "turn/started",
                   "turn/completed",
                   "item/started",
                   "item/completed",
                   "item/commandExecution/outputDelta"
                 ]
             end)

      methods = Agent.get(ctx.control, &Enum.map(&1.outbound, fn e -> e.method end))
      assert Enum.count(methods, &(&1 == "turn/start")) == 1
      assert Enum.count(methods, &(&1 == "thread/resume")) == 1
      assert_effect(ctx, if(ctx.branch == "dropped", do: 0, else: 1), count)
      assert Session.uncertain_operations(pid) == []
      assert %{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid)

      if ctx.branch == "forwarded" do
        assert :ok = Session.acknowledge_interaction_outcome(pid, approval.handle)
        assert Session.interaction_outcomes(pid) == []
        assert_effect(ctx, 1, 2)
      else
        # Absence of cold callback/command is not an authoritative native abort receipt.
        assert_outcome(pid, approval, digest, :uncertain)
      end

      assert :ok = Session.close(pid)
      control(ctx, "close")
      assert length(events(ctx, "fixture_closed")) == 1
      proof = json(ctx, "state.json")
      assert proof["native_pids"] == [native, restarted]
      started = Enum.map(events(ctx, "native_started"), & &1["pid"])

      finished =
        Enum.map(events(ctx, "native_crashed") ++ events(ctx, "native_stopped"), & &1["pid"])

      assert Enum.sort(started) == Enum.sort([native, restarted])
      assert Enum.sort(finished) == Enum.sort(started)
      for owned <- proof["native_pids"], do: refute(File.exists?("/proc/#{owned}"))
    end
  end

  defp assert_outcome(pid, approval, digest, status) do
    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle == approval.handle and outcome.status == status
    assert outcome.response_digest == digest
    assert outcome.method == "item/commandExecution/requestApproval"
    assert outcome.thread_id == approval.wire["params"]["threadId"]
  end

  defp assert_stale(pid, approval) do
    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})
  end

  defp assert_cold_history(thread, turn, %{branch: "forwarded"} = ctx),
    do: assert_completed_history(thread, turn, ctx)

  defp assert_cold_history(thread, turn, %{branch: "dropped"}) do
    assert [%{"id" => ^turn, "status" => "interrupted"} = original] = thread["turns"]
    assert original["completedAt"] == nil and original["durationMs"] == nil
    assert original["error"] == nil
    assert Enum.filter(original["items"], &(&1["type"] == "commandExecution")) == []
  end

  defp assert_completed_history(thread, turn, ctx) do
    assert [%{"id" => ^turn, "status" => "completed"} = original] = thread["turns"]
    assert original["error"] == nil
    assert [item] = Enum.filter(original["items"], &(&1["type"] == "commandExecution"))
    assert item["id"] == "sent-cold-command-1" and item["status"] == "completed"
    assert item["exitCode"] == 0 and item["aggregatedOutput"] == "samgita_loss_command"
    assert item["cwd"] == Path.join(ctx.root, "workspace")
    assert OptionParser.split(item["command"]) == argv(ctx)

    assert [%{"text" => "Owned sent-unconfirmed command finished"}] =
             Enum.map(
               Enum.filter(original["items"], &(&1["type"] == "agentMessage")),
               &Map.take(&1, ["text"])
             )
  end

  defp persisted_checkpoint?(path, thread, turn, ctx) do
    # Parse only complete JSONL records while the owned writer may append.
    rows = File.read!(path) |> String.split("\n") |> Enum.drop(-1) |> Enum.map(&JSON.decode!/1)

    command = Enum.any?(rows, &persisted_command?(&1, thread, turn, ctx))
    terminal = Enum.any?(rows, &persisted_terminal?(&1, turn))

    command and terminal
  end

  defp persisted_command?(row, thread, turn, ctx) do
    payload = row["payload"] || %{}
    item = payload["item"] || %{}
    expected_event = %{"type" => "item_completed", "thread_id" => thread, "turn_id" => turn}

    expected_command = %{
      "type" => "CommandExecution",
      "id" => "sent-cold-command-1",
      "status" => "completed",
      "command" => argv(ctx),
      "cwd" => "file://" <> Path.join(ctx.root, "workspace"),
      "exit_code" => 0,
      "aggregated_output" => "samgita_loss_command"
    }

    Map.take(payload, Map.keys(expected_event)) == expected_event and
      Map.take(item, Map.keys(expected_command)) == expected_command
  end

  defp persisted_terminal?(row, turn) do
    payload = row["payload"] || %{}

    expected = %{
      "type" => "task_complete",
      "turn_id" => turn,
      "last_agent_message" => "Owned sent-unconfirmed command finished"
    }

    Map.take(payload, Map.keys(expected)) == expected and payload["error"] == nil
  end

  defp assert_effect(ctx, appends, count) do
    control(ctx, "barrier")

    if appends == 0 do
      assert File.ls!(Path.join(ctx.root, "workspace")) == []
    else
      marker = Path.join(ctx.root, "workspace/loss-command.txt")
      assert File.ls!(Path.dirname(marker)) == ["loss-command.txt"]
      assert File.lstat!(marker).type == :regular
      assert File.read!(marker) == "owned recovered command\n"
    end

    assert length(json(ctx, "requests.json")) == count
    assert json(ctx, "provider-errors.json") == []
    assert json(ctx, "rejected-realtime-posts.json") == []

    assert Enum.filter(
             json(ctx, "realtime-journal.json"),
             &(&1["event"] in ["handshake", "native_frame"])
           ) == []

    refute File.exists?(Path.join(ctx.root, "codex/auth.json"))
    refute File.exists?(Path.join(ctx.root, "codex/rules/default.rules"))
  end

  defp argv(ctx), do: [Path.join(ctx.root, "bin/sh"), "-c", @command]

  defp read(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp replies(ctx),
    do: Agent.get(ctx.control, &Enum.filter(&1.outbound, fn e -> e.kind == :reply end))

  defp initialize(pid) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_sent_approval_restart", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp control(ctx, op) do
    id = "sent-cold-#{System.unique_integer([:positive])}"
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"id" => id, "op" => op}))
    await(fn -> Enum.find(events(ctx, "control_done"), &(&1["id"] == id)) end)
  end

  defp collect(pid, predicate, acc \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000
    assert {:ok, batch} = Session.drain(pid)
    acc = acc ++ batch

    if predicate.(acc) do
      acc
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Owned sent approval native event deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected sent approval event gap")
      after
        20 -> :ok
      end

      collect(pid, predicate, acc, deadline)
    end
  end

  defp await(predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 10_000

    case predicate.() do
      value when value not in [false, nil] ->
        value

      _ ->
        assert System.monotonic_time(:millisecond) < deadline,
               "Owned sent approval fixture deadline"

        receive do
        after
          10 -> :ok
        end

        await(predicate, deadline)
    end
  end

  defp cleanup(ctx) do
    assert :ok = Stdio.close(ctx.owner)

    if File.exists?(Path.join(ctx.root, "state.json")) do
      proof = json(ctx, "state.json")

      for owned <-
            proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
          do: await_process_exit(owned)

      assert length(events(ctx, "fixture_closed")) == 1
    end

    IO.puts(:stderr, "Owned sent approval restart evidence retained: #{ctx.root}")
  end

  defp await_process_exit(pid), do: await(fn -> not File.exists?("/proc/#{pid}") end)

  defp json(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp events(ctx, kind), do: Enum.filter(json(ctx, "bem-journal.json"), &(&1["event"] == kind))
end
