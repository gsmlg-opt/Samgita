defmodule SamgitaCodexDriver.NativePermissionGlobEffectsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  import TurnFixture, only: [call: 3, thread: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/permission_glob_effects_fixture.py", __DIR__)
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-permission-glob-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "denied_glob")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Owned native guardians close before the provider and disposable root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    writable = Path.join(fixture.workspace, "writable")
    File.mkdir!(writable)
    public = Path.join(writable, "public.txt")
    private = Path.join(writable, "private.secret")
    File.write!(public, "owned public before\n")
    File.write!(private, "owned private before\n")

    ctx = %{
      binary: binary,
      root: root,
      fixture: fixture,
      writable: writable,
      public: public,
      private: private
    }

    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "retained deny glob preserves the private file when native retry is declined", ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{})
    assert ModelFixture.requests(ctx.fixture) == []
    assert_files(ctx, "owned public before\n")

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned retained deny-glob effects only"}
      ])

    events = collect(pid, [], &(interactions(&1) != []))
    assert [grant] = interactions(events)
    assert grant.wire["method"] == "item/permissions/requestApproval"
    # Pinned Codex allocates server request IDs from AtomicI64 initialized at zero.
    assert is_integer(grant.wire["id"]) and grant.wire["id"] >= 0
    params = grant.wire["params"]
    assert params["threadId"] == id
    assert params["turnId"] == turn
    assert params["itemId"] == "permission-glob-grant"
    assert params["environmentId"] == "local"
    assert params["cwd"] == ctx.fixture.workspace
    assert params["reason"] == "Owned sibling and deny-glob patch effects only"
    assert is_integer(params["startedAtMs"])
    assert grant.handle.id == grant.wire["id"]
    assert grant.handle.generation == Session.status(pid).generation
    assert is_reference(grant.handle.reference)

    write = %{"path" => %{"type" => "path", "path" => ctx.writable}, "access" => "write"}

    deny = %{
      "path" => %{"type" => "glob_pattern", "pattern" => Path.join(ctx.writable, "*.secret")},
      "access" => "deny"
    }

    assert params["permissions"] == %{
             "network" => nil,
             "fileSystem" => %{"read" => nil, "write" => nil, "entries" => [write, deny]}
           }

    assert {:ok, started_at_ms} = Map.fetch(params, "startedAtMs")
    assert is_integer(started_at_ms) and started_at_ms > 0

    assert Map.delete(params, "startedAtMs") === %{
             "threadId" => id,
             "turnId" => turn,
             "itemId" => "permission-glob-grant",
             "environmentId" => "local",
             "cwd" => ctx.fixture.workspace,
             "reason" => "Owned sibling and deny-glob patch effects only",
             "permissions" => %{
               "network" => nil,
               "fileSystem" => %{"read" => nil, "write" => nil, "entries" => [write, deny]}
             }
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_files(ctx, "owned public before\n")

    # Deliberately omit the requested glob: native intersection must retain it.
    assert :ok =
             Session.respond(
               pid,
               grant.handle,
               {:ok,
                %{
                  "permissions" => %{"fileSystem" => %{"entries" => [write]}},
                  "scope" => "turn",
                  "strictAutoReview" => false
                }}
             )

    events =
      collect(pid, events, fn all ->
        assert length(interactions(all)) <= 2, "Unexpected extra approval request"
        length(interactions(all)) == 2
      end)

    assert [^grant, retry] = interactions(events)
    assert retry.wire["method"] == "item/fileChange/requestApproval"
    retry_params = retry.wire["params"]

    assert Enum.sort(Map.keys(retry_params)) ==
             ~w(grantRoot itemId reason startedAtMs threadId turnId)

    assert retry_params["threadId"] == id
    assert retry_params["turnId"] == turn
    assert retry_params["itemId"] == "permission-glob-private"
    assert Map.fetch(retry_params, "reason") == {:ok, "command failed; retry without sandbox?"}
    assert Map.fetch(retry_params, "grantRoot") == {:ok, nil}
    assert is_integer(retry_params["startedAtMs"]) and retry_params["startedAtMs"] > 0
    refute retry.wire["id"] == grant.wire["id"]
    assert retry.handle.id == retry.wire["id"]
    assert retry.handle.generation == Session.status(pid).generation
    assert is_reference(retry.handle.reference)
    assert length(ModelFixture.requests(ctx.fixture)) == 3
    assert_files(ctx, "owned public after\n")

    assert_item(
      events,
      id,
      turn,
      "item/completed",
      expected_item(
        ctx.public,
        "permission-glob-public",
        "completed",
        "@@ -1 +1 @@\n-owned public before\n+owned public after\n"
      )
    )

    assert_item(
      events,
      id,
      turn,
      "item/started",
      expected_item(
        ctx.private,
        "permission-glob-private",
        "inProgress",
        "@@ -1 +1 @@\n-owned private before\n+owned private after\n"
      )
    )

    refute notification(
             events,
             "item/completed",
             &(&1["item"]["id"] == "permission-glob-private")
           )

    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0, gap: nil} =
             Session.status(pid)

    # Never grant a retry without the sandbox enforcing the retained deny glob.
    assert :ok = Session.respond(pid, retry.handle, {:ok, %{"decision" => "decline"}})
    request_ids = [grant.wire["id"], retry.wire["id"]]

    events =
      collect(pid, events, fn all ->
        assert interactions(all) == [grant, retry], "Unexpected extra approval request"

        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
          Enum.all?(request_ids, fn request_id ->
            notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
          end)
      end)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    public_item =
      expected_item(
        ctx.public,
        "permission-glob-public",
        "completed",
        "@@ -1 +1 @@\n-owned public before\n+owned public after\n"
      )

    private_item =
      expected_item(
        ctx.private,
        "permission-glob-private",
        "declined",
        "@@ -1 +1 @@\n-owned private before\n+owned private after\n"
      )

    assert_item(events, id, turn, "item/started", Map.put(public_item, "status", "inProgress"))
    assert_item(events, id, turn, "item/completed", public_item)
    assert_item(events, id, turn, "item/started", Map.put(private_item, "status", "inProgress"))
    assert_item(events, id, turn, "item/completed", private_item)
    assert_files(ctx, "owned public after\n")

    assert [first, second, third, final] = ModelFixture.requests(ctx.fixture)
    assert Enum.all?([first, second, third, final], &(&1["model"] == "mock-model"))

    assert second |> tool_output("permission-glob-grant") |> JSON.decode!() == %{
             "permissions" => %{"network" => nil, "file_system" => %{"entries" => [write, deny]}},
             "scope" => "turn"
           }

    public_output = tool_output(third, "permission-glob-public")

    assert ["Wall time: 0.0000 seconds", "Output:", "Exit code: 0", wall_time, "Output:", summary] =
             String.split(public_output, "\n", parts: 6)

    assert wall_time =~ ~r/^Wall time: \d+(?:\.\d+)? seconds$/
    assert summary == "Success. Updated the following files:\nM writable/public.txt\n"
    assert tool_output(final, "permission-glob-private") == "patch rejected by user"

    refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))

    for request_id <- request_ids do
      assert %{"threadId" => ^id, "requestId" => ^request_id} =
               notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))
    end

    outcomes = Session.interaction_outcomes(pid)
    assert length(outcomes) == 2

    assert Map.new(outcomes, &{&1.handle, &1.status}) == %{
             grant.handle => :resolution_observed,
             retry.handle => :resolution_observed
           }

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []

    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, grant.handle, {:ok, %{"permissions" => %{}}})

    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, retry.handle, {:ok, %{"decision" => "decline"}})

    refute File.exists?(Path.join([ctx.fixture.codex_home, "rules", "default.rules"]))

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert Enum.filter(items, &(&1["type"] == "fileChange")) == [public_item, private_item]
    assert ModelFixture.requests(ctx.fixture) == [first, second, third, final]
    assert_files(ctx, "owned public after\n")
    close_owned(pid)
    assert_files(ctx, "owned public after\n")
  end

  defp expected_item(path, id, status, diff),
    do: %{
      "id" => id,
      "type" => "fileChange",
      "status" => status,
      "changes" => [
        %{"path" => path, "kind" => %{"type" => "update", "move_path" => nil}, "diff" => diff}
      ]
    }

  defp assert_files(ctx, public_bytes) do
    assert File.lstat!(ctx.public).type == :regular
    assert File.lstat!(ctx.private).type == :regular
    assert File.read!(ctx.public) == public_bytes
    assert File.read!(ctx.private) == "owned private before\n"
    assert File.ls!(ctx.fixture.workspace) == ["writable"]
    assert Enum.sort(File.ls!(ctx.writable)) == ["private.secret", "public.txt"]
  end

  defp assert_item(events, id, turn, method, expected) do
    assert %{"threadId" => ^id, "turnId" => ^turn, "item" => item} =
             notification(events, method, &(&1["item"]["id"] == expected["id"]))

    assert item == expected
  end

  defp tool_output(request, call_id) do
    assert [output] =
             Enum.filter(
               request["input"],
               &(&1["type"] == "function_call_output" and &1["call_id"] == call_id)
             )

    output["output"]
  end

  defp collect(pid, events, done, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 15_000
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    if done.(events) do
      events
    else
      assert %{phase: :ready} = Session.status(pid)
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:codex_driver, ^pid, :events_available} ->
          collect(pid, events, done, deadline)

        {:codex_driver, ^pid, {:gap, _}} ->
          flunk("Unexpected event gap during deny-glob effects")
      after
        remaining -> flunk("Native deny-glob deadline: #{inspect(Session.status(pid))}")
      end
    end
  end

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_permission_glob_effects", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp close_owned(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert Port.info(connection.port) == nil
    assert :atomics.get(connection.owner.completion, 1) == 1
  end

  defp interactions(events), do: Enum.filter(events, &(&1.kind == :server_request))
end
