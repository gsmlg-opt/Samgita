defmodule SamgitaCodexDriver.NativeGuardianProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag :isolated_guardian
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/isolated_guardian_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @started "item/autoApprovalReview/started"
  @completed "item/autoApprovalReview/completed"
  @strict "autoApprovalReview/strictReviewRequired"
  @call "owned-guardian-action"
  @rationale "Owned synthetic action is not authorized."

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-guardian-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    for directory <- ~w(home codex workspace tmp), do: File.mkdir!(Path.join(root, directory))
    ctx = %{binary: Path.expand(binary), root: root, scenario: tags[:scenario] || "deny"}

    on_exit(fn ->
      if File.exists?(Path.join(root, "journal.json")) do
        for started <- events(ctx, "native_started"),
            key <- ~w(pid controller_pid namespace_owner_pid),
            do: wait(fn -> not File.exists?("/proc/#{started[key]}") end)

        assert events(ctx, "native_closed") != []
      end

      File.rm_rf!(root)
    end)

    ctx
  end

  test "denied native review warns and explicit approval supplies context without executing",
       ctx do
    pid = start(ctx, false)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &done?(&1, thread, turn))
    {_started, denied} = assert_review(received, thread, turn, "denied")

    assert denied["review"] == %{
             "status" => "denied",
             "riskLevel" => "high",
             "userAuthorization" => "unknown",
             "rationale" => @rationale
           }

    assert denied["decisionSource"] == "agent"

    assert notice(received, "guardianWarning")["message"] ==
             "Automatic approval review denied (risk: high, authorization: unknown): #{@rationale}"

    assert notice(received, @strict) == nil
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 2
    assert events(ctx, "forbidden_mcp") == []

    assert call(pid, "thread/approveGuardianDeniedAction", %{
             "threadId" => thread,
             "event" => denial_event(denied)
           }) == %{}

    assert call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"][
             "id"
           ] == thread

    assert length(provider(ctx)) == 3
    assert {:ok, after_approval} = Session.drain(pid)
    refute Enum.any?(after_approval, &(&1.wire["method"] == "turn/started"))

    next_turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:guardian:observe-approval"}]
      })["turn"]["id"]

    followup = collect(pid, &done?(&1, thread, next_turn))
    assert events(ctx, "approved_context_observed") != []
    assert length(provider(ctx)) == 4
    assert notice(followup, @started) == nil
    assert_no_interactions(followup)
    finish(ctx, pid)
  end

  @tag scenario: "cancel"
  test "interrupting a held native reviewer aborts review without approving the MCP action",
       ctx do
    pid = start(ctx, false)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &(notice(&1, @started) != nil))
    wait(fn -> Enum.any?(provider(ctx), &(&1["reviewer"] == true)) end)
    assert call(pid, "turn/interrupt", %{"threadId" => thread, "turnId" => turn}) == %{}

    received =
      collect(pid, &(done?(&1, thread, turn, "interrupted") and notice(&1, @completed)), received)

    assert_review(received, thread, turn, "aborted")
    assert notice(received, "guardianWarning") == nil
    assert notice(received, @strict) == nil
    wait(fn -> events(ctx, "reviewer_transport_closed") != [] end)
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert events(ctx, "forbidden_mcp") == []
    finish(ctx, pid)
  end

  @tag scenario: "strict-overflow"
  test "bounded asynchronous action overflow emits native strict-review fallback and denied result",
       ctx do
    pid = start(ctx, true)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &done?(&1, thread, turn))
    {started, denied} = assert_review(received, thread, turn, "denied")

    assert notice(received, @strict) == %{
             "threadId" => thread,
             "turnId" => turn,
             "startedAtMs" => started["startedAtMs"]
           }

    assert Enum.count(received, &(&1.wire["method"] == @strict)) == 1
    assert denied["review"]["rationale"] == @rationale
    assert notice(received, "guardianWarning")["threadId"] == thread
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 2
    assert events(ctx, "forbidden_mcp") == []
    finish(ctx, pid)
  end

  @tag scenario: "allow"
  test "native allow review dispatches one fixed MCP action after release and preserves its result",
       ctx do
    pid = start(ctx, false)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &(notice(&1, @started) != nil))
    wait(fn -> events(ctx, "allow_reviewer_held") != [] end)
    assert events(ctx, "mcp_action_dispatched") == []
    assert events(ctx, "allow_parent_continuation") == []
    assert notice(received, @completed) == nil
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 1

    File.write!(Path.join(ctx.root, "allow-review.release"), "allow\n")
    received = collect(pid, &done?(&1, thread, turn), received)
    {_started, approved} = assert_review(received, thread, turn, "approved")

    assert approved["review"] == %{
             "status" => "approved",
             "riskLevel" => "low",
             "userAuthorization" => "high",
             "rationale" => "Owned fixed in-memory action is authorized."
           }

    assert approved["decisionSource"] == "agent"

    assert notice(received, "guardianWarning")["message"] ==
             "Automatic approval review approved (risk: low, authorization: high): " <>
               "Owned fixed in-memory action is authorized."

    assert notice(received, @strict) == nil

    assert [
             %{
               "tool" => "denied_action",
               "arguments" => %{"message" => "owned harmless allow payload"},
               "result_text" => "owned harmless allow result"
             }
           ] = events(ctx, "mcp_action_dispatched")

    assert [
             %{
               "call_id" => @call,
               "content" => %{"type" => "input_text", "text" => "owned harmless allow result"}
             }
           ] =
             events(ctx, "allow_parent_continuation")

    assert [
             %{
               "review_id" => review_id,
               "thread_id" => ^thread,
               "turn_id" => ^turn,
               "target_item_id" => @call
             }
           ] = events(ctx, "allow_review_completed")

    assert review_id == approved["reviewId"]

    completed_index =
      Enum.find_index(received, fn event ->
        event.wire["method"] == "item/completed" and
          get_in(event.wire, ["params", "item", "id"]) == @call
      end)

    approved_index = Enum.find_index(received, &(&1.wire["method"] == @completed))
    assert is_integer(approved_index) and is_integer(completed_index)
    assert approved_index < completed_index
    completed = Enum.at(received, completed_index).wire["params"]["item"]
    assert completed["type"] == "mcpToolCall" and completed["status"] == "completed"
    assert completed["arguments"] == %{"message" => "owned harmless allow payload"}

    assert completed["result"]["content"] == [
             %{"type" => "text", "text" => "owned harmless allow result"}
           ]

    assert completed["error"] == nil

    journal = journal(ctx)["events"]
    released = Enum.find_index(journal, &(&1["event"] == "allow_reviewer_released"))
    dispatched = Enum.find_index(journal, &(&1["event"] == "mcp_action_dispatched"))
    continued = Enum.find_index(journal, &(&1["event"] == "allow_parent_continuation"))
    assert is_integer(released) and is_integer(dispatched) and is_integer(continued)
    assert released < dispatched and dispatched < continued
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 2
    assert Enum.count(events(ctx, "mcp"), &(&1["method"] == "tools/call")) == 1
    assert_no_interactions(received)
    finish(ctx, pid)
  end

  @tag scenario: "deny-medium-low"
  test "native fixed medium-risk low-authorization assessment remains denied without execution",
       ctx do
    pid = start(ctx, false)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &done?(&1, thread, turn))
    {_started, denied} = assert_review(received, thread, turn, "denied")

    assert denied["review"] === %{
             "status" => "denied",
             "riskLevel" => "medium",
             "userAuthorization" => "low",
             "rationale" => "Owned medium-risk action remains denied."
           }

    assert denied["decisionSource"] == "agent"

    assert notice(received, "guardianWarning")["message"] ==
             "Automatic approval review denied (risk: medium, authorization: low): " <>
               "Owned medium-risk action remains denied."

    assert notice(received, @strict) == nil
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 2
    refute Enum.any?(events(ctx, "mcp"), &(&1["method"] == "tools/call"))

    refute Enum.any?(
             events(ctx, "native_input"),
             &(&1["method"] == "thread/approveGuardianDeniedAction")
           )

    assert events(ctx, "mcp_action_dispatched") == []
    assert events(ctx, "allow_parent_continuation") == []
    assert events(ctx, "forbidden_mcp") == []
    finish(ctx, pid)
  end

  @tag scenario: "deny-critical-medium"
  test "native fixed critical-risk medium-authorization assessment remains denied without execution",
       ctx do
    pid = start(ctx, false)
    {thread, turn} = turn(ctx, pid)
    received = collect(pid, &done?(&1, thread, turn))
    {_started, denied} = assert_review(received, thread, turn, "denied")

    assert denied["review"] === %{
             "status" => "denied",
             "riskLevel" => "critical",
             "userAuthorization" => "medium",
             "rationale" => "Owned critical-risk action remains denied."
           }

    assert denied["decisionSource"] == "agent"

    assert notice(received, "guardianWarning")["message"] ==
             "Automatic approval review denied (risk: critical, authorization: medium): " <>
               "Owned critical-risk action remains denied."

    assert notice(received, @strict) == nil
    assert Enum.count(provider(ctx), &(&1["reviewer"] == true)) == 1
    assert Enum.count(provider(ctx), &(&1["reviewer"] == false)) == 2
    refute Enum.any?(events(ctx, "mcp"), &(&1["method"] == "tools/call"))

    refute Enum.any?(
             events(ctx, "native_input"),
             &(&1["method"] == "thread/approveGuardianDeniedAction")
           )

    assert events(ctx, "mcp_action_dispatched") == []
    assert events(ctx, "allow_parent_continuation") == []
    assert events(ctx, "forbidden_mcp") == []
    finish(ctx, pid)
  end

  defp start(ctx, experimental) do
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
             Session.initialize(pid, %{"name" => "samgita_guardian", "version" => "1"}, %{
               "experimentalApi" => experimental
             })

    wait(fn -> Enum.any?(events(ctx, "native_input"), &(&1["method"] == "initialized")) end)
    pid
  end

  defp turn(ctx, pid) do
    thread =
      call(pid, "thread/start", %{"cwd" => Path.join(ctx.root, "workspace")})["thread"]["id"]

    text =
      if ctx.scenario == "allow", do: "synthetic:guardian:allow", else: "synthetic:guardian:deny"

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => text}]
      })["turn"]["id"]

    {thread, turn}
  end

  defp assert_review(received, thread, turn, terminal) do
    started = notice(received, @started)
    completed = notice(received, @completed)
    assert started["threadId"] == thread and completed["threadId"] == thread
    assert started["turnId"] == turn and completed["turnId"] == turn
    assert is_binary(started["reviewId"]) and started["reviewId"] != ""
    assert completed["reviewId"] == started["reviewId"]
    assert started["targetItemId"] == @call and completed["targetItemId"] == @call
    assert started["review"]["status"] == "inProgress"
    assert completed["review"]["status"] == terminal
    assert is_integer(started["startedAtMs"]) and started["startedAtMs"] > 0
    assert completed["startedAtMs"] == started["startedAtMs"]
    assert completed["completedAtMs"] >= completed["startedAtMs"]
    assert started["action"] == completed["action"]
    assert completed["action"]["type"] == "mcpToolCall"
    assert completed["action"]["server"] == "owned_guardian"
    assert completed["action"]["toolName"] == "denied_action"
    assert Enum.count(received, &(&1.wire["method"] == @started)) == 1
    assert Enum.count(received, &(&1.wire["method"] == @completed)) == 1
    assert_no_interactions(received)
    {started, completed}
  end

  defp denial_event(params) do
    action = params["action"]

    %{
      "id" => params["reviewId"],
      "target_item_id" => params["targetItemId"],
      "turn_id" => params["turnId"],
      "started_at_ms" => params["startedAtMs"],
      "completed_at_ms" => params["completedAtMs"],
      "status" => "denied",
      "decision_source" => "agent",
      "risk_level" => params["review"]["riskLevel"],
      "user_authorization" => params["review"]["userAuthorization"],
      "rationale" => params["review"]["rationale"],
      "action" => %{
        "type" => "mcp_tool_call",
        "server" => action["server"],
        "tool_name" => action["toolName"],
        "connector_id" => action["connectorId"],
        "connector_name" => action["connectorName"],
        "tool_title" => action["toolTitle"]
      }
    }
  end

  defp assert_no_interactions(received),
    do: assert(Enum.all?(received, &(&1.kind != :server_request)))

  defp finish(ctx, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    proof = journal(ctx)["namespace"]
    assert proof["parent"] == File.read_link!("/proc/self/ns/net")
    assert proof["parent"] != proof["child"] and proof["interfaces"] == ["lo"]
    refute proof["default_route"]
    refute proof["ipv6_default_route"]
    assert :ok = Session.close(pid)
    wait(fn -> events(ctx, "native_closed") != [] end)
    assert [%{"passed" => true}] = events(ctx, "secret_scan")
    assert [%{"binary_sha256" => @sha}] = events(ctx, "native_started")

    for name <- ~w(fixture_error forbidden_http forbidden_mcp),
        do: assert(events(ctx, name) == [])
  end

  defp call(pid, method, params) do
    id = "owned-guardian-#{System.unique_integer([:positive])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    result
  end

  defp notice(received, method),
    do:
      Enum.find_value(received, fn event ->
        if event.wire["method"] == method, do: event.wire["params"]
      end)

  defp done?(received, thread, turn, status \\ "completed") do
    Enum.any?(received, fn event ->
      event.wire["method"] == "turn/completed" and event.wire["params"]["threadId"] == thread and
        event.wire["params"]["turn"]["id"] == turn and
        event.wire["params"]["turn"]["status"] == status
    end)
  end

  defp collect(pid, done, received \\ [], remaining \\ 1_500)
  defp collect(_pid, _done, _received, 0), do: flunk("Owned Guardian event deadline")

  defp collect(pid, done, received, remaining) do
    assert {:ok, current} = Session.drain(pid)
    received = received ++ current

    if done.(received) do
      received
    else
      assert Session.status(pid).phase == :ready
      Process.sleep(10)
      collect(pid, done, received, remaining - 1)
    end
  end

  defp journal(ctx), do: ctx.root |> Path.join("journal.json") |> File.read!() |> JSON.decode!()
  defp events(ctx, name), do: Enum.filter(journal(ctx)["events"], &(&1["event"] == name))
  defp provider(ctx), do: events(ctx, "provider_request")
  defp wait(predicate, remaining \\ 500)
  defp wait(_predicate, 0), do: flunk("Owned Guardian fixture deadline")

  defp wait(predicate, remaining) do
    if value = predicate.() do
      value
    else
      Process.sleep(10)
      wait(predicate, remaining - 1)
    end
  end
end
