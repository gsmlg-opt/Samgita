defmodule SamgitaCodexDriver.DefaultGateRecordingUDS do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.UnixSocket

  @impl true
  def open(opts) do
    with {:ok, inner} <- UnixSocket.open(opts),
         do: {:ok, %{inner: inner, sent: Keyword.fetch!(opts, :sent_path)}}
  end

  @impl true
  def send(state, json) do
    # Synthetic fixtures only. Record the exact bytes; do not normalize params.
    File.write!(state.sent, json <> "\n", [:append])

    case UnixSocket.send(state.inner, json) do
      {:ok, inner} -> {:ok, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case UnixSocket.handle_info(message, state.inner) do
      :unknown -> :unknown
      {:ok, events, inner} -> {:ok, events, %{state | inner: inner}}
      {:error, error, inner} -> {:error, error, %{state | inner: inner}}
    end
  end

  @impl true
  def close(state), do: UnixSocket.close(state.inner)
  @impl true
  def metadata(state), do: UnixSocket.metadata(state.inner)
end

defmodule SamgitaCodexDriver.NativeDefaultGatesProfile do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{DefaultGateRecordingUDS, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.Error

  @moduletag :real_codex
  @moduletag :isolated_default_gates
  @moduletag timeout: 90_000
  @script Path.expand("../../../scripts/codex/isolated_default_gates_fixture.py", __DIR__)
  @sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) == @sha
    for tool <- ~w(python3 unshare ip), do: assert(System.find_executable(tool))

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-default-gates-" <>
          Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(root)
    File.chmod!(root, 0o700)

    for directory <- ~w(home codex workspace tmp bin),
        do: File.mkdir!(Path.join(root, directory))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.write!(Path.join(root, "requests.json"), "[]")
    on_exit(fn -> File.rm_rf!(root) end)

    ctx = %{
      root: root,
      socket: Path.join(root, "native.sock"),
      workspace: Path.join(root, "workspace"),
      parent_netns: File.read_link!("/proc/self/ns/net"),
      parent_userns: File.read_link!("/proc/self/ns/user")
    }

    {:ok, owner} =
      Stdio.open(
        executable: System.find_executable("python3"),
        args: [@script, "--root", root, "--codex", Path.expand(binary)],
        cwd: ctx.workspace,
        inherit_env: [],
        env: %{
          "HOME" => Path.join(root, "home"),
          "CODEX_HOME" => Path.join(root, "codex"),
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(root, "bin/sh"),
          "NO_COLOR" => "1",
          "RUST_LOG" => "off",
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "PYTHONDONTWRITEBYTECODE" => "1"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(owner)

      if File.exists?(Path.join(root, "state.json")) do
        proof = read(ctx, "state.json")

        for pid <-
              proof["native_pids"] ++ [proof["controller_pid"], proof["namespace_owner_pid"]],
            do: await(fn -> not File.exists?("/proc/#{pid}") end, "owned process reaping")
      end
    end)

    await(
      fn ->
        File.exists?(Path.join(root, "state.json")) and read(ctx, "state.json")["ready"]
      end,
      "owned fixture readiness"
    )

    proof = read(ctx, "state.json")
    assert proof["ready"]
    assert proof["namespace"] != ctx.parent_netns
    assert proof["parent_namespace"] == ctx.parent_netns
    assert proof["user_namespace"] != ctx.parent_userns
    assert proof["parent_user_namespace"] == ctx.parent_userns
    assert proof["interfaces"] == ["lo"]
    refute proof["default_route"] or proof["ipv6_default_route"]
    Map.put(ctx, :owner, owner)
  end

  test "primitive experimental booleans default false, reject null, and gate true", ctx do
    for negotiation <- [:absent, false] do
      {pid, journal} = client(ctx, negotiation)

      for field <- ~w(allowProviderModelFallback experimentalRawEvents) do
        for extra <- [%{}, %{field => false}] do
          result = start(pid, ctx, extra)
          assert result["model"] == "mock-model"
          assert last_params(journal, "thread/start") == params(ctx, extra)
        end

        reject_gate(pid, ctx, journal, field, true)
        before = count(journal, "thread/start")

        assert {:error, %Error{code: :schema_violation}} =
                 Session.request(pid, "thread/start", params(ctx, %{field => nil}))

        assert count(journal, "thread/start") == before
        error = wire_error(pid, "thread/start", params(ctx, %{field => nil}))
        assert error["code"] == -32_600
        assert error["message"] =~ "invalid type: null, expected a boolean"
      end
    end

    {enabled, journal} = client(ctx, true)

    for field <- ~w(allowProviderModelFallback experimentalRawEvents) do
      assert start(enabled, ctx, %{field => true})["model"] == "mock-model"
      assert last_params(journal, "thread/start")[field] == true
    end

    assert read(ctx, "requests.json") == []
  end

  test "optional false, empty vectors, and empty strings stay active experimental values", ctx do
    values = [
      {"daybreakEnabled", false},
      {"daybreakEnabled", true},
      {"dynamicTools", []},
      {"mockExperimentalField", ""},
      {"mockExperimentalField", "owned-default-value"},
      {"historyMode", "legacy"},
      {"historyMode", "paginated"}
    ]

    {stable, journal} = client(ctx, false)

    for field <- ~w(daybreakEnabled dynamicTools mockExperimentalField historyMode) do
      result = start(stable, ctx, %{field => nil})
      assert result["thread"]["daybreakEnabled"] == nil
      assert last_params(journal, "thread/start")[field] == nil
      assert Map.has_key?(last_params(journal, "thread/start"), field)
    end

    for {field, value} <- values, do: reject_gate(stable, ctx, journal, field, value)

    {enabled, enabled_journal} = client(ctx, true)

    for {field, value} <- values do
      result = start(enabled, ctx, %{field => value})
      assert last_params(enabled_journal, "thread/start") == params(ctx, %{field => value})
      if field in ~w(daybreakEnabled historyMode), do: assert(result["thread"][field] == value)
    end

    assert read(ctx, "requests.json") == []
  end

  test "thread tier double-option inherits config while explicit null requests native default",
       ctx do
    {pid, journal} = client(ctx, false)

    for {extra, expected} <- [
          {%{}, "flex"},
          {%{"serviceTier" => nil}, "default"},
          {%{"serviceTier" => "default"}, "default"},
          {%{"serviceTier" => "flex"}, "flex"},
          {%{"serviceTier" => "owned-unsupported-tier"}, nil}
        ] do
      result = start(pid, ctx, extra)
      assert result["serviceTier"] == expected
      assert last_params(journal, "thread/start") == params(ctx, extra)
      assert result["thread"]["ephemeral"] == false
    end

    assert read(ctx, "requests.json") == []
  end

  test "thread null options preserve durable defaults and explicit history/ephemeral choices",
       ctx do
    {pid, journal} = client(ctx, true)

    for {extra, ephemeral, history} <- [
          {%{}, false, "paginated"},
          {%{"ephemeral" => nil, "historyMode" => nil}, false, "paginated"},
          {%{"ephemeral" => false}, false, "paginated"},
          {%{"ephemeral" => true}, true, "paginated"},
          {%{"historyMode" => "legacy"}, false, "legacy"},
          {%{"historyMode" => "paginated"}, false, "paginated"}
        ] do
      result = start(pid, ctx, extra)
      assert result["thread"]["ephemeral"] == ephemeral
      assert result["thread"]["historyMode"] == history
      assert last_params(journal, "thread/start") == params(ctx, extra)
    end

    assert read(ctx, "requests.json") == []
  end

  test "turn optional maps accept null but gate empty objects without starting rejected turns",
       ctx do
    {stable, journal} = client(ctx, false)
    thread = start(stable, ctx)["thread"]["id"]

    for {field, index} <- Enum.with_index(~w(additionalContext responsesapiClientMetadata), 1) do
      for {extra, marker} <- [{%{}, index * 10}, {%{field => nil}, index * 10 + 1}] do
        before = length(read(ctx, "requests.json"))
        turn = start_turn(stable, thread, marker, extra)
        events = finish(stable, turn)
        assert length(read(ctx, "requests.json")) == before + 1
        assert last_params(journal, "turn/start") == turn_params(thread, marker, extra)
        refute Enum.any?(events, &(&1.kind == :server_request))
      end

      rejected = turn_params(thread, index * 10 + 2, %{field => %{}})
      requests = read(ctx, "requests.json")
      before = count(journal, "turn/start")

      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(stable, "turn/start", rejected)

      assert count(journal, "turn/start") == before

      assert wire_error(stable, "turn/start", rejected) == %{
               "code" => -32_600,
               "message" => "turn/start.#{field} requires experimentalApi capability"
             }

      assert read(ctx, "requests.json") == requests
      assert {:ok, events} = Session.drain(stable)
      refute Enum.any?(events, &(&1.wire["method"] == "turn/started"))
    end

    {enabled, enabled_journal} = client(ctx, true)
    thread = start(enabled, ctx)["thread"]["id"]

    for {field, index} <- Enum.with_index(~w(additionalContext responsesapiClientMetadata), 100) do
      turn = start_turn(enabled, thread, index, %{field => %{}})
      events = finish(enabled, turn)

      assert last_params(enabled_journal, "turn/start") ==
               turn_params(thread, index, %{field => %{}})

      refute Enum.any?(events, &(&1.kind == :server_request))
    end

    assert length(read(ctx, "requests.json")) == 6
  end

  test "fork normalizes omitted null and empty paths before experimental negotiation", ctx do
    for negotiation <- [:absent, false] do
      {creator, _} = client(ctx, true)
      id = start(creator, ctx, %{"historyMode" => "legacy"})["thread"]["id"]
      name = "Owned empty-path fork #{negotiation}"
      assert call(creator, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
      parent_query = %{"threadId" => id, "includeTurns" => true}
      saved = call(creator, "thread/read", parent_query)["thread"]
      assert_idle_without_work(ctx, creator)
      assert :ok = Session.close(creator)
      restart_owned_native(ctx)
      {pid, journal} = client(ctx, negotiation)
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      parent = call(pid, "thread/read", parent_query)["thread"]
      assert parent["id"] == id
      assert parent["name"] == name
      assert parent["historyMode"] == "legacy"
      assert parent["turns"] == []
      assert parent["path"] == saved["path"]
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      parent_bytes = File.read!(parent["path"])

      assert [parent_meta] =
               parent_bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

      assert parent_meta["type"] == "session_meta"
      assert parent_meta["payload"]["id"] == id
      assert_idle_without_work(ctx, pid)

      for extra <- [%{}, %{"path" => nil}, %{"path" => ""}] do
        before = call(pid, "thread/loaded/list", %{})["data"] |> MapSet.new()
        rollouts = Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl"))
        active = %{"threadId" => id, "path" => parent["path"]}
        sent_before = count(journal, "thread/fork")

        assert {:error, %Error{code: :experimental_api_required}} =
                 Session.request(pid, "thread/fork", active)

        assert count(journal, "thread/fork") == sent_before

        assert wire_error(pid, "thread/fork", active) == %{
                 "code" => -32_600,
                 "message" => "thread/fork.path requires experimentalApi capability"
               }

        assert last_params(journal, "thread/fork") == active
        assert MapSet.new(call(pid, "thread/loaded/list", %{})["data"]) == before
        assert Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl")) == rollouts
        assert call(pid, "thread/read", parent_query)["thread"] == parent
        assert File.read!(parent["path"]) == parent_bytes
        assert_idle_without_work(ctx, pid)

        request = Map.merge(%{"threadId" => id}, extra)
        response = call(pid, "thread/fork", request)
        assert last_params(journal, "thread/fork") == request

        assert Map.has_key?(last_params(journal, "thread/fork"), "path") ==
                 Map.has_key?(extra, "path")

        child = Map.fetch!(response, "thread")
        child_id = Map.fetch!(child, "id")
        assert is_binary(child_id) and byte_size(child_id) > 0
        refute child_id == id or MapSet.member?(before, child_id)
        assert child["forkedFromId"] == id
        assert child["name"] == name
        assert child["historyMode"] == "legacy"
        assert child["turns"] == []
        child_path = Map.fetch!(child, "path")
        refute child_path == parent["path"]
        assert File.regular?(child_path)
        assert_default_session_settings(ctx, response, "low")

        assert MapSet.new(call(pid, "thread/loaded/list", %{})["data"]) ==
                 MapSet.put(before, child_id)

        persisted =
          call(pid, "thread/read", %{"threadId" => child_id, "includeTurns" => true})["thread"]

        for field <- ~w(id forkedFromId name historyMode turns path),
            do: assert(Map.fetch!(persisted, field) == Map.fetch!(child, field))

        await(
          fn ->
            bytes = File.read!(child_path)
            String.ends_with?(bytes, "\n") and length(String.split(bytes, "\n", trim: true)) == 3
          end,
          "fork metadata inherited history and settings flush"
        )

        [meta, inherited, _checkpoint] =
          child_path
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.map(&JSON.decode!/1)

        assert meta["type"] == "session_meta"
        assert meta["payload"]["id"] == child_id
        assert meta["payload"]["forked_from_id"] == id
        assert meta["payload"]["history_mode"] == "legacy"
        assert meta["payload"]["cwd"] == ctx.workspace
        assert Map.delete(inherited, "timestamp") == Map.delete(parent_meta, "timestamp")
        prefix = child_path |> File.read!() |> String.split("\n", trim: true) |> Enum.take(2)

        assert_resume_rollout(
          ctx,
          child_path,
          Enum.join(prefix, "\n") <> "\n",
          child_id,
          1,
          "low"
        )

        assert call(pid, "thread/read", parent_query)["thread"] == parent
        assert File.read!(parent["path"]) == parent_bytes
        assert_idle_without_work(ctx, pid)
      end

      assert :ok = Session.close(pid)
    end
  end

  test "cold resume history omission and null preserve history while empty history is active",
       ctx do
    {creator, _} = client(ctx, true)
    id = start(creator, ctx, %{"historyMode" => "legacy"})["thread"]["id"]
    name = "Owned cold-history resume"
    assert call(creator, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    saved = call(creator, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert saved["id"] == id
    assert saved["name"] == name
    assert saved["historyMode"] == "legacy"
    assert saved["turns"] == []
    assert :ok = Session.close(creator)
    restart_owned_native(ctx)
    rollout = File.read!(saved["path"])
    assert [meta] = rollout |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert meta["type"] == "session_meta"
    assert meta["payload"]["id"] == id
    assert meta["payload"]["history_mode"] == "legacy"
    assert String.ends_with?(rollout, "\n")

    cases =
      for negotiation <- [:absent, false, true],
          extra <- [%{}, %{"history" => nil}],
          do: {negotiation, extra}

    for {{negotiation, extra}, resume_count} <- Enum.with_index(cases, 1) do
      {pid, journal} = client(ctx, negotiation)
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      previous_rollout = File.read!(saved["path"])
      rollouts = Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl"))
      active = %{"threadId" => id, "history" => []}
      sent_before = count(journal, "thread/resume")

      unless negotiation == true do
        assert {:error, %Error{code: :experimental_api_required}} =
                 Session.request(pid, "thread/resume", active)

        assert count(journal, "thread/resume") == sent_before
      end

      message =
        if negotiation == true,
          do: "history must not be empty",
          else: "thread/resume.history requires experimentalApi capability"

      assert wire_error(pid, "thread/resume", active) == %{
               "code" => -32_600,
               "message" => message
             }

      assert last_params(journal, "thread/resume") == active
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      assert Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl")) == rollouts
      assert File.read!(saved["path"]) == previous_rollout
      assert_resume_rollout(ctx, saved["path"], rollout, id, resume_count - 1)
      assert_idle_without_work(ctx, pid)

      request = Map.merge(%{"threadId" => id}, extra)
      response = call(pid, "thread/resume", request)
      assert last_params(journal, "thread/resume") == request

      assert Map.has_key?(last_params(journal, "thread/resume"), "history") ==
               Map.has_key?(extra, "history")

      resumed = Map.fetch!(response, "thread")
      assert resumed["id"] == id
      assert resumed["name"] == name
      assert resumed["path"] == saved["path"]
      assert resumed["historyMode"] == "legacy"
      assert resumed["turns"] == []
      assert_default_session_settings(ctx, response, nil)
      assert call(pid, "thread/loaded/list", %{})["data"] == [id]
      loaded = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]

      for field <- ~w(id name historyMode turns path),
          do: assert(Map.fetch!(loaded, field) == Map.fetch!(resumed, field))

      assert_idle_without_work(ctx, pid)
      assert :ok = Session.close(pid)

      await(
        fn ->
          bytes = File.read!(saved["path"])

          String.starts_with?(bytes, rollout) and String.ends_with?(bytes, "\n") and
            length(String.split(bytes, "\n", trim: true)) == resume_count + 1
        end,
        "cold history resume settings checkpoint"
      )

      restart_owned_native(ctx)
      assert_resume_rollout(ctx, saved["path"], rollout, id, resume_count)
      durable = File.read!(saved["path"])
      assert binary_part(durable, 0, byte_size(previous_rollout)) == previous_rollout
      assert read(ctx, "requests.json") == []
    end
  end

  test "supplied typed content retains known history before one explicit turn", ctx do
    {pid, journal} = client(ctx, true)
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert_no_import_work(ctx, pid, [])

    history = [
      %{
        "type" => "message",
        "id" => "msg_owned_history_anchor",
        "role" => "user",
        "content" => [%{"type" => "input_text", "text" => "Owned supplied-history anchor λ"}]
      },
      %{
        "type" => "agent_message",
        "id" => "amsg_owned_history_plaintext",
        "author" => "/owned-history-worker",
        "recipient" => "/",
        "content" => [
          %{"type" => "input_text", "text" => "Owned historical agent note α"},
          %{"type" => "input_text", "text" => "Owned historical agent note β"}
        ]
      },
      %{
        "type" => "reasoning",
        "id" => "rs_owned_history_reasoning",
        "summary" => [],
        "content" => [
          %{"type" => "reasoning_text", "text" => "Owned historical reasoning λ"},
          %{"type" => "text", "text" => "Owned historical reasoning continuation β"}
        ],
        "encrypted_content" => nil
      },
      %{
        "type" => "message",
        "id" => "msg_owned_history_answer",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "output_text",
            "text" => "Owned historical answer γ",
            "annotations" => [],
            "logprobs" => []
          }
        ]
      }
    ]

    known_ids = Enum.map(history, &Map.fetch!(&1, "id"))
    requested_id = "00000000-0000-4000-8000-000000000912"
    request = params(ctx, %{"threadId" => requested_id, "history" => history})
    imported = call(pid, "thread/resume", request)["thread"]
    id = Map.fetch!(imported, "id")
    path = Map.fetch!(imported, "path")
    assert count(journal, "thread/resume") == 1
    assert last_params(journal, "thread/resume") == request
    assert is_binary(id) and id != "" and id != requested_id
    assert String.starts_with?(path, Path.join(ctx.root, "codex/sessions/"))
    assert File.regular?(path)
    assert imported["status"] == %{"type" => "idle"}
    assert imported["ephemeral"] == false
    assert imported["historyMode"] == "paginated"
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]
    assert_no_import_work(ctx, pid, [])

    await(
      fn ->
        bytes = File.read!(path)

        String.ends_with?(bytes, "\n") and
          length(String.split(bytes, "\n", trim: true)) == length(history) + 2
      end,
      "typed supplied history and settings flush"
    )

    imported_prefix = File.read!(path)
    records = rollout_records(imported_prefix)
    [meta | _] = records
    assert meta["type"] == "session_meta"
    assert Map.fetch!(meta, "ordinal") == 0
    assert meta["payload"]["id"] == id
    assert meta["payload"]["session_id"] == id
    imported_items = Enum.filter(records, &(&1["type"] == "response_item"))
    assert length(imported_items) == length(history)

    for {{record, expected}, ordinal} <-
          Enum.with_index(Enum.zip(imported_items, history), 1) do
      assert Map.delete(record, "timestamp") == %{
               "ordinal" => ordinal,
               "type" => "response_item",
               "payload" => expected
             }

      assert {:ok, _timestamp, 0} = DateTime.from_iso8601(Map.fetch!(record, "timestamp"))
    end

    prefix =
      imported_prefix
      |> String.split("\n", trim: true)
      |> Enum.take(length(history) + 1)
      |> Enum.join("\n")

    assert_resume_rollout(ctx, path, prefix <> "\n", id, 1, "low", length(history) + 1)
    assert_no_import_work(ctx, pid, [])

    turn = start_turn(pid, id, 912, %{})
    assert count(journal, "turn/start") == 1
    assert last_params(journal, "turn/start") == turn_params(id, 912, %{})
    assert_default_completion(finish(pid, turn), id, turn)
    assert [model_request] = read(ctx, "requests.json")
    input = Map.fetch!(model_request, "input")
    assert Enum.filter(input, &(&1["id"] in known_ids)) == history

    for known_id <- known_ids,
        do: assert(Enum.count(input, &(&1["id"] == known_id)) == 1)

    history_positions =
      for {item, index} <- Enum.with_index(input), item["id"] in known_ids, do: index

    current_positions =
      for {item, index} <- Enum.with_index(input),
          item["role"] == "user",
          part <- Map.get(item, "content", []),
          part == %{"type" => "input_text", "text" => "synthetic:defaults:912"},
          do: index

    assert [current_position] = current_positions
    assert current_position > Enum.max(history_positions)

    assert %{
             "thread_id" => ^id,
             "turn_id" => ^turn,
             "history_initialization" => "supplied_history"
           } = JSON.decode!(model_request["client_metadata"]["x-codex-turn-metadata"])

    assert :ok = Session.close(pid)
    restart_owned_native(ctx)
    durable = File.read!(path)
    assert String.starts_with?(durable, imported_prefix)
    assert String.ends_with?(durable, "\n")

    retained_items =
      durable
      |> rollout_records()
      |> Enum.filter(&(&1["type"] == "response_item" and &1["payload"]["id"] in known_ids))

    assert retained_items == imported_items

    for known_id <- known_ids,
        do: assert(Enum.count(retained_items, &(&1["payload"]["id"] == known_id)) == 1)

    assert read(ctx, "requests.json") == [model_request]
    {cold, cold_journal} = client(ctx, true)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    saved = call(cold, "thread/read", %{"threadId" => id})["thread"]
    assert saved["id"] == id
    assert saved["path"] == path
    assert saved["status"] == %{"type" => "notLoaded"}
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert count(cold_journal, "thread/resume") == 0
    assert count(cold_journal, "turn/start") == 0
    assert_no_import_work(ctx, cold, [model_request])
    assert File.read!(path) == durable
  end

  test "supplied history imports one independent durable thread before an explicit turn", ctx do
    {creator, _} = client(ctx, true)
    source_id = start(creator, ctx, %{"historyMode" => "legacy"})["thread"]["id"]
    source_name = "Owned populated supplied-history source"

    assert call(creator, "thread/name/set", %{
             "threadId" => source_id,
             "name" => source_name
           }) == %{}

    source_turn = start_turn(creator, source_id, 910, %{})
    assert_default_completion(finish(creator, source_turn), source_id, source_turn)
    source_query = %{"threadId" => source_id, "includeTurns" => true}
    source_path = call(creator, "thread/read", source_query)["thread"]["path"]
    assert :ok = Session.close(creator)
    restart_owned_native(ctx)
    source_bytes = File.read!(source_path)
    {pid, journal} = client(ctx, true)
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    source = call(pid, "thread/read", source_query)["thread"]
    assert source["id"] == source_id
    assert source["name"] == source_name
    assert source["historyMode"] == "legacy"
    assert source["status"] == %{"type" => "notLoaded"}
    assert [source_history] = source["turns"]
    assert_default_text_turn(source_history, source_turn, 910)
    assert [source_request] = read(ctx, "requests.json")
    source_requests = [source_request]
    assert File.read!(source_path) == source_bytes

    text = "Owned supplied history λ"

    message = %{
      "type" => "message",
      "role" => "user",
      "content" => [%{"type" => "input_text", "text" => text}]
    }

    missing_path = Path.join(ctx.root, "owned-never-existing-history-source.jsonl")
    refute File.exists?(missing_path)

    request =
      params(ctx, %{"threadId" => source_id, "path" => missing_path, "history" => [message]})

    # Omit path here so only the nonempty history capability gate can reject it.
    {disabled, disabled_journal} = client(ctx, false)
    disabled_request = Map.delete(request, "path")
    rollouts = Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl"))

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(disabled, "thread/resume", disabled_request)

    assert count(disabled_journal, "thread/resume") == 0

    assert wire_error(disabled, "thread/resume", disabled_request) == %{
             "code" => -32_600,
             "message" => "thread/resume.history requires experimentalApi capability"
           }

    assert last_params(disabled_journal, "thread/resume") == disabled_request
    assert call(disabled, "thread/loaded/list", %{})["data"] == []
    assert Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl")) == rollouts
    assert call(disabled, "thread/read", source_query)["thread"] == source
    assert File.read!(source_path) == source_bytes
    assert_no_import_work(ctx, disabled, source_requests)
    assert :ok = Session.close(disabled)

    response = call(pid, "thread/resume", request)
    assert count(journal, "thread/resume") == 1
    assert last_params(journal, "thread/resume") == request
    imported = Map.fetch!(response, "thread")
    id = Map.fetch!(imported, "id")
    path = Map.fetch!(imported, "path")
    assert is_binary(id) and id != "" and id != source_id
    assert path != source_path
    assert String.starts_with?(path, Path.join(ctx.root, "codex/sessions/"))
    assert File.regular?(path)
    assert Map.fetch!(imported, "preview") == text
    assert Map.fetch!(imported, "status") == %{"type" => "idle"}
    assert Map.fetch!(imported, "ephemeral") == false
    assert Map.fetch!(imported, "historyMode") == "paginated"
    assert Map.fetch!(imported, "turns") == []

    for field <- ~w(name projectId parentThreadId forkedFromId),
        do: assert(Map.fetch!(imported, field) == nil)

    assert_default_session_settings(ctx, response, "low")
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]
    assert_no_import_work(ctx, pid, source_requests)

    await(
      fn ->
        bytes = File.read!(path)
        String.ends_with?(bytes, "\n") and length(String.split(bytes, "\n", trim: true)) == 3
      end,
      "supplied history and effective settings flush"
    )

    imported_prefix = File.read!(path)
    [meta, item, _checkpoint] = rollout_records(imported_prefix)
    assert meta["type"] == "session_meta"
    assert Map.fetch!(meta, "ordinal") == 0
    assert meta["payload"]["id"] == id
    assert meta["payload"]["session_id"] == id
    assert meta["payload"]["cwd"] == ctx.workspace
    assert meta["payload"]["history_mode"] == "paginated"

    for field <- ~w(forked_from_id forked_from_ordinal_exclusive parent_thread_id),
        do: refute(Map.has_key?(meta["payload"], field))

    item_id = item["payload"]["id"]
    assert is_binary(item_id) and item_id != ""

    assert Map.delete(item, "timestamp") == %{
             "ordinal" => 1,
             "type" => "response_item",
             "payload" => Map.put(message, "id", item_id)
           }

    prefix = imported_prefix |> String.split("\n", trim: true) |> Enum.take(2)
    assert_resume_rollout(ctx, path, Enum.join(prefix, "\n") <> "\n", id, 1, "low", 2)
    assert call(pid, "thread/read", source_query)["thread"] == source
    assert File.read!(source_path) == source_bytes
    refute File.exists?(missing_path)

    replacement = request |> Map.delete("path") |> Map.put("threadId", id)
    current_rollouts = Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl"))

    assert wire_error(pid, "thread/resume", replacement) == %{
             "code" => -32_600,
             "message" => "cannot resume thread #{id} with history while it is already running"
           }

    assert last_params(journal, "thread/resume") == replacement
    assert count(journal, "thread/resume") == 2
    assert call(pid, "thread/loaded/list", %{})["data"] == [id]
    assert Path.wildcard(Path.join(ctx.root, "codex/sessions/**/*.jsonl")) == current_rollouts
    assert File.read!(path) == imported_prefix
    assert_no_import_work(ctx, pid, source_requests)

    turn = start_turn(pid, id, 911, %{})
    assert last_params(journal, "turn/start") == turn_params(id, 911, %{})
    assert count(journal, "turn/start") == 1
    assert_default_completion(finish(pid, turn), id, turn)
    assert [^source_request, imported_request] = read(ctx, "requests.json")

    user_texts =
      for input <- imported_request["input"],
          input["role"] == "user",
          content <- input["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == text)) == 1
    assert Enum.count(user_texts, &(&1 == "synthetic:defaults:911")) == 1
    refute Enum.any?(user_texts, &String.contains?(&1, "synthetic:defaults:910"))

    assert %{
             "thread_id" => ^id,
             "turn_id" => ^turn,
             "history_initialization" => "supplied_history"
           } = JSON.decode!(imported_request["client_metadata"]["x-codex-turn-metadata"])

    assert :ok = Session.close(pid)
    restart_owned_native(ctx)
    durable = File.read!(path)
    assert String.starts_with?(durable, imported_prefix)
    assert String.ends_with?(durable, "\n")
    assert Enum.filter(rollout_records(durable), &(&1["payload"]["id"] == item_id)) == [item]
    {cold, cold_journal} = client(ctx, true)
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    saved = call(cold, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert saved["id"] == id
    assert saved["path"] == path
    # Stored preview follows canonical user events, unlike the import response snapshot.
    assert saved["preview"] == "synthetic:defaults:911"
    assert saved["status"] == %{"type" => "notLoaded"}
    # Plain imported ResponseItems have no UI turn boundary; the explicit turn does.
    assert [saved_turn] = saved["turns"]
    assert_default_text_turn(saved_turn, turn, 911)
    assert call(cold, "thread/read", source_query)["thread"] == source
    assert File.read!(source_path) == source_bytes
    assert call(cold, "thread/loaded/list", %{})["data"] == []
    assert count(cold_journal, "thread/resume") == 0
    assert count(cold_journal, "turn/start") == 0
    assert_no_import_work(ctx, cold, [source_request, imported_request])
    refute File.exists?(missing_path)
  end

  test "cold resume normalizes an empty path before experimental negotiation", ctx do
    {creator, _} = client(ctx, true)
    thread = start(creator, ctx, %{"historyMode" => "legacy"})["thread"]
    id = thread["id"]
    name = "Owned empty-path resume"
    assert call(creator, "thread/name/set", %{"threadId" => id, "name" => name}) == %{}
    saved = call(creator, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert saved["id"] == id
    assert saved["name"] == name
    assert saved["historyMode"] == "legacy"
    assert saved["turns"] == []
    assert File.regular?(saved["path"])
    assert :ok = Session.close(creator)
    restart_owned_native(ctx)
    rollout = File.read!(saved["path"])
    assert [meta] = rollout |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert meta["type"] == "session_meta"
    assert meta["payload"]["id"] == id
    assert meta["payload"]["history_mode"] == "legacy"
    assert String.ends_with?(rollout, "\n")

    cases =
      for negotiation <- [:absent, false],
          extra <- [%{}, %{"path" => nil}, %{"path" => ""}],
          do: {negotiation, extra}

    for {{negotiation, extra}, resume_count} <- Enum.with_index(cases, 1) do
      previous_rollout = File.read!(saved["path"])
      {pid, journal} = client(ctx, negotiation)
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      assert {:ok, _} = Session.drain(pid)
      active = %{"threadId" => id, "path" => saved["path"]}
      before = count(journal, "thread/resume")

      assert {:error, %Error{code: :experimental_api_required}} =
               Session.request(pid, "thread/resume", active)

      assert count(journal, "thread/resume") == before

      assert wire_error(pid, "thread/resume", active) == %{
               "code" => -32_600,
               "message" => "thread/resume.path requires experimentalApi capability"
             }

      assert last_params(journal, "thread/resume") == active
      assert call(pid, "thread/loaded/list", %{})["data"] == []
      assert {:ok, rejected_events} = Session.drain(pid)

      refute Enum.any?(
               rejected_events,
               &(&1.wire["method"] in ["thread/started", "turn/started"])
             )

      assert_resume_rollout(ctx, saved["path"], rollout, id, resume_count - 1)
      assert File.read!(saved["path"]) == previous_rollout

      request = Map.merge(%{"threadId" => id}, extra)
      resumed = call(pid, "thread/resume", request)["thread"]
      assert last_params(journal, "thread/resume") == request

      assert Map.has_key?(last_params(journal, "thread/resume"), "path") ==
               Map.has_key?(extra, "path")

      assert resumed["id"] == id
      assert resumed["name"] == name
      assert resumed["path"] == saved["path"]
      assert resumed["historyMode"] == "legacy"
      assert resumed["turns"] == []
      assert {:ok, resume_events} = Session.drain(pid)
      refute Enum.any?(resume_events, &(&1.kind == :server_request))

      refute Enum.any?(resume_events, fn event ->
               event.wire["method"] in [
                 "turn/started",
                 "turn/completed",
                 "item/started",
                 "item/completed"
               ]
             end)

      assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
               Session.status(pid)

      assert :ok = Session.close(pid)

      # SessionConfigured can precede the resume checkpoint. Wait for its full
      # newline-delimited record before stopping the owned writer, then reread.
      await(
        fn ->
          bytes = File.read!(saved["path"])

          String.starts_with?(bytes, rollout) and String.ends_with?(bytes, "\n") and
            length(String.split(bytes, "\n", trim: true)) == resume_count + 1
        end,
        "cold resume settings checkpoint"
      )

      restart_owned_native(ctx)
      assert_resume_rollout(ctx, saved["path"], rollout, id, resume_count)
      durable = File.read!(saved["path"])
      assert binary_part(durable, 0, byte_size(previous_rollout)) == previous_rollout
      assert read(ctx, "requests.json") == []
    end
  end

  test "environment null inherits the local default while an empty list selects none", ctx do
    local = [
      %{
        "environmentId" => "local",
        "cwd" => ctx.workspace,
        "runtimeWorkspaceRoots" => [ctx.workspace]
      }
    ]

    for negotiation <- [:absent, false, true] do
      {pid, journal} = client(ctx, negotiation)

      for extra <- [%{}, %{"environments" => nil}] do
        thread = start(pid, ctx, extra)["thread"]
        assert Map.fetch!(thread, "environments") == local
        assert thread["turns"] == []
        assert last_params(journal, "thread/start") == params(ctx, extra)

        assert Map.has_key?(last_params(journal, "thread/start"), "environments") ==
                 Map.has_key?(extra, "environments")

        loaded = call(pid, "thread/read", %{"threadId" => thread["id"], "includeTurns" => false})
        assert Map.fetch!(loaded["thread"], "environments") == local
      end

      if negotiation == true do
        extra = %{"environments" => []}
        thread = start(pid, ctx, extra)["thread"]
        assert Map.fetch!(thread, "environments") == []
        assert thread["turns"] == []
        assert last_params(journal, "thread/start") == params(ctx, extra)
        loaded = call(pid, "thread/read", %{"threadId" => thread["id"], "includeTurns" => false})
        assert Map.fetch!(loaded["thread"], "environments") == []
      else
        reject_gate(pid, ctx, journal, "environments", [])
        assert last_params(journal, "thread/start") == params(ctx, %{"environments" => []})
      end

      assert :ok = Session.close(pid)
      assert read(ctx, "requests.json") == []
    end
  end

  test "session start source defaults to new while clear marks only its new runtime", ctx do
    {pid, journal} = client(ctx, false)

    cases = [
      {%{}, false, "new", 920},
      {%{"sessionStartSource" => nil}, true, "new", 921},
      {%{"sessionStartSource" => "startup"}, true, "new", 922},
      {%{"sessionStartSource" => "clear"}, true, "cleared", 923}
    ]

    {snapshots, requests} =
      Enum.reduce(cases, {[], []}, fn {extra, present, initialization, marker},
                                      {previous, requests} ->
        response = start(pid, ctx, extra)
        assert last_params(journal, "thread/start") == params(ctx, extra)

        assert Map.has_key?(last_params(journal, "thread/start"), "sessionStartSource") ==
                 present

        thread = Map.fetch!(response, "thread")
        id = Map.fetch!(thread, "id")
        path = Map.fetch!(thread, "path")
        assert is_binary(id) and id != ""
        assert is_binary(path) and path != ""
        assert String.starts_with?(path, Path.join(ctx.root, "codex/sessions/"))
        refute Enum.any?(previous, &(&1.id == id or &1.path == path))
        assert Map.fetch!(thread, "status") == %{"type" => "idle"}
        assert Map.fetch!(thread, "ephemeral") == false
        assert Map.fetch!(thread, "historyMode") == "paginated"
        assert Map.fetch!(thread, "turns") == []

        for field <- ~w(name projectId parentThreadId forkedFromId),
            do: assert(Map.fetch!(thread, field) == nil)

        assert_default_session_settings(ctx, response, "low")

        assert Enum.sort(call(pid, "thread/loaded/list", %{})["data"]) ==
                 Enum.sort([id | Enum.map(previous, & &1.id)])

        # Clear starts a separate root; it cannot erase the previously completed roots.
        for saved <- previous do
          assert call(pid, "thread/read", %{
                   "threadId" => saved.id,
                   "includeTurns" => true
                 })["thread"] == saved.thread

          assert File.read!(saved.path) == saved.bytes
        end

        assert_no_import_work(ctx, pid, requests)
        turn = start_turn(pid, id, marker, %{})
        assert last_params(journal, "turn/start") == turn_params(id, marker, %{})
        assert_default_completion(finish(pid, turn), id, turn)
        actual_requests = read(ctx, "requests.json")
        assert length(actual_requests) == length(requests) + 1
        assert Enum.take(actual_requests, length(requests)) == requests
        request = List.last(actual_requests)

        user_texts =
          for input <- request["input"],
              input["role"] == "user",
              content <- input["content"],
              content["type"] == "input_text",
              do: content["text"]

        assert Enum.count(user_texts, &(&1 == "synthetic:defaults:#{marker}")) == 1

        for other <- 920..923, other != marker do
          refute Enum.any?(user_texts, &String.contains?(&1, "synthetic:defaults:#{other}"))
        end

        assert %{
                 "thread_id" => ^id,
                 "turn_id" => ^turn,
                 "history_initialization" => ^initialization
               } = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])

        saved = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
        assert saved["id"] == id
        assert saved["path"] == path
        assert saved["preview"] == "synthetic:defaults:#{marker}"
        assert [saved_turn] = saved["turns"]
        assert_default_text_turn(saved_turn, turn, marker)
        assert File.regular?(path)
        bytes = File.read!(path)
        assert String.ends_with?(bytes, "\n")
        assert_no_import_work(ctx, pid, actual_requests)
        snapshot = %{id: id, path: path, thread: saved, bytes: bytes}
        {previous ++ [snapshot], actual_requests}
      end)

    assert length(snapshots) == 4
    assert length(requests) == 4
    assert count(journal, "thread/start") == 4
    assert count(journal, "turn/start") == 4
    assert count(journal, "thread/resume") == 0

    assert Enum.sort(call(pid, "thread/loaded/list", %{})["data"]) ==
             Enum.sort(Enum.map(snapshots, & &1.id))

    for saved <- snapshots do
      assert call(pid, "thread/read", %{
               "threadId" => saved.id,
               "includeTurns" => true
             })["thread"] == saved.thread

      assert File.read!(saved.path) == saved.bytes
    end

    assert_no_import_work(ctx, pid, requests)
    assert :ok = Session.close(pid)
  end

  test "thread personality defaults inherit none while named values preserve catalog instructions",
       ctx do
    literal = """
    Owned catalog intro λ
    # Personality
    Owned fixed style {{ personality }}
    ## Details
    Owned removable detail.
    # Rules
    Owned stable rule.
    """

    stripped = """
    Owned catalog intro λ
    # Rules
    Owned stable rule.
    """

    config_path = Path.join(ctx.root, "codex/config.toml")
    config = File.read!(config_path)
    refute Regex.match?(~r/^\s*(personality|instructions|model_instructions_file)\s*=/m, config)
    catalog_path = Path.join(ctx.root, "codex/models.json")
    catalog = read(ctx, "codex/models.json")
    assert length(catalog["models"]) == 1

    catalog =
      put_in(
        catalog,
        ["models", Access.at(0), "model_messages", "instructions_template"],
        literal
      )

    File.write!(catalog_path, JSON.encode!(catalog))
    File.write!(config_path, "personality = \"none\"\n" <> config)
    restart_owned_native(ctx)
    {pid, journal} = client(ctx, false)
    assert read(ctx, "requests.json") == []

    cases = [
      {%{}, false, stripped},
      {%{"personality" => nil}, true, stripped},
      {%{"personality" => "none"}, true, stripped},
      {%{"personality" => "friendly"}, true, literal},
      {%{"personality" => "pragmatic"}, true, literal}
    ]

    ids =
      for {{extra, present, expected}, marker} <- Enum.with_index(cases, 930) do
        requests = read(ctx, "requests.json")
        response = start(pid, ctx, extra)
        assert last_params(journal, "thread/start") == params(ctx, extra)
        assert Map.has_key?(last_params(journal, "thread/start"), "personality") == present
        assert_default_session_settings(ctx, response, "low")
        thread = response["thread"]["id"]
        assert is_binary(thread) and thread != ""
        assert response["thread"]["turns"] == []
        assert response["thread"]["status"] == %{"type" => "idle"}
        assert_no_import_work(ctx, pid, requests)

        turn = start_turn(pid, thread, marker, %{})
        assert last_params(journal, "turn/start") == turn_params(thread, marker, %{})
        assert_default_completion(finish(pid, turn), thread, turn)
        actual = read(ctx, "requests.json")
        assert length(actual) == marker - 929
        assert Enum.take(actual, length(requests)) == requests
        request = List.last(actual)
        assert request["model"] == "mock-model"
        refute Map.has_key?(request, "instructions")

        assert %{
                 "type" => "message",
                 "role" => "developer",
                 "content" => [%{"type" => "input_text", "text" => ^expected}]
               } = hd(request["input"])

        user_texts =
          for input <- request["input"],
              input["role"] == "user",
              content <- input["content"],
              content["type"] == "input_text",
              do: content["text"]

        assert Enum.count(user_texts, &(&1 == "synthetic:defaults:#{marker}")) == 1

        for other <- 930..934, other != marker do
          refute Enum.any?(user_texts, &String.contains?(&1, "synthetic:defaults:#{other}"))
        end

        saved =
          call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

        assert [saved_turn] = saved["turns"]
        assert_default_text_turn(saved_turn, turn, marker)
        assert_no_import_work(ctx, pid, actual)
        thread
      end

    assert length(Enum.uniq(ids)) == 5
    assert Enum.sort(call(pid, "thread/loaded/list", %{})["data"]) == Enum.sort(ids)
    assert count(journal, "thread/start") == 5
    assert count(journal, "turn/start") == 5
    assert length(read(ctx, "requests.json")) == 5
    assert :ok = Session.close(pid)
  end

  test "omitted section lists all while explicit null lists only unsectioned threads", ctx do
    {pid, journal} = client(ctx, true)
    unsectioned = start(pid, ctx)["thread"]["id"]
    selected = start(pid, ctx)["thread"]["id"]
    refute unsectioned == selected

    for {id, marker} <- [{unsectioned, 701}, {selected, 702}] do
      turn = start_turn(pid, id, marker, %{})
      finish(pid, turn)
      assert last_params(journal, "turn/start") == turn_params(id, marker, %{})

      assert call(pid, "thread/name/set", %{
               "threadId" => id,
               "name" => "Owned section #{marker}"
             }) == %{}
    end

    section = call(pid, "threadSection/create", %{"name" => "Owned semantic section"})["section"]
    assert is_binary(section["id"]) and section["id"] != ""
    assert section["name"] == "Owned semantic section"

    assert call(pid, "thread/section/move", %{
             "threadId" => selected,
             "sectionId" => section["id"]
           }) == %{}

    assert_section_filter_variants(pid, journal, ctx, unsectioned, selected, section)

    paths =
      for id <- [unsectioned, selected] do
        thread = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => false})["thread"]
        assert thread["preview"] != ""
        assert File.regular?(thread["path"])
        thread["path"]
      end

    assert length(read(ctx, "requests.json")) == 2
    requests = read(ctx, "requests.json")
    assert :ok = Session.close(pid)
    rollouts = Map.new(paths, &{&1, File.read!(&1)})
    restart_owned_native(ctx)

    for negotiation <- [:absent, false] do
      {cold, cold_journal} = client(ctx, negotiation)
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      assert_section_filter_variants(cold, cold_journal, ctx, unsectioned, selected, section)
      assert call(cold, "thread/loaded/list", %{})["data"] == []
      sections = call(cold, "threadSection/list", %{"limit" => 100})["data"]
      assert Enum.find(sections, &(&1["id"] == section["id"])) == section
      assert :ok = Session.close(cold)
      assert read(ctx, "requests.json") == requests
      for {path, bytes} <- rollouts, do: assert(File.read!(path) == bytes)
    end
  end

  defp assert_default_completion(events, thread, turn) do
    assert Enum.any?(events, fn event ->
             event.wire["method"] == "turn/completed" and
               event.wire["params"]["threadId"] == thread and
               event.wire["params"]["turn"]["id"] == turn and
               event.wire["params"]["turn"]["status"] == "completed"
           end)

    assert Enum.any?(events, fn event ->
             event.wire["method"] == "item/completed" and
               event.wire["params"]["threadId"] == thread and
               event.wire["params"]["turnId"] == turn and
               event.wire["params"]["item"]["type"] == "agentMessage" and
               event.wire["params"]["item"]["text"] == "Owned default response"
           end)
  end

  defp assert_default_text_turn(turn, id, marker) do
    assert turn["id"] == id
    assert turn["status"] == "completed"
    assert Enum.map(turn["items"], & &1["type"]) == ["userMessage", "agentMessage"]
    [user, assistant] = turn["items"]

    assert user["content"] == [
             %{
               "type" => "text",
               "text" => "synthetic:defaults:#{marker}",
               "text_elements" => []
             }
           ]

    assert assistant["text"] == "Owned default response"
  end

  defp assert_no_import_work(ctx, pid, requests) do
    assert read(ctx, "requests.json") == requests

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/started",
               "item/completed"
             ]
           end)
  end

  defp rollout_records(bytes),
    do: bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp assert_default_session_settings(ctx, response, reasoning_effort) do
    for {field, expected} <- %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => ctx.workspace,
          "approvalPolicy" => "on-request",
          "approvalsReviewer" => "user",
          "serviceTier" => "flex",
          "reasoningEffort" => reasoning_effort,
          "sandbox" => %{"type" => "readOnly", "networkAccess" => false}
        },
        do: assert(Map.fetch!(response, field) == expected)
  end

  defp assert_idle_without_work(ctx, pid) do
    assert read(ctx, "requests.json") == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.kind == :server_request))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in [
               "turn/started",
               "turn/completed",
               "item/started",
               "item/completed"
             ]
           end)
  end

  defp assert_section_filter_variants(pid, journal, ctx, unsectioned, selected, section) do
    base = %{
      "limit" => 10,
      "cwd" => ctx.workspace,
      "modelProviders" => ["fixture"],
      "sortKey" => "created_at"
    }

    for {extra, expected} <- [
          {%{}, [unsectioned, selected]},
          {%{"sectionId" => nil}, [unsectioned]},
          {%{"sectionId" => section["id"]}, [selected]}
        ] do
      query = Map.merge(base, extra)
      result = call(pid, "thread/list", query)
      assert last_params(journal, "thread/list") == query

      assert Map.has_key?(last_params(journal, "thread/list"), "sectionId") ==
               Map.has_key?(extra, "sectionId")

      assert Enum.sort(Enum.map(result["data"], & &1["id"])) == Enum.sort(expected)
      assert Map.fetch!(result, "nextCursor") == nil

      for thread <- result["data"], do: assert_section_projection(thread, selected, section)
    end
  end

  defp assert_section_projection(thread, selected, section) do
    expected_section = if thread["id"] == selected, do: section, else: nil
    assert Map.fetch!(thread, "section") == expected_section
    assert is_binary(thread["preview"]) and thread["preview"] != ""
  end

  defp restart_owned_native(ctx) do
    previous = read(ctx, "state.json")
    generation = previous["generation"] + 1
    assert {:ok, _} = Stdio.send(ctx.owner, JSON.encode!(%{"restart" => true}))

    await(
      fn ->
        state = read(ctx, "state.json")
        state["ready"] and state["generation"] == generation
      end,
      "explicit owned native restart"
    )

    for os_pid <- previous["native_pids"], do: refute(File.exists?("/proc/#{os_pid}"))
  end

  defp assert_resume_rollout(
         ctx,
         path,
         prefix,
         id,
         expected_count,
         reasoning_effort \\ nil,
         first_ordinal \\ nil
       ) do
    bytes = File.read!(path)
    assert byte_size(bytes) >= byte_size(prefix)
    assert binary_part(bytes, 0, byte_size(prefix)) == prefix
    assert String.ends_with?(bytes, "\n")
    suffix = binary_part(bytes, byte_size(prefix), byte_size(bytes) - byte_size(prefix))
    records = suffix |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert length(records) == expected_count

    expected = %{
      "type" => "event_msg",
      "payload" => %{
        "type" => "thread_settings_applied",
        "thread_id" => id,
        "thread_settings" => %{
          "model" => "mock-model",
          "model_provider_id" => "fixture",
          "service_tier" => "flex",
          "approval_policy" => "on-request",
          "approvals_reviewer" => "user",
          "permission_profile" => %{
            "type" => "managed",
            "file_system" => %{
              "type" => "restricted",
              "entries" => [
                %{
                  "path" => %{"type" => "special", "value" => %{"kind" => "root"}},
                  "access" => "read"
                }
              ]
            },
            "network" => "restricted"
          },
          "cwd" => ctx.workspace,
          "runtime_workspace_roots" => [ctx.workspace],
          "reasoning_summary" => "concise",
          "collaboration_mode" => %{
            "mode" => "default",
            "settings" => %{
              "model" => "mock-model",
              "reasoning_effort" => reasoning_effort,
              "developer_instructions" => nil
            }
          },
          "disabled_plugin_ids" => []
        }
      }
    }

    expected =
      if is_nil(reasoning_effort) do
        expected
      else
        put_in(expected, ["payload", "thread_settings", "reasoning_effort"], reasoning_effort)
      end

    for {record, index} <- Enum.with_index(records) do
      expected_record =
        if is_nil(first_ordinal),
          do: expected,
          else: Map.put(expected, "ordinal", first_ordinal + index)

      assert Map.delete(record, "timestamp") == expected_record
      assert {:ok, _timestamp, 0} = DateTime.from_iso8601(Map.fetch!(record, "timestamp"))
    end
  end

  defp client(ctx, negotiation) do
    name = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    journal = Path.join(ctx.root, "sent-" <> name <> ".jsonl")
    File.write!(journal, "")

    {:ok, pid} =
      Session.start_link(
        transport: {DefaultGateRecordingUDS, [socket_path: ctx.socket, sent_path: journal]}
      )

    on_exit(fn ->
      if Process.alive?(pid) do
        try do
          assert :ok = Session.close(pid)
        catch
          :exit, {:noproc, _} -> :ok
        end
      end
    end)

    capabilities = if negotiation == :absent, do: %{}, else: %{"experimentalApi" => negotiation}

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_owned_defaults", "version" => "0.1.0"},
               capabilities
             )

    {pid, journal}
  end

  defp reject_gate(pid, ctx, journal, field, value) do
    loaded = call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort()
    assert {:ok, _} = Session.drain(pid)
    before = count(journal, "thread/start")

    assert {:error, %Error{code: :experimental_api_required}} =
             Session.request(pid, "thread/start", params(ctx, %{field => value}))

    assert count(journal, "thread/start") == before

    assert wire_error(pid, "thread/start", params(ctx, %{field => value})) == %{
             "code" => -32_600,
             "message" => "thread/start.#{field} requires experimentalApi capability"
           }

    assert call(pid, "thread/loaded/list", %{})["data"] |> Enum.sort() == loaded
    assert {:ok, events} = Session.drain(pid)
    refute Enum.any?(events, &(&1.wire["method"] in ["thread/started", "turn/started"]))
  end

  defp params(ctx, extra),
    do:
      Map.merge(
        %{
          "cwd" => ctx.workspace,
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request"
        },
        extra
      )

  defp start(pid, ctx, extra \\ %{}), do: call(pid, "thread/start", params(ctx, extra))

  defp turn_params(thread, marker, extra),
    do:
      Map.merge(
        %{
          "threadId" => thread,
          "input" => [%{"type" => "text", "text" => "synthetic:defaults:#{marker}"}]
        },
        extra
      )

  defp start_turn(pid, thread, marker, extra),
    do: call(pid, "turn/start", turn_params(thread, marker, extra))["turn"]["id"]

  defp finish(pid, turn), do: finish(pid, turn, [], now() + 15_000)

  defp finish(pid, turn, acc, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    refute Enum.any?(incoming, &(&1.kind == :server_request)), "no tool or approval is authorized"
    acc = acc ++ incoming

    completed =
      Enum.find(
        acc,
        &(get_in(&1, [:wire, "method"]) == "turn/completed" and
            get_in(&1, [:wire, "params", "turn", "id"]) == turn)
      )

    if completed do
      assert completed.wire["params"]["turn"]["status"] == "completed"
      acc
    else
      assert now() < deadline, "owned assistant turn deadline"

      receive do
      after
        10 -> :ok
      end

      finish(pid, turn, acc, deadline)
    end
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params)
    result
  end

  defp wire_error(pid, method, params) do
    assert {:error, %Error{code: :upstream_error, wire: %{"error" => error}}} =
             Session.request(pid, method, params, validation: :wire)

    error
  end

  defp sent(path),
    do: path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  defp count(path, method), do: Enum.count(sent(path), &(&1["method"] == method))

  defp last_params(path, method),
    do:
      sent(path) |> Enum.filter(&(&1["method"] == method)) |> List.last() |> Map.fetch!("params")

  defp read(ctx, name), do: ctx.root |> Path.join(name) |> File.read!() |> JSON.decode!()
  defp now, do: System.monotonic_time(:millisecond)
  defp await(fun, label), do: await(fun, label, now() + 10_000)

  defp await(fun, label, deadline) do
    if fun.() do
      :ok
    else
      assert now() < deadline, label

      receive do
      after
        10 -> :ok
      end

      await(fun, label, deadline)
    end
  end
end
