defmodule SamgitaCodexDriver.NativeOutputNoticeLifecycleTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.{Stdio, UnixSocket}
  import SamgitaCodexDriver.TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/output_notice_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @before_text "owned before\n"
  @after_text "owned after λ🙂\n"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-output-notice-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for dir <- ~w(home codex workspace tmp), do: File.mkdir_p!(Path.join(root, dir))
    File.write!(Path.join(root, "requests.json"), "[]")
    workspace = Path.join(root, "workspace")
    File.write!(Path.join(workspace, "owned-notice.txt"), @before_text)
    File.write!(Path.join(workspace, "untouched.txt"), "owned untouched\n")
    on_exit(fn -> File.rm_rf!(root) end)
    ctx = %{root: root, workspace: workspace, socket: Path.join(root, "native.sock")}

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
        cwd: workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "RUST_LOG" => "off",
          "NO_COLOR" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = state(ctx)

        for key <- ~w(native_pid controller_pid namespace_owner_pid),
            do: await(fn -> not File.exists?("/proc/#{proof[key]}") end)
      end
    end)

    await(fn -> File.exists?(Path.join(root, "state.json")) end)
    proof = state(ctx)
    assert proof["parent_namespace"] == File.read_link!("/proc/self/ns/net")
    assert proof["namespace"] != proof["parent_namespace"] and proof["interfaces"] == ["lo"]
    assert proof["default_route"] == false and proof["ipv6_default_route"] == false
    ctx
  end

  test "native reasoning notices preserve synthetic indices fragments identity and order", ctx do
    {pid, thread, turn, events} = run(ctx, "reasoning")
    parts = notices(events, "item/reasoning/summaryPartAdded")
    summaries = notices(events, "item/reasoning/summaryTextDelta")
    raw = notices(events, "item/reasoning/textDelta")

    assert Enum.map(parts, & &1["summaryIndex"]) == [0, 1]

    assert Enum.map(summaries, &{&1["summaryIndex"], &1["delta"]}) == [
             {0, "Synthetic summary "},
             {0, "λ🙂"},
             {1, "Synthetic second summary"}
           ]

    assert Enum.map(raw, &{&1["contentIndex"], &1["delta"]}) == [
             {2, "Synthetic raw "},
             {2, "α🙂"}
           ]

    for params <- parts ++ summaries ++ raw,
        do:
          assert(
            params["threadId"] == thread and params["turnId"] == turn and
              params["itemId"] == "owned-reasoning"
          )

    started = index(events, "item/started", &(&1["item"]["id"] == "owned-reasoning"))
    completed = index(events, "item/completed", &(&1["item"]["id"] == "owned-reasoning"))

    for method <-
          ~w(item/reasoning/summaryPartAdded item/reasoning/summaryTextDelta item/reasoning/textDelta) do
      positions = indices(events, method)
      assert Enum.all?(positions, &(started < &1 and &1 < completed))
    end

    assert index(events, "item/reasoning/summaryPartAdded") <
             index(events, "item/reasoning/summaryTextDelta")

    assert index(events, "item/reasoning/summaryTextDelta") <
             index(events, "item/reasoning/textDelta")

    assert_profile(ctx, pid, events, 1)
  end

  test "native Plan mode emits identified proposed-plan deltas and authoritative final item",
       ctx do
    {pid, thread, turn, events} = run(ctx, "plan", "plan")
    plan = "# Owned plan λ🙂\n- first\n- second\n"
    item = turn <> "-plan"
    deltas = notices(events, "item/plan/delta")
    assert deltas != []

    assert Enum.all?(
             deltas,
             &(&1["threadId"] == thread and &1["turnId"] == turn and &1["itemId"] == item and
                 &1["delta"] != "")
           )

    assert Enum.map_join(deltas, & &1["delta"]) == plan

    assert [%{"item" => %{"id" => ^item, "type" => "plan", "text" => ^plan}}] =
             Enum.filter(notices(events, "item/completed"), &(&1["item"]["type"] == "plan"))

    first = index(events, "item/started", &(&1["item"]["id"] == item))
    last = index(events, "item/completed", &(&1["item"]["id"] == item))
    assert Enum.all?(indices(events, "item/plan/delta"), &(first < &1 and &1 < last))
    assert notices(events, "turn/plan/updated") == []
    assert_profile(ctx, pid, events, 1)
  end

  test "native checklist update preserves explanation and all three step statuses outside Plan mode",
       ctx do
    {pid, thread, turn, events} = run(ctx, "checklist")

    assert notices(events, "turn/plan/updated") == [
             %{
               "threadId" => thread,
               "turnId" => turn,
               "explanation" => "Synthetic checklist λ🙂",
               "plan" => [
                 %{"step" => "Owned completed step", "status" => "completed"},
                 %{"step" => "Owned current step", "status" => "inProgress"},
                 %{"step" => "Owned pending step", "status" => "pending"}
               ]
             }
           ]

    assert notices(events, "item/plan/delta") == []
    assert index(events, "turn/plan/updated") < index(events, "turn/completed")
    assert_profile(ctx, pid, events, 2)
  end

  test "native streamed patch updates only the fixed owned regular file and emits exact final diff",
       ctx do
    path = Path.join(ctx.workspace, "owned-notice.txt")
    assert File.lstat!(path).type == :regular
    assert File.read!(path) == @before_text
    {pid, thread, turn, events} = run(ctx, "patch", "default", "workspace-write")
    patches = notices(events, "item/fileChange/patchUpdated")
    assert patches != []

    for params <- patches do
      assert params["threadId"] == thread and params["turnId"] == turn and
               params["itemId"] == "owned-patch-call"

      assert [%{"path" => "owned-notice.txt", "kind" => %{"type" => "update"}, "diff" => diff}] =
               params["changes"]

      assert is_binary(diff) and diff != ""
    end

    assert List.last(patches)["changes"] == [
             %{
               "path" => "owned-notice.txt",
               "kind" => %{"type" => "update", "move_path" => nil},
               "diff" => "@@\n-owned before\n+owned after λ🙂\n"
             }
           ]

    expected = %{"threadId" => thread, "turnId" => turn, "diff" => expected_diff()}
    diffs = notices(events, "turn/diff/updated")
    assert diffs != []
    assert Enum.all?(diffs, &(&1 == expected))
    assert List.last(diffs) == expected

    assert %{
             "item" => %{
               "id" => "owned-patch-call",
               "type" => "fileChange",
               "status" => "completed"
             }
           } =
             notice(events, "item/completed", &(&1["item"]["id"] == "owned-patch-call"))

    assert File.lstat!(path).type == :regular and File.read!(path) == @after_text
    assert File.read!(Path.join(ctx.workspace, "untouched.txt")) == "owned untouched\n"
    assert Enum.sort(File.ls!(ctx.workspace)) == ["owned-notice.txt", "untouched.txt"]
    assert index(events, "item/fileChange/patchUpdated") < index(events, "turn/diff/updated")

    assert Enum.all?(
             indices(events, "turn/diff/updated"),
             &(&1 < index(events, "turn/completed"))
           )

    assert_profile(ctx, pid, events, 2)
  end

  defp run(ctx, scenario, mode \\ "default", sandbox \\ "read-only") do
    {:ok, pid} = Session.start_link(transport: {UnixSocket, [socket_path: ctx.socket]})

    on_exit(fn ->
      if Process.alive?(pid), do: assert(:ok = Session.close(pid))
    end)

    assert {:ok, _} =
             Session.initialize(
               pid,
               %{"name" => "samgita_output_notices", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    thread =
      call(pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.workspace,
        "sandbox" => sandbox,
        "approvalPolicy" => "on-request"
      })["thread"]["id"]

    turn =
      call(pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "synthetic:output-#{scenario}"}],
        "collaborationMode" => %{
          "mode" => mode,
          "settings" => %{
            "model" => "mock-model",
            "reasoning_effort" => nil,
            "developer_instructions" => nil
          }
        }
      })["turn"]["id"]

    events = collect(pid, turn, [], System.monotonic_time(:millisecond) + 20_000)

    assert %{
             "threadId" => ^thread,
             "turn" => %{"id" => ^turn, "status" => "completed", "error" => nil}
           } = notice(events, "turn/completed")

    {pid, thread, turn, events}
  end

  defp collect(pid, turn, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)
    acc = acc ++ events

    refute Enum.any?(acc, &(&1.kind == :server_request)),
           "Unexpected approval/tool request; no response is authorized"

    cond do
      notice(acc, "turn/completed", &(&1["turn"]["id"] == turn)) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Owned output notice deadline")

      true ->
        assert Session.status(pid).phase == :ready

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected output notice gap")
        after
          20 -> :ok
        end

        collect(pid, turn, acc, deadline)
    end
  end

  defp assert_profile(ctx, pid, events, expected_requests) do
    assert length(JSON.decode!(File.read!(Path.join(ctx.root, "requests.json")))) ==
             expected_requests

    refute File.exists?(Path.join(ctx.root, "forbidden-fetch.json"))
    assert notices(events, "item/fileChange/outputDelta") == []
    assert Session.status(pid).interactions == 0
    output = JSON.decode!(File.read!(Path.join(ctx.root, "provider-events.json")))
    assert length(output) == expected_requests

    for response <- output, event <- response do
      assert String.starts_with?(event["type"], "response.")
      refute Map.has_key?(event, "method")
    end
  end

  defp expected_diff do
    "diff --git a/owned-notice.txt b/owned-notice.txt\n" <>
      "index #{blob_oid(@before_text)}..#{blob_oid(@after_text)}\n" <>
      "--- a/owned-notice.txt\n+++ b/owned-notice.txt\n@@ -1 +1 @@\n-owned before\n+owned after λ🙂\n"
  end

  defp blob_oid(content),
    do: Base.encode16(:crypto.hash(:sha, "blob #{byte_size(content)}\0" <> content), case: :lower)

  defp state(ctx), do: JSON.decode!(File.read!(Path.join(ctx.root, "state.json")))

  defp notices(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp notice(events, method, predicate \\ fn _ -> true end),
    do: Enum.find(notices(events, method), predicate)

  defp indices(events, method),
    do: for({event, i} <- Enum.with_index(events), event.wire["method"] == method, do: i)

  defp index(events, method, predicate \\ fn _ -> true end) do
    result =
      Enum.find_index(events, &(&1.wire["method"] == method and predicate.(&1.wire["params"])))

    assert is_integer(result)
    result
  end

  defp await(predicate, remaining \\ 500)

  defp await(predicate, remaining) when remaining > 0 do
    if predicate.() do
      :ok
    else
      Process.sleep(10)
      await(predicate, remaining - 1)
    end
  end

  defp await(_predicate, 0), do: flunk("Owned output fixture startup/shutdown deadline")
end
