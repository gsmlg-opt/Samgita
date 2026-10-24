defmodule SamgitaCodexDriver.NativePermissionVariantsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3, notification: 2, notification: 3, thread: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/permission_variants_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-permission-variants-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario])
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    ctx = %{root: root, fixture: fixture, binary: binary}
    TurnFixture.configure_model(ctx, %{})
    File.mkdir!(Path.join(root, "tmp"))

    for path <- ["readable", "writable", "writable/secrets"],
        do: File.mkdir_p!(Path.join(fixture.workspace, path))

    ctx
  end

  for variant <- ~w(allow false null omitted requested_false) do
    @variant variant
    @tag scenario: "network_#{variant}"
    test "native network request with #{@variant} response has exact intersected grant", ctx do
      {pid, id, turn, approval, events} = pending(ctx)
      params = approval.wire["params"]

      assert params["permissions"] == %{
               "network" => %{"enabled" => @variant != "requested_false"},
               "fileSystem" => nil
             }

      permissions =
        case @variant do
          "false" -> %{"network" => %{"enabled" => false}}
          "null" -> %{"network" => nil}
          "omitted" -> %{}
          "allow" -> %{"network" => %{"enabled" => true}, "fileSystem" => nil}
          _ -> %{"network" => %{"enabled" => true}}
        end

      assert :ok =
               Session.respond(
                 pid,
                 approval.handle,
                 {:ok,
                  %{"permissions" => permissions, "scope" => "turn", "strictAutoReview" => nil}}
               )

      events = finish(pid, id, turn, events)
      network = if @variant == "allow", do: %{"enabled" => true}, else: nil

      assert output(ctx) == %{
               "permissions" => %{"network" => network, "file_system" => nil},
               "scope" => "turn"
             }

      assert Enum.count(events, &(&1.kind == :server_request)) == 1
      assert length(ModelFixture.requests(ctx.fixture)) == 2
      refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))
      assert_idle(ctx, pid, approval)
    end
  end

  @tag scenario: "read_only"
  test "native legacy read roots round-trip without widening to write", ctx do
    {pid, id, turn, approval, events} = pending(ctx)
    root = Path.join(ctx.fixture.workspace, "readable")

    assert approval.wire["params"]["permissions"] == %{
             "network" => nil,
             "fileSystem" => %{
               "read" => [root],
               "write" => nil,
               "entries" => [entry("read", root)]
             }
           }

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{"permissions" => %{"fileSystem" => %{"read" => [root]}}, "scope" => "turn"}}
             )

    finish(pid, id, turn, events)

    assert output(ctx) == %{
             "permissions" => %{"network" => nil, "file_system" => %{"read" => [root]}},
             "scope" => "turn"
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_idle(ctx, pid, approval)
  end

  @tag scenario: "canonical"
  test "native canonical request retains constraining path and glob deny entries during intersection",
       ctx do
    {pid, id, turn, approval, events} = pending(ctx)
    read = entry("read", Path.join(ctx.fixture.workspace, "readable"))
    write = entry("write", Path.join(ctx.fixture.workspace, "writable"))
    deny = entry("deny", Path.join(ctx.fixture.workspace, "writable/secrets"))

    glob = %{
      "path" => %{
        "type" => "glob_pattern",
        "pattern" => Path.join(ctx.fixture.workspace, "writable/**/*.blocked")
      },
      "access" => "deny"
    }

    expected = [read, write, deny, glob]

    assert approval.wire["params"]["permissions"] == %{
             "network" => nil,
             "fileSystem" => %{
               "read" => nil,
               "write" => nil,
               "entries" => expected,
               "globScanMaxDepth" => 2
             }
           }

    # Deliberately omit both requested deny entries from the granted reply.
    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok,
                %{
                  "permissions" => %{
                    "network" => nil,
                    "fileSystem" => %{"entries" => [read, write], "globScanMaxDepth" => 3}
                  },
                  "scope" => "turn"
                }}
             )

    finish(pid, id, turn, events)

    assert output(ctx) == %{
             "permissions" => %{
               "network" => nil,
               "file_system" => %{"entries" => expected, "glob_scan_max_depth" => 2}
             },
             "scope" => "turn"
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 2
    assert_idle(ctx, pid, approval)
  end

  @tag scenario: "empty_grant"
  test "empty filesystem grant supplies no authority for a later actual patch", ctx do
    {pid, id, turn, approval, events} = pending(ctx)

    assert :ok =
             Session.respond(
               pid,
               approval.handle,
               {:ok, %{"permissions" => %{}, "scope" => "turn"}}
             )

    events =
      collect(pid, events, fn all -> Enum.count(all, &(&1.kind == :server_request)) == 2 end)

    [^approval, current] = Enum.filter(events, &(&1.kind == :server_request))
    assert current.wire["method"] == "item/fileChange/requestApproval"
    target = Path.join(ctx.fixture.workspace, "must-not-exist.txt")
    refute File.exists?(target)

    assert output(ctx) == %{
             "permissions" => %{"network" => nil, "file_system" => nil},
             "scope" => "turn"
           }

    assert :ok = Session.respond(pid, current.handle, {:ok, %{"decision" => "decline"}})
    events = finish(pid, id, turn, events)
    patch = item(events, "fileChange")
    assert patch["status"] == "declined"
    assert [%{"path" => ^target}] = patch["changes"]
    refute File.exists?(target)
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_idle(ctx, pid, current)
  end

  for decision <- ~w(allow deny control) do
    @decision decision
    @tag scenario: "strict_#{decision}"
    test "turn strict auto review #{@decision} controls a real otherwise-safe command", ctx do
      {pid, id, turn, approval, events} = pending(ctx)
      strict = @decision != "control"

      assert :ok =
               Session.respond(
                 pid,
                 approval.handle,
                 {:ok,
                  %{
                    "permissions" => %{"fileSystem" => %{"write" => [ctx.fixture.workspace]}},
                    "scope" => "turn",
                    "strictAutoReview" => strict
                  }}
               )

      events = finish(pid, id, turn, events)

      expected = %{
        "permissions" => %{
          "network" => nil,
          "file_system" => %{"write" => [ctx.fixture.workspace]}
        },
        "scope" => "turn"
      }

      expected = if strict, do: Map.put(expected, "strict_auto_review", true), else: expected
      assert output(ctx) == expected
      assert Enum.count(events, &(&1.kind == :server_request)) == 1
      requests = ModelFixture.requests(ctx.fixture)

      reviewers =
        Enum.filter(
          requests,
          &(get_in(&1, ["client_metadata", "x-openai-subagent"]) == "guardian")
        )

      assert length(reviewers) == if(strict, do: 1, else: 0)
      assert length(requests) == if(strict, do: 4, else: 3)
      command = item(events, "commandExecution")

      if @decision == "deny" do
        assert command["status"] == "declined"
        assert command["aggregatedOutput"] == nil
        assert command["exitCode"] == nil
      else
        assert command["status"] == "completed"
        assert command["aggregatedOutput"] == "samgita_strict_turn"
        assert command["exitCode"] == 0
      end

      started = notification(events, "item/autoApprovalReview/started")
      completed = notification(events, "item/autoApprovalReview/completed")

      if strict do
        assert started["threadId"] == id and completed["threadId"] == id
        assert started["turnId"] == turn and completed["turnId"] == turn
        assert started["targetItemId"] == "permission-variant-command"
        assert completed["targetItemId"] == started["targetItemId"]
        assert is_binary(started["reviewId"]) and started["reviewId"] != ""
        assert completed["reviewId"] == started["reviewId"]
        assert started["review"]["status"] == "inProgress"

        assert completed["review"]["status"] ==
                 if(@decision == "allow", do: "approved", else: "denied")

        assert is_integer(started["startedAtMs"]) and started["startedAtMs"] > 0
        assert completed["completedAtMs"] >= started["startedAtMs"]
      else
        assert started == nil and completed == nil
      end

      assert_idle(ctx, pid, approval)
    end
  end

  defp pending(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: ctx.fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => ctx.fixture.home,
               "CODEX_HOME" => ctx.fixture.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => ctx.fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "permission_variants", "version" => "1"}, %{
               "experimentalApi" => true
             })

    id = thread(ctx, pid)

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned permission variants only"}
      ])

    events = collect(pid, [], &Enum.any?(&1, fn e -> e.kind == :server_request end))
    assert [approval] = Enum.filter(events, &(&1.kind == :server_request))
    assert approval.wire["method"] == "item/permissions/requestApproval"
    p = approval.wire["params"]
    assert p["threadId"] == id and p["turnId"] == turn
    assert p["itemId"] == "permission-variant-1" and p["environmentId"] == "local"
    assert p["reason"] == "Owned permission variant only" and p["cwd"] == ctx.fixture.workspace
    assert is_integer(p["startedAtMs"]) and p["startedAtMs"] > 0
    assert length(ModelFixture.requests(ctx.fixture)) == 1
    {pid, id, turn, approval, events}
  end

  defp output(ctx) do
    outputs =
      for request <- ModelFixture.requests(ctx.fixture),
          request["client_metadata"]["x-openai-subagent"] != "guardian",
          item <- request["input"],
          item["type"] == "function_call_output",
          item["call_id"] == "permission-variant-1",
          do: JSON.decode!(item["output"])

    assert outputs != []
    [value] = Enum.uniq(outputs)
    value
  end

  defp finish(pid, id, turn, events) do
    events =
      collect(pid, events, fn all ->
        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) != nil
      end)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert [%{"id" => ^turn, "status" => "completed"}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    events
  end

  defp item(events, kind),
    do: notification(events, "item/completed", &(&1["item"]["type"] == kind))["item"]

  defp entry(access, path),
    do: %{"path" => %{"type" => "path", "path" => path}, "access" => access}

  defp assert_idle(ctx, pid, approval) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []

    assert {:error, %Error{code: :stale_interaction}} =
             Session.respond(pid, approval.handle, {:ok, %{}})

    refute File.exists?(Path.join(ctx.fixture.codex_home, "rules/default.rules"))
    assert File.ls!(Path.join(ctx.fixture.workspace, "readable")) == []
    assert File.ls!(Path.join(ctx.fixture.workspace, "writable")) == ["secrets"]
    assert File.ls!(Path.join(ctx.fixture.workspace, "writable/secrets")) == []
  end

  defp collect(pid, events, predicate),
    do: collect(pid, events, predicate, System.monotonic_time(:millisecond) + 20_000)

  defp collect(pid, events, predicate, deadline) do
    assert {:ok, new} = Session.drain(pid)
    events = events ++ new

    cond do
      predicate.(events) ->
        events

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Native permission variant deadline")

      true ->
        receive do
        after
          5 -> collect(pid, events, predicate, deadline)
        end
    end
  end
end
