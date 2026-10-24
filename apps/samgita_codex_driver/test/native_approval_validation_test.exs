defmodule SamgitaCodexDriver.NativeApprovalValidationTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, TurnFixture}
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 3, start: 1, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @scripts Path.expand("../../../scripts/codex", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @binary_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-approval-validation-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    script = tags[:provider_script] || "server_interaction_fixture.py"
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", Path.join(@scripts, script))

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    %{binary: binary, fixture: fixture, root: root}
  end

  for decision <- ~w(accept decline) do
    @decision decision
    @tag scenario: "command_repeat"
    test "invalid command replies preserve the handle until explicit #{@decision}", ctx do
      {pid, id, turn, approval, events} = pending(ctx, "commandExecution", "interaction-call-1")
      params = approval.wire["params"]
      assert params["kind"] == "command"
      assert params["cwd"] == ctx.fixture.workspace
      assert params["proposedExecpolicyAmendment"] == ["printf"]

      assert [shell, "-c", "printf samgita_interaction"] =
               OptionParser.split(params["command"])

      assert Path.type(shell) == :absolute and File.regular?(shell)
      events = reject_invalid(ctx, pid, turn, approval, events, invalid_command_results())
      response = {:ok, %{"decision" => @decision}}
      assert :ok = Session.respond(pid, approval.handle, response)
      assert_stale(pid, approval, response)
      events = finish(pid, id, turn, events, 1)
      command = item(events, "commandExecution")
      assert command["id"] == params["itemId"]

      if @decision == "accept" do
        assert %{
                 "status" => "completed",
                 "exitCode" => 0,
                 "aggregatedOutput" => "samgita_interaction"
               } = command
      else
        assert %{"status" => "declined", "exitCode" => nil, "aggregatedOutput" => nil} =
                 command
      end

      assert File.ls!(ctx.fixture.workspace) == []
      assert_finished(ctx, pid, id, turn, approval, response, 2)
    end

    @tag scenario: "patch"
    test "invalid file replies preserve the handle until explicit #{@decision}", ctx do
      {pid, id, turn, approval, events} = pending(ctx, "fileChange", "interaction-call-1")
      path = Path.join(ctx.fixture.workspace, "approved.txt")
      assert [%{"path" => ^path}] = item(events, "fileChange", "item/started")["changes"]
      refute File.exists?(path)
      events = reject_invalid(ctx, pid, turn, approval, events, invalid_file_results())
      response = {:ok, %{"decision" => @decision}}
      assert :ok = Session.respond(pid, approval.handle, response)
      assert_stale(pid, approval, response)
      events = finish(pid, id, turn, events, 1)
      file = item(events, "fileChange")
      assert file["id"] == approval.wire["params"]["itemId"]

      if @decision == "accept" do
        assert file["status"] == "completed"
        assert File.read!(path) == "synthetic patch\n"
        assert File.ls!(ctx.fixture.workspace) == ["approved.txt"]
      else
        assert file["status"] == "declined"
        assert File.ls!(ctx.fixture.workspace) == []
      end

      assert_finished(ctx, pid, id, turn, approval, response, 2)
    end
  end

  for disposition <- ~w(grant deny) do
    @disposition disposition
    @tag scenario: "permission_lifetime", provider_script: "permission_lifetime_fixture.py"
    test "invalid permission replies preserve the handle until explicit #{@disposition}", ctx do
      {pid, id, turn, approval, events} = pending(ctx, "permissions", "permission-lifetime-1")
      params = approval.wire["params"]
      assert params["environmentId"] == "local" and params["cwd"] == ctx.fixture.workspace
      assert params["reason"] == "Synthetic owned workspace permission lifetime only"
      assert params["permissions"]["fileSystem"]["write"] == [ctx.fixture.workspace]
      events = reject_invalid(ctx, pid, turn, approval, events, invalid_permission_results())

      permissions =
        if @disposition == "grant",
          do: %{"fileSystem" => %{"write" => [ctx.fixture.workspace]}},
          else: %{}

      response =
        {:ok, %{"permissions" => permissions, "scope" => "turn", "strictAutoReview" => false}}

      assert :ok = Session.respond(pid, approval.handle, response)
      assert_stale(pid, approval, response)
      path = Path.join(ctx.fixture.workspace, "granted-now.txt")

      events =
        if @disposition == "grant" do
          events = finish(pid, id, turn, events, 1)
          assert item(events, "fileChange")["status"] == "completed"
          assert File.read!(path) == "owned turn grant\n"
          assert File.ls!(ctx.fixture.workspace) == ["granted-now.txt"]
          events
        else
          events = collect(pid, events, &(length(interactions(&1)) == 2), true)
          assert [^approval, patch] = interactions(events)
          assert patch.wire["method"] == "item/fileChange/requestApproval"
          assert patch.wire["params"]["threadId"] == id
          assert patch.wire["params"]["turnId"] == turn
          assert patch.wire["params"]["itemId"] == "permission-lifetime-2"
          assert [%{"path" => ^path}] = item(events, "fileChange", "item/started")["changes"]
          assert length(ModelFixture.requests(ctx.fixture)) == 2
          refute File.exists?(path)
          decline = {:ok, %{"decision" => "decline"}}
          assert :ok = Session.respond(pid, patch.handle, decline)
          assert_stale(pid, patch, decline)
          events = finish(pid, id, turn, events, 2)
          assert item(events, "fileChange")["status"] == "declined"
          assert File.ls!(ctx.fixture.workspace) == []
          events
        end

      assert permission_output(ctx) == %{
               "permissions" => %{
                 "network" => nil,
                 "file_system" =>
                   if(@disposition == "grant",
                     do: %{"write" => [ctx.fixture.workspace]},
                     else: nil
                   )
               },
               "scope" => "turn"
             }

      refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))
      assert_finished(ctx, pid, id, turn, approval, response, 3)
    end
  end

  defp pending(ctx, kind, item_id) do
    # The shared starter registers the owned stdio process guardian before initialization.
    pid = start(ctx)
    id = thread(ctx, pid)

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned invalid approval validation only"}
      ])

    events = collect(pid, [], &(interactions(&1) != []), true)
    assert [approval] = interactions(events)
    assert approval.wire["method"] == "item/#{kind}/requestApproval"
    assert approval.wire["params"]["threadId"] == id
    assert approval.wire["params"]["turnId"] == turn
    assert approval.wire["params"]["itemId"] == item_id
    assert is_integer(approval.wire["params"]["startedAtMs"])
    assert approval.wire["params"]["startedAtMs"] > 0
    assert approval.handle.id == approval.wire["id"]
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    {pid, id, turn, approval, events}
  end

  defp reject_invalid(ctx, pid, turn, approval, events, invalid_results) do
    %{generation: generation} = Session.status(pid)
    assert approval.handle.generation == generation
    original = Map.fetch!(:sys.get_state(pid).interactions, approval.handle.id)
    assert original.handle == approval.handle
    assert is_integer(Process.read_timer(original.timer))

    replies = [
      {:not_a_response, :invalid_response}
      | Enum.map(invalid_results, &{{:ok, &1}, :schema_violation})
    ]

    Enum.reduce(replies, events, fn {reply, code}, events ->
      assert {:error, %Error{code: ^code, uncertain: false, wire: nil}} =
               Session.respond(pid, approval.handle, reply)

      assert %{
               phase: :ready,
               generation: ^generation,
               pending: 0,
               interactions: 1,
               interaction_outcomes: 0,
               uncertain: 0,
               gap: nil
             } = Session.status(pid)

      # Includes the opaque handle, native IDs, timer and token: rejection must not
      # replace the handle or extend the original approval deadline.
      assert ^original = Map.fetch!(:sys.get_state(pid).interactions, approval.handle.id)
      assert Session.interaction_outcomes(pid) == []
      assert Session.uncertain_operations(pid) == []
      assert length(ModelFixture.requests(ctx.fixture)) == 1
      assert File.ls!(ctx.fixture.workspace) == []
      refute File.exists?(rules(ctx))
      assert {:ok, incoming} = Session.drain(pid)
      refute Enum.any?(incoming, &(&1.kind == :server_request))
      events = events ++ incoming
      refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

      refute notification(
               events,
               "item/completed",
               &(&1["item"]["type"] in ["fileChange", "commandExecution"])
             )

      events
    end)
  end

  defp invalid_command_results do
    [
      nil,
      %{},
      %{"decision" => nil},
      %{"decision" => "timed_out"},
      %{
        "decision" => %{"acceptWithExecpolicyAmendment" => %{"execpolicyAmendment" => ["printf"]}}
      },
      %{"decision" => %{"acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => [true]}}},
      %{
        "decision" => %{
          "applyNetworkPolicyAmendment" => %{
            "network_policy_amendment" => %{"host" => "owned.invalid", "action" => "accept"}
          }
        }
      }
    ]
  end

  defp invalid_file_results do
    [
      nil,
      %{},
      %{"decision" => nil},
      %{"decision" => "approved"},
      %{"decision" => []},
      %{
        "decision" => %{
          "acceptWithExecpolicyAmendment" => %{"execpolicy_amendment" => ["printf"]}
        }
      }
    ]
  end

  defp invalid_permission_results do
    [
      nil,
      %{},
      %{"permissions" => nil},
      %{"permissions" => %{}, "scope" => nil},
      %{"permissions" => %{}, "scope" => "forever"},
      %{"permissions" => %{}, "strictAutoReview" => "false"},
      %{"permissions" => %{"network" => %{"enabled" => "true"}}},
      %{"permissions" => %{"fileSystem" => %{"write" => [42]}}},
      %{"permissions" => %{"fileSystem" => %{"globScanMaxDepth" => 0}}},
      %{
        "permissions" => %{
          "fileSystem" => %{
            "entries" => [%{"access" => "write", "path" => %{"path" => "/tmp/owned-unexecuted"}}]
          }
        }
      }
    ]
  end

  defp finish(pid, id, turn, events, request_count) do
    events =
      collect(
        pid,
        events,
        &notification(&1, "turn/completed", fn p -> p["turn"]["id"] == turn end),
        false
      )

    assert length(interactions(events)) == request_count

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    events
  end

  defp collect(pid, events, predicate, allow_request, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)

    unless allow_request do
      refute Enum.any?(incoming, &(&1.kind == :server_request)),
             "Unexpected native request; never automatically answer unrelated interactions"
    end

    events = events ++ incoming

    if predicate.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, predicate, allow_request, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during native invalid approval validation")
      after
        remaining -> flunk("Native invalid approval deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp assert_finished(ctx, pid, id, turn, approval, response, provider_count) do
    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert length(ModelFixture.requests(ctx.fixture)) == provider_count
    assert_stale(pid, approval, response)
    refute File.exists?(rules(ctx))
  end

  defp assert_stale(pid, approval, response) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, approval.handle, response)
  end

  defp permission_output(ctx) do
    assert [_first, second, _third] = ModelFixture.requests(ctx.fixture)
    assert [output] = Enum.filter(second["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "permission-lifetime-1"
    JSON.decode!(output["output"])
  end

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))

  defp item(events, kind, method \\ "item/completed") do
    assert %{"item" => item} = notification(events, method, &(&1["item"]["type"] == kind))
    item
  end

  defp rules(ctx), do: Path.join([ctx.fixture.codex_home, "rules", "default.rules"])
end
