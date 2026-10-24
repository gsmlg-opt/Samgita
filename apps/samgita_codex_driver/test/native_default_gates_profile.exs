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

  defp assert_resume_rollout(ctx, path, prefix, id, expected_count) do
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
              "reasoning_effort" => nil,
              "developer_instructions" => nil
            }
          },
          "disabled_plugin_ids" => []
        }
      }
    }

    for record <- records do
      assert Map.delete(record, "timestamp") == expected
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
