defmodule SamgitaCodexDriver.ServerInteractionsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/server_interaction_fixture.py", __DIR__)

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: CODEX_BINARY must select the immutable pinned executable"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-interactions-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: binary, root: root}
  end

  defp fixture(root, scenario) do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, scenario)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> ModelFixture.close(fixture) end)
    fixture
  end

  defp start(binary, fixture, experimental \\ true) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => _}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_server_interactions", "version" => "0.1.0"},
               %{"experimentalApi" => experimental}
             )

    pid
  end

  defp thread(pid, fixture) do
    assert {:ok, %{"result" => %{"thread" => %{"id" => id}}}} =
             Session.request(pid, "thread/start", %{
               "model" => "mock-model",
               "modelProvider" => "fixture",
               "cwd" => fixture.workspace,
               "sandbox" => "read-only",
               "approvalPolicy" => "on-request",
               "ephemeral" => true
             })

    id
  end

  defp turn(pid, thread) do
    assert {:ok, %{"result" => %{"turn" => %{"id" => id}}}} =
             Session.request(pid, "turn/start", %{
               "threadId" => thread,
               "input" => [%{"type" => "text", "text" => "Synthetic interaction only"}]
             })

    id
  end

  defp finish(pid, turn, respond, events \\ [], deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)
    Enum.each(Enum.filter(incoming, &(&1.kind == :server_request)), respond)
    events = events ++ incoming

    cond do
      Enum.any?(events, &completed?(&1, turn)) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Interaction deadline: #{inspect(Session.status(pid))}")

      Session.status(pid).phase != :ready ->
        flunk("Unexpected disconnected real Codex: #{inspect(Session.status(pid))}")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
        after
          10 -> :ok
        end

        finish(pid, turn, respond, events, deadline)
    end
  end

  defp completed?(event, turn),
    do:
      get_in(event, [:wire, "method"]) == "turn/completed" and
        get_in(event, [:wire, "params", "turn", "id"]) == turn

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))

  defp completed_item(events, type) do
    events
    |> Enum.filter(&(get_in(&1, [:wire, "method"]) == "item/completed"))
    |> Enum.map(&get_in(&1, [:wire, "params", "item"]))
    |> Enum.find(&(&1["type"] == type))
  end

  test "file approvals apply only accepted patches and preserve all four decisions", context do
    for decision <- ["decline", "cancel", "accept", "acceptForSession"] do
      fixture = fixture(Path.join(context.root, decision), "patch")
      pid = start(context.binary, fixture)
      thread = thread(pid, fixture)
      turn = turn(pid, thread)

      events =
        finish(pid, turn, fn event ->
          assert event.wire["method"] == "item/fileChange/requestApproval"
          assert event.wire["params"]["threadId"] == thread
          assert event.wire["params"]["turnId"] == turn
          assert event.wire["params"]["itemId"] == "interaction-call-1"
          refute File.exists?(Path.join(fixture.workspace, "approved.txt"))
          assert :ok = Session.respond(pid, event.handle, {:ok, %{"decision" => decision}})
        end)

      assert length(interactions(events)) == 1

      started =
        events
        |> Enum.filter(&(get_in(&1, [:wire, "method"]) == "item/started"))
        |> Enum.map(&get_in(&1, [:wire, "params", "item"]))
        |> Enum.find(&(&1["type"] == "fileChange"))

      assert hd(started["changes"])["path"] == Path.join(fixture.workspace, "approved.txt")

      assert Enum.find(events, &completed?(&1, turn)).wire["params"]["turn"]["status"] ==
               if(decision == "cancel", do: "interrupted", else: "completed")

      if decision in ["accept", "acceptForSession"] do
        assert File.read!(Path.join(fixture.workspace, "approved.txt")) == "synthetic patch\n"
        assert completed_item(events, "fileChange")["status"] == "completed"
      else
        refute File.exists?(Path.join(fixture.workspace, "approved.txt"))
      end

      Session.close(pid)
    end
  end

  test "session command approval suppresses the matching prompt in a later turn", context do
    fixture = fixture(context.root, "command_repeat")
    pid = start(context.binary, fixture)
    thread = thread(pid, fixture)
    first_turn = turn(pid, thread)

    events =
      finish(pid, first_turn, fn event ->
        assert event.wire["method"] == "item/commandExecution/requestApproval"
        assert event.wire["params"]["cwd"] == fixture.workspace

        assert String.ends_with?(
                 event.wire["params"]["command"],
                 " -c 'printf samgita_interaction'"
               )

        assert :ok =
                 Session.respond(pid, event.handle, {:ok, %{"decision" => "acceptForSession"}})
      end)

    assert length(interactions(events)) == 1
    assert completed_item(events, "commandExecution")["aggregatedOutput"] =~ "samgita_interaction"
    next_turn = turn(pid, thread)

    next_events =
      finish(pid, next_turn, fn event ->
        flunk("Matching session-approved command prompted again: #{event.wire["method"]}")
      end)

    assert completed_item(next_events, "commandExecution")["exitCode"] == 0

    assert completed_item(next_events, "commandExecution")["aggregatedOutput"] =~
             "samgita_interaction"
  end

  test "execpolicy amendment persists only the explicitly approved proposed rule", context do
    fixture = fixture(context.root, "command_repeat")
    pid = start(context.binary, fixture)
    thread = thread(pid, fixture)
    turn = turn(pid, thread)

    events =
      finish(pid, turn, fn event ->
        assert event.wire["method"] == "item/commandExecution/requestApproval"
        assert ["printf"] = event.wire["params"]["proposedExecpolicyAmendment"]

        assert :ok =
                 Session.respond(
                   pid,
                   event.handle,
                   {:ok,
                    %{
                      "decision" => %{
                        "acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => ["printf"]}
                      }
                    }}
                 )
      end)

    assert length(interactions(events)) == 1
    assert completed_item(events, "commandExecution")["exitCode"] == 0
    rules = File.read!(Path.join([fixture.codex_home, "rules", "default.rules"]))
    assert rules =~ "printf"
    assert rules =~ "allow"
  end

  test "permissions report empty, turn and session grants back into model-visible results",
       context do
    for scope <- ["empty", "turn", "session"] do
      fixture = fixture(Path.join(context.root, scope), "permissions")
      pid = start(context.binary, fixture)
      thread = thread(pid, fixture)
      turn = turn(pid, thread)

      events =
        finish(pid, turn, fn event ->
          assert event.wire["method"] == "item/permissions/requestApproval"
          params = event.wire["params"]
          assert params["threadId"] == thread
          assert params["turnId"] == turn
          assert params["permissions"]["fileSystem"]["write"] == [fixture.workspace]
          permissions = if scope == "empty", do: %{}, else: params["permissions"]

          assert :ok =
                   Session.respond(
                     pid,
                     event.handle,
                     {:ok,
                      %{
                        "permissions" => permissions,
                        "scope" => if(scope == "session", do: "session", else: "turn")
                      }}
                   )
        end)

      assert length(interactions(events)) == 1
      assert length(ModelFixture.requests(fixture)) == 2

      output =
        fixture
        |> ModelFixture.requests()
        |> List.last()
        |> Map.fetch!("input")
        |> Enum.find(&(&1["type"] == "function_call_output"))
        |> Map.fetch!("output")

      assert output =~ "permissions"
      if scope != "empty", do: assert(output =~ fixture.workspace)
      Session.close(pid)
    end
  end

  test "external currentTime requests work in stable and experimental sessions", context do
    for experimental <- [false, true] do
      fixture = fixture(Path.join(context.root, to_string(experimental)), "current_time")
      pid = start(context.binary, fixture, experimental)
      thread = thread(pid, fixture)
      turn = turn(pid, thread)

      events =
        finish(pid, turn, fn event ->
          assert event.wire["method"] == "currentTime/read"
          assert event.wire["params"]["threadId"] == thread

          assert :ok =
                   Session.respond(pid, event.handle, {:ok, %{"currentTimeAt" => 1_781_717_655}})
        end)

      assert interactions(events) != []
      [request] = ModelFixture.requests(fixture)
      assert JSON.encode!(request["input"]) =~ "2026-06-17 17:34:15 UTC"
      Session.close(pid)
    end
  end

  test "MCP form elicitation preserves accept, decline and cancel to the actual MCP peer",
       context do
    for action <- ["accept", "decline", "cancel"] do
      fixture = fixture(Path.join(context.root, action), "mcp")
      pid = start(context.binary, fixture)
      thread = thread(pid, fixture)
      turn = turn(pid, thread)

      events =
        finish(pid, turn, fn event ->
          assert event.wire["method"] == "mcpServer/elicitation/request"
          assert event.wire["params"]["serverName"] == "fixture"
          assert event.wire["params"]["mode"] == "form"
          content = if action == "accept", do: %{"confirmed" => true}, else: nil

          assert :ok =
                   Session.respond(
                     pid,
                     event.handle,
                     {:ok,
                      %{
                        "action" => action,
                        "content" => content
                      }}
                   )
        end)

      assert length(interactions(events)) == 1
      journal = fixture.codex_home |> Path.join("mcp.json") |> File.read!() |> JSON.decode!()
      assert journal["result"]["action"] == action
      assert completed_item(events, "mcpToolCall")["status"] == "completed"
      [interaction] = interactions(events)

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(pid, interaction.handle, {:ok, %{"action" => "accept"}})

      Session.close(pid)
    end
  end
end
