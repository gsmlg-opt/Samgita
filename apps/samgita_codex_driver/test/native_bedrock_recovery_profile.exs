defmodule SamgitaCodexDriver.NativeBedrockRecoveryProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_bedrock_recovery
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_bedrock_recovery_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @started "modelProvider/authRecoveryStarted"
  @completed "modelProvider/authRecoveryCompleted"
  @started_message "AWS session has expired. Reauthenticating..."
  @completed_message "Signed in with AWS."
  @text "Owned Bedrock recovery completed."

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-bedrock-recovery-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    ctx = %{binary: Path.expand(binary), root: root, scenario: tags[:scenario] || "profile"}

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert events(ctx, "native_closed") != []
        assert Enum.all?(helpers(ctx), &(not File.exists?("/proc/#{&1["pid"]}")))
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  for mode <- ~w(profile export) do
    @tag scenario: mode
    test "#{mode} native SigV4 401 refresh retry emits exact correlated recovery pair", ctx do
      pid = start(ctx)
      {thread, turn} = turn(ctx, pid)
      received = collect(pid, thread, turn)
      assert terminal(received)["status"] == "completed"
      assert terminal(received)["error"] == nil

      assert recovery(received) == [
               {@started, fields(thread, turn, @started_message)},
               {@completed, fields(thread, turn, @completed_message)}
             ]

      assert Enum.any?(received, fn event ->
               item = event.wire["params"]["item"]

               event.wire["method"] == "item/completed" and item["type"] == "agentMessage" and
                 item["text"] == @text
             end)

      assert_signed_requests(ctx, ["old", "new"])
      assert_helpers(ctx, 1, if(ctx.scenario == "export", do: 2, else: 0))
      assert refresh(ctx)["success"] == true
      assert JSON.decode!(File.read!(Path.join(ctx.root, "credential-state.json"))) == "new"

      if ctx.scenario == "export" do
        states = helpers(ctx) |> Enum.filter(&(&1["mode"] == "export")) |> Enum.map(& &1["state"])
        assert Enum.sort(states) == ["new", "old"]
      end

      assert call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"][
               "id"
             ] == thread

      finish(ctx, pid)
    end
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: System.find_executable("python3"),
             args: [
               @script,
               "--codex",
               ctx.binary,
               "--root",
               ctx.root,
               "--scenario",
               ctx.scenario
             ],
             cwd: Path.join(ctx.root, "workspace"),
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_bedrock_recovery", "version" => "1"}, %{
               "experimentalApi" => false
             })

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp turn(ctx, pid) do
    started = call(pid, "thread/start", %{"cwd" => Path.join(ctx.root, "workspace")})
    assert started["modelProvider"] == "amazon-bedrock"
    assert started["model"] == "openai.gpt-5.5"
    thread = started["thread"]["id"]

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:bedrock:recover"}]
      })["turn"]["id"]

    {thread, turn}
  end

  defp fields(thread, turn, message),
    do: %{
      "threadId" => thread,
      "turnId" => turn,
      "provider" => "Amazon Bedrock",
      "message" => message
    }

  defp recovery(received),
    do:
      for(
        event <- received,
        event.wire["method"] in [@started, @completed],
        do: {event.wire["method"], event.wire["params"]}
      )

  defp terminal(received),
    do:
      received
      |> Enum.find(&(&1.wire["method"] == "turn/completed"))
      |> Map.fetch!(:wire)
      |> get_in(["params", "turn"])

  defp collect(pid, thread, turn, received \\ [], remaining \\ 500)

  defp collect(_pid, _thread, _turn, _received, 0),
    do: flunk("Owned Bedrock recovery notification deadline")

  defp collect(pid, thread, turn, received, remaining) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current
    assert Enum.all?(current, &(&1.kind != :server_request))
    refute Enum.any?(current, &(&1.wire["method"] == "account/chatgptAuthTokens/refresh"))

    if Enum.any?(received, fn event ->
         event.wire["method"] == "turn/completed" and event.wire["params"]["threadId"] == thread and
           event.wire["params"]["turn"]["id"] == turn
       end),
       do: received,
       else:
         (
           Process.sleep(10)
           collect(pid, thread, turn, received, remaining - 1)
         )
  end

  defp assert_signed_requests(ctx, states) do
    requests = events(ctx, "signed_request")
    assert Enum.map(requests, & &1["credential_state"]) == states

    assert Enum.map(requests, & &1["status"]) ==
             Enum.map(states, &if(&1 == "old", do: 401, else: 200))

    assert Enum.all?(
             requests,
             &(&1["sigv4_verified"] and &1["semantic_payload_preserved"] and &1["host_verified"])
           )

    assert [retry] = events(ctx, "retry_payload")
    assert retry["semantic_equal"] and retry["changed_keys"] == []
  end

  defp assert_helpers(ctx, refresh_count, export_count) do
    owner = List.first(events(ctx, "native_started"))
    helpers = helpers(ctx)
    assert Enum.count(helpers, &(&1["mode"] == "refresh")) == refresh_count
    assert Enum.count(helpers, &(&1["mode"] == "export")) == export_count

    for helper <- helpers do
      assert helper["ppid"] == owner["pid"] and helper["pgid"] == owner["pgid"]
      assert helper["netns"] == owner["netns"]

      assert helper["parent_binary_verified"] and helper["fixed_arguments_verified"] and
               helper["owned_search_path_verified"] and helper["no_descendants"]

      refute File.exists?("/proc/#{helper["pid"]}")
    end
  end

  defp finish(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert {:ok, after_turn} = Session.drain(pid)
    assert recovery(after_turn) == []
    assert Enum.all?(after_turn, &(&1.kind != :server_request))
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert :ok = Session.close(pid)
    wait(fn -> events(ctx, "native_closed") != [] end)

    assert events(ctx, "native_closed") == [
             %{"event" => "native_closed", "helpers_exited" => true}
           ]

    assert events(ctx, "secret_scan") == [%{"event" => "secret_scan", "passed" => true}]
    for name <- ~w(unexpected_http fixture_error peer_closed), do: assert(events(ctx, name) == [])
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))

  defp helpers(ctx),
    do:
      for(
        path <- Path.wildcard(Path.join(ctx.root, "helpers/*.json")),
        do: path |> File.read!() |> JSON.decode!()
      )

  defp refresh(ctx), do: Enum.find(helpers(ctx), &(&1["mode"] == "refresh"))
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned Bedrock recovery observation deadline")

  defp wait(predicate, remaining) do
    if value = predicate.(),
      do: value,
      else:
        (
          Process.sleep(10)
          wait(predicate, remaining - 1)
        )
  end
end
