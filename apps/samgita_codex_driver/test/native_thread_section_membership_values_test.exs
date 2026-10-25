defmodule SamgitaCodexDriver.NativeThreadSectionMembershipValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  import TurnFixture, only: [call: 3, notification: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @instructions "Owned section membership fixture instructions."
  @answer "Deterministic local fixture answer"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in ["thread/section/move", "thread/list"] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 128 and byte_size(encoded) <= 4096 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [wire]))
          {:ok, next}
        end
      else
        {:error, SamgitaProtocolCodex.Error.new(:test_capture_overflow), state}
      end
    end

    @impl true
    def handle_info(message, state), do: Stdio.handle_info(message, state)
    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    ctx = TurnFixture.setup(tags)
    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "model_messages" => %{"instructions_template" => @instructions}
    })

    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      "cli_auth_credentials_store = \"ephemeral\"\n" <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native section moves append reorder transfer and remove only their named persisted members",
       ctx do
    pid = start(ctx)

    threads =
      for {label, index} <- Enum.with_index(~w(a b c d), 1), into: %{} do
        thread = TurnFixture.thread(ctx, pid, %{"historyMode" => "legacy"})
        marker = "Owned real section member #{label} λ"
        turn = TurnFixture.start_turn(pid, thread, [%{"type" => "text", "text" => marker}])
        complete_turn(pid, thread, turn, [], System.monotonic_time(:millisecond) + 20_000)
        requests = ModelFixture.requests(ctx.fixture)
        assert length(requests) == index
        assert_provider(List.last(requests), marker)
        saved = read(pid, thread)
        assert [%{"id" => ^turn, "status" => "completed"}] = saved["turns"]
        assert is_binary(saved["preview"]) and saved["preview"] != ""
        assert Map.fetch!(saved, "section") == nil
        {label, %{id: thread, turns: saved["turns"], preview: saved["preview"]}}
      end

    assert length(Enum.uniq(Enum.map(threads, fn {_label, row} -> row.id end))) == 4

    sections = %{
      "s" => create_section(pid, "Owned membership S"),
      "t" => create_section(pid, "Owned membership T")
    }

    assert sections["s"]["id"] != sections["t"]["id"]
    journal = File.read!(ctx.fixture.requests)
    assert_state(ctx, pid, threads, sections, {[], []}, journal)

    a = threads["a"].id
    b = threads["b"].id
    c = threads["c"].id
    s = sections["s"]["id"]
    t = sections["t"]["id"]

    # sectionId is required and nullable. Only beforeThreadId is optional:
    # omission/null append, while an actual member anchors insertion order.
    moves = [
      {%{"threadId" => a, "sectionId" => s}, {~w(a), []}},
      {%{"threadId" => b, "sectionId" => s, "beforeThreadId" => nil}, {~w(a b), []}},
      {%{"threadId" => c, "sectionId" => s, "beforeThreadId" => b}, {~w(a c b), []}},
      {%{"threadId" => a, "sectionId" => s, "beforeThreadId" => nil}, {~w(c b a), []}},
      {%{"threadId" => c, "sectionId" => t}, {~w(b a), ~w(c)}},
      {%{"threadId" => b, "sectionId" => nil}, {~w(a), ~w(c)}},
      {%{"threadId" => a, "sectionId" => nil, "beforeThreadId" => nil}, {[], ~w(c)}}
    ]

    final =
      Enum.reduce(Enum.with_index(moves, 1), pid, fn {{params, orders}, index}, current ->
        assert request(ctx, current, "thread/section/move", params) == %{}
        assert_state(ctx, current, threads, sections, orders, journal)

        if index == 5 do
          # Preserve nontrivial [B,A] order and C's independent destination in
          # another process, without loading/resuming or invoking the provider.
          replacement = restart(ctx, current)
          assert call(replacement, "thread/loaded/list", %{})["data"] == []
          assert_state(ctx, replacement, threads, sections, orders, journal)
          replacement
        else
          current
        end
      end)

    captures = Agent.get(ctx.capture, & &1)
    assert Enum.count(captures, &(&1["method"] == "thread/section/move")) == 7
    assert Enum.count(captures, &(&1["method"] == "thread/list")) == 54
    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert :ok = close(final)
  end

  defp create_section(pid, name) do
    section = call(pid, "threadSection/create", %{"name" => name})["section"]
    id = section["id"]
    assert is_binary(id) and id != ""
    assert section === %{"id" => id, "name" => name, "appearance" => nil}
    section
  end

  defp assert_state(ctx, pid, threads, sections, {s_order, t_order}, journal) do
    assigned =
      Map.new(
        for {key, labels} <- [{"s", s_order}, {"t", t_order}],
            label <- labels,
            do: {label, sections[key]}
      )

    all = ~w(a b c d)
    unsectioned = Enum.reject(all, &Map.has_key?(assigned, &1))

    base = %{
      "limit" => 10,
      "cwd" => ctx.fixture.workspace,
      "modelProviders" => ["fixture"],
      "sortKey" => "created_at"
    }

    for {extra, labels} <- [
          {%{}, all},
          {%{"sectionId" => nil}, unsectioned},
          {%{"sectionId" => sections["s"]["id"]}, s_order},
          {%{"sectionId" => sections["t"]["id"]}, t_order}
        ] do
      result = request(ctx, pid, "thread/list", Map.merge(base, extra))
      expected = Enum.map(labels, &threads[&1].id)
      assert Enum.sort(Enum.map(result["data"], & &1["id"])) == Enum.sort(expected)
      assert Map.fetch!(result, "nextCursor") == nil
      assert_projections(result["data"], threads, assigned)
    end

    # Section-position sorting requires a concrete section. Omitted/null
    # filters above use ordinary sorting; their global order is not prescribed.
    for {key, labels} <- [{"s", s_order}, {"t", t_order}] do
      params =
        Map.merge(base, %{
          "sectionId" => sections[key]["id"],
          "sortKey" => "section_position",
          "sortDirection" => "asc"
        })

      result = request(ctx, pid, "thread/list", params)
      assert Enum.map(result["data"], & &1["id"]) == Enum.map(labels, &threads[&1].id)
      assert Map.fetch!(result, "nextCursor") == nil
      assert_projections(result["data"], threads, assigned)
    end

    for {label, original} <- threads do
      saved = read(pid, original.id)
      assert Map.fetch!(saved, "section") === assigned[label]
      assert saved["turns"] === original.turns
      assert saved["preview"] == original.preview
    end

    assert File.read!(ctx.fixture.requests) == journal
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert File.read!(ctx.config) == ctx.config_bytes
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp assert_projections(data, threads, assigned) do
    by_id = Map.new(threads, fn {label, row} -> {row.id, label} end)

    for row <- data do
      label = Map.fetch!(by_id, row["id"])
      assert Map.fetch!(row, "section") === assigned[label]
      assert row["preview"] == threads[label].preview
    end
  end

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-section-membership-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
    result
  end

  defp assert_provider(request, marker) do
    assert request["model"] == "mock-model"

    assert %{
             "role" => "developer",
             "content" => [%{"type" => "input_text", "text" => @instructions}]
           } = hd(request["input"])

    user_texts =
      for item <- request["input"],
          item["role"] == "user",
          content <- item["content"],
          content["type"] == "input_text",
          do: content["text"]

    assert Enum.count(user_texts, &(&1 == marker)) == 1
  end

  # Functional completion only: the shared collector's separate approval
  # assertion is outside this unit and is deliberately not invoked.
  defp complete_turn(pid, thread, turn, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming

    found =
      notification(events, "turn/completed", fn params ->
        params["threadId"] == thread and params["turn"]["id"] == turn
      end)

    if found do
      assert %{"threadId" => ^thread, "turn" => %{"id" => ^turn, "status" => "completed"}} = found

      assert %{"item" => %{"type" => "agentMessage", "text" => @answer}} =
               notification(events, "item/completed", fn params ->
                 params["threadId"] == thread and params["turnId"] == turn and
                   params["item"]["type"] == "agentMessage"
               end)

      refute Enum.any?(events, &(&1.wire["method"] in ["error", "warning"]))
    else
      assert System.monotonic_time(:millisecond) < deadline, "native section member turn deadline"
      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during member turn")
      after
        20 -> :ok
      end

      complete_turn(pid, thread, turn, events, deadline)
    end
  end

  defp read(pid, thread),
    do: call(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true})["thread"]

  defp restart(ctx, pid) do
    previous = native_id(pid)
    assert :ok = close(pid)
    replacement = start(ctx)
    assert native_id(replacement) != previous
    replacement
  end

  defp close(pid) do
    native = native_id(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
  end

  defp native_id(pid) do
    id = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(id)
    assert hash(File.read!("/proc/#{id}/exe")) == @binary_sha
    id
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
             executable: ctx.binary,
             args: NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    %{transport: CaptureStdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_thread_section_membership", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
