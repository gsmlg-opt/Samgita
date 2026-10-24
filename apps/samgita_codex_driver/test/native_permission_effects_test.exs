defmodule SamgitaCodexDriver.NativePermissionEffectsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  import TurnFixture, only: [call: 3, thread: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/permission_effects_fixture.py", __DIR__)
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
        "samgita-permission-effects-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, "denied_directory")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    # Owned native guardians close before the provider and disposable root.
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    writable = Path.join(fixture.workspace, "writable")
    secrets = Path.join(writable, "secrets")
    File.mkdir_p!(secrets)
    public = Path.join(writable, "public.txt")
    private = Path.join(secrets, "private.txt")
    File.write!(public, "owned public before\n")
    File.write!(private, "owned private before\n")

    ctx = %{
      binary: binary,
      root: root,
      fixture: fixture,
      writable: writable,
      secrets: secrets,
      public: public,
      private: private
    }

    TurnFixture.configure_model(ctx, %{})
    ctx
  end

  test "retained denied directory requires approval for its child despite a positive write root",
       ctx do
    pid = start(ctx)
    id = thread(ctx, pid, %{})
    assert ModelFixture.requests(ctx.fixture) == []
    assert_files(ctx, "owned public before\n")

    turn =
      TurnFixture.start_turn(pid, id, [
        %{"type" => "text", "text" => "Owned permission effects with a denied directory only"}
      ])

    events = collect(pid, [], &(interactions(&1) != []))
    assert [grant] = interactions(events)

    assert_request(
      pid,
      grant,
      id,
      turn,
      "item/permissions/requestApproval",
      "permission-effects-grant"
    )

    write = entry("write", ctx.writable)
    deny = entry("deny", ctx.secrets)

    assert grant.wire["params"]["environmentId"] == "local"
    assert grant.wire["params"]["cwd"] == ctx.fixture.workspace
    assert grant.wire["params"]["reason"] == "Owned canonical denied-directory patch only"

    assert grant.wire["params"]["permissions"] == %{
             "network" => nil,
             "fileSystem" => %{"read" => nil, "write" => nil, "entries" => [write, deny]}
           }

    assert length(ModelFixture.requests(ctx.fixture)) == 1
    assert_files(ctx, "owned public before\n")

    # Deliberately omit the requested deny: native intersection must retain it.
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
        assert length(interactions(all)) <= 2, "Unexpected additional native interaction"
        length(interactions(all)) == 2
      end)

    assert [^grant, denied] = interactions(events)

    assert_request(
      pid,
      denied,
      id,
      turn,
      "item/fileChange/requestApproval",
      "permission-effects-private"
    )

    params = denied.wire["params"]
    assert Enum.sort(Map.keys(params)) == ~w(grantRoot itemId reason startedAtMs threadId turnId)
    assert Map.fetch(params, "reason") == {:ok, nil}
    assert Map.fetch(params, "grantRoot") == {:ok, nil}

    public_item =
      expected_item(
        ctx.public,
        "permission-effects-public",
        "completed",
        "@@ -1 +1 @@\n-owned public before\n+owned public after\n"
      )

    private_started =
      expected_item(
        ctx.private,
        "permission-effects-private",
        "inProgress",
        "@@ -1 +1 @@\n-owned private before\n+owned private after\n"
      )

    assert_item(events, id, turn, "item/completed", public_item)
    assert_item(events, id, turn, "item/started", private_started)

    refute notification(
             events,
             "item/completed",
             &(&1["item"]["id"] == "permission-effects-private")
           )

    refute notification(events, "turn/completed", &(&1["turn"]["id"] == turn))
    assert_files(ctx, "owned public after\n")
    assert %{phase: :ready, pending: 0, interactions: 1, uncertain: 0} = Session.status(pid)

    assert [first, second, third] = ModelFixture.requests(ctx.fixture)
    normalized = second |> tool_output("permission-effects-grant") |> JSON.decode!()

    assert normalized == %{
             "permissions" => %{"network" => nil, "file_system" => %{"entries" => [write, deny]}},
             "scope" => "turn"
           }

    assert tool_output(third, "permission-effects-public") =~
             "Success. Updated the following files:"

    assert tool_output(third, "permission-effects-public") =~ "writable/public.txt"
    assert Enum.all?([first, second, third], &(&1["model"] == "mock-model"))
    assert_stale(pid, grant, %{"permissions" => %{}})

    assert :ok = Session.respond(pid, denied.handle, {:ok, %{"decision" => "decline"}})
    request_id = denied.wire["id"]

    events =
      collect(pid, events, fn all ->
        assert interactions(all) == [grant, denied],
               "Unexpected new native interaction after explicit decline"

        notification(all, "turn/completed", &(&1["turn"]["id"] == turn)) &&
          notification(all, "serverRequest/resolved", &(&1["requestId"] == request_id))
      end)

    assert %{"threadId" => ^id, "turn" => %{"id" => ^turn, "status" => "completed"}} =
             notification(events, "turn/completed", &(&1["turn"]["id"] == turn))

    private_item = Map.put(private_started, "status", "declined")
    assert_item(events, id, turn, "item/completed", private_item)
    assert_files(ctx, "owned public after\n")
    assert [^first, ^second, ^third, final] = ModelFixture.requests(ctx.fixture)
    assert tool_output(final, "permission-effects-private") =~ "patch rejected by user"
    assert final["model"] == "mock-model"
    refute Enum.any?(events, &(&1.wire["method"] == "item/autoApprovalReview/started"))

    for interaction <- [grant, denied] do
      request_id = interaction.wire["id"]

      assert %{"threadId" => ^id, "requestId" => ^request_id} =
               notification(events, "serverRequest/resolved", &(&1["requestId"] == request_id))

      assert [outcome] =
               Enum.filter(Session.interaction_outcomes(pid), &(&1.handle == interaction.handle))

      assert outcome.status == :resolution_observed
    end

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
    assert_stale(pid, denied, %{"decision" => "accept"})
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

  defp entry(access, path),
    do: %{"path" => %{"type" => "path", "path" => path}, "access" => access}

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
    assert Enum.sort(File.ls!(ctx.writable)) == ["public.txt", "secrets"]
    assert File.ls!(ctx.secrets) == ["private.txt"]
  end

  defp assert_request(pid, request, id, turn, method, item_id) do
    assert request.wire["method"] == method
    assert request.wire["params"]["threadId"] == id
    assert request.wire["params"]["turnId"] == turn
    assert request.wire["params"]["itemId"] == item_id
    assert is_integer(request.wire["params"]["startedAtMs"])
    assert request.handle.id == request.wire["id"]
    assert request.handle.generation == Session.status(pid).generation
    assert is_reference(request.handle.reference)
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

  defp assert_stale(pid, request, reply) do
    assert {:error, %Error{code: :stale_interaction, uncertain: false}} =
             Session.respond(pid, request.handle, {:ok, reply})
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
          flunk("Unexpected event gap during permission effects")
      after
        remaining -> flunk("Native permission effects deadline: #{inspect(Session.status(pid))}")
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
               %{"name" => "samgita_permission_effects", "version" => "0.1.0"},
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
