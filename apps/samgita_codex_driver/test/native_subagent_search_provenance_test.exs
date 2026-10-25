defmodule SamgitaCodexDriver.NativeSubagentSearchProvenanceTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @script Path.expand("../../../scripts/codex/subagent_search_provenance_fixture.py", __DIR__)
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @needle "Owned source provenance"
  @root_marker @needle <> " root λ"
  @child_marker @needle <> " child 🙂"
  @child_path "/root/search_child"
  @child_answer @child_marker <> " done"
  @root_answer "Owned source provenance root done"

  setup tags do
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha

    TurnFixture.configure_model(ctx, %{
      "multi_agent_version" => "v2",
      "default_reasoning_level" => "medium",
      "supported_reasoning_levels" => [
        %{"effort" => "medium", "description" => "Owned local medium effort"}
      ]
    })

    rg = System.find_executable("rg")
    assert is_binary(rg) and File.regular?(rg), "BLOCKED_ENV: ripgrep required"
    File.ln_s!(rg, Path.join(ctx.fixture.bin, "rg"))

    inputs =
      Map.new(["config.toml", "turn-models.json"], fn name ->
        path = Path.join(ctx.fixture.codex_home, name)
        {path, snapshot(path)}
      end)

    Map.put(ctx, :inputs, inputs)
  end

  test "native child provenance survives archived source-filtered search and first cold search",
       ctx do
    warm = start(ctx)
    warm_native = native_id(warm)

    root =
      call(warm, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => ctx.fixture.workspace,
        "historyMode" => "paginated",
        "ephemeral" => false
      })["thread"]["id"]

    assert is_binary(root) and root != ""
    assert ModelFixture.requests(ctx.fixture) == []

    turn =
      call(warm, "turn/start", %{
        "threadId" => root,
        "input" => [%{"type" => "text", "text" => @root_marker}],
        "effort" => "medium"
      })["turn"]["id"]

    events = collect(warm, root, turn, [], deadline(20_000))

    # Resolve generated child identity from a separate native management query.
    assert %{"data" => [child], "nextCursor" => nil} =
             call(warm, "thread/list", %{
               "parentThreadId" => root,
               "sourceKinds" => ["subAgentThreadSpawn"],
               "sortKey" => "created_at",
               "limit" => 100,
               "useStateDbOnly" => true
             })

    child_id = Map.fetch!(child, "id")
    assert is_binary(child_id) and child_id != "" and child_id != root
    assert Map.fetch!(child, "parentThreadId") == root
    assert Map.fetch!(child, "preview") == ""
    expected_source = source(root)
    assert Map.fetch!(child, "source") === expected_source
    root_saved = assert_history(warm, root, @root_answer)
    child_saved = assert_history(warm, child_id, @child_answer)
    assert [%{"id" => ^turn, "rootTurnId" => ^turn}] = root_saved["turns"]
    assert [%{"id" => child_turn, "rootTurnId" => ^turn}] = child_saved["turns"]

    assert [
             %{
               "threadId" => ^child_id,
               "turn" => %{
                 "id" => ^child_turn,
                 "rootTurnId" => ^turn,
                 "status" => "completed",
                 "error" => nil
               }
             },
             %{
               "threadId" => ^root,
               "turn" => %{
                 "id" => ^turn,
                 "rootTurnId" => ^turn,
                 "status" => "completed",
                 "error" => nil
               }
             }
           ] = params(events, "turn/completed")

    assert_provider(ctx, root, child_id)
    assert Map.fetch!(child_saved, "preview") == ""

    # Active global discovery requires a preview. The native MAv2 agent message
    # creates none, although relation listing and stored content are available.
    assert_active_child_search_empty(warm)
    assert_interactive_search(warm, root, child_id)
    child_bytes = snapshot(child_saved["path"])

    retained =
      Map.merge(ctx.inputs, %{
        root_saved["path"] => snapshot(root_saved["path"]),
        ctx.fixture.requests => snapshot(ctx.fixture.requests),
        observed(ctx) => snapshot(observed(ctx))
      })

    # Archival is an explicit native lifecycle operation. It preserves rollout
    # bytes, and archived discovery includes threads with an empty preview.
    assert call(warm, "thread/archive", %{"threadId" => child_id}) === %{}
    archived_child = assert_history(warm, child_id, @child_answer)
    archived_path = Map.fetch!(archived_child, "path")

    assert archived_path ==
             Path.join([
               ctx.fixture.codex_home,
               "archived_sessions",
               Path.basename(child_saved["path"])
             ])

    refute File.exists?(child_saved["path"])
    assert snapshot(archived_path) === child_bytes
    assert archived_child["turns"] === child_saved["turns"]
    assert Map.fetch!(archived_child, "preview") == ""
    retained = Map.put(retained, archived_path, child_bytes)

    assert_child_search(warm, root, child_id, archived_path, expected_source)
    assert_active_child_search_empty(warm)
    assert_interactive_search(warm, root, child_id)
    assert_retained(ctx, warm, retained)
    close(warm, warm_native)

    cold = start(ctx)
    cold_native = native_id(cold)
    refute cold_native == warm_native
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # First cold content read is search, without resume or history hydration.
    assert_child_search(cold, root, child_id, archived_path, expected_source)
    assert_active_child_search_empty(cold)
    assert_interactive_search(cold, root, child_id)
    assert call(cold, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert assert_history(cold, child_id, @child_answer)["turns"] === child_saved["turns"]
    assert assert_history(cold, root, @root_answer)["turns"] === root_saved["turns"]
    assert_retained(ctx, cold, retained)
    close(cold, cold_native)
    for {path, bytes} <- retained, do: assert(snapshot(path) === bytes)
  end

  defp source(root) do
    %{
      "subAgent" => %{
        "thread_spawn" => %{
          "agent_nickname" => "OwnedSearchChild",
          "agent_path" => @child_path,
          "agent_role" => "source_fixture",
          "depth" => 1,
          "parent_thread_id" => root
        }
      }
    }
  end

  defp assert_child_search(pid, root, child, path, expected_source) do
    assert %{"data" => [row], "nextCursor" => nil} =
             call(pid, "thread/search", %{
               "searchTerm" => @needle,
               "sourceKinds" => ["subAgentThreadSpawn"],
               "archived" => true,
               "limit" => 100
             })

    assert String.contains?(Map.fetch!(row, "snippet"), @child_marker)
    thread = Map.fetch!(row, "thread")
    assert Map.fetch!(thread, "id") == child
    # Global stored projections do not populate the relation-list parent field.
    # The nested native source retains the independently known parent identity.
    assert Map.fetch!(thread, "parentThreadId") == nil
    assert Map.fetch!(thread, "path") == path
    assert Map.fetch!(thread, "source") === expected_source
    assert get_in(thread, ["source", "subAgent", "thread_spawn", "parent_thread_id"]) == root
    assert Map.fetch!(thread, "turns") === []
  end

  defp assert_active_child_search_empty(pid) do
    assert call(pid, "thread/search", %{
             "searchTerm" => @needle,
             "sourceKinds" => ["subAgentThreadSpawn"],
             "archived" => false,
             "limit" => 100
           }) === %{"data" => [], "nextCursor" => nil, "backwardsCursor" => nil}
  end

  defp assert_interactive_search(pid, root, child) do
    assert %{"data" => [row], "nextCursor" => nil} =
             call(pid, "thread/search", %{"searchTerm" => @needle, "limit" => 100})

    assert Map.fetch!(row, "snippet") == @root_marker
    assert row["thread"]["id"] == root
    refute row["thread"]["id"] == child
  end

  defp assert_history(pid, id, answer) do
    thread = call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"]
    assert Map.fetch!(thread, "id") == id
    assert Map.fetch!(thread, "historyMode") == "paginated"
    assert [%{"status" => "completed", "error" => nil, "items" => items}] = thread["turns"]
    assert [%{"text" => ^answer}] = Enum.filter(items, &(&1["type"] == "agentMessage"))
    path = Map.fetch!(thread, "path")
    assert is_binary(path) and File.regular?(path)
    thread
  end

  defp assert_provider(ctx, root, child) do
    requests = ModelFixture.requests(ctx.fixture)
    assert length(requests) == 4

    assert Enum.frequencies_by(requests, fn request ->
             assert Map.fetch!(request, "model") == "mock-model"
             assert request["reasoning"]["effort"] == "medium"
             metadata = JSON.decode!(request["client_metadata"]["x-codex-turn-metadata"])
             Map.fetch!(metadata, "thread_id")
           end) == %{root => 3, child => 1}

    assert JSON.decode!(File.read!(observed(ctx))) === %{
             "root_requests" => 3,
             "child_requests" => 1,
             "errors" => []
           }
  end

  defp assert_retained(ctx, pid, retained) do
    for {path, bytes} <- retained, do: assert(snapshot(path) === bytes)
    assert length(ModelFixture.requests(ctx.fixture)) == 4
    assert File.ls!(ctx.fixture.workspace) == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp collect(pid, root, turn, events, until) do
    assert {:ok, batch} = Session.drain(pid)
    events = events ++ batch
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert %{phase: :ready, gap: nil} = Session.status(pid)

    if Enum.any?(
         params(events, "turn/completed"),
         &(&1["threadId"] == root and &1["turn"]["id"] == turn)
       ) do
      events
    else
      assert System.monotonic_time(:millisecond) < until, "Native provenance turn deadline"

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected provenance event gap")
      after
        10 -> :ok
      end

      collect(pid, root, turn, events, until)
    end
  end

  defp params(events, method),
    do: for(event <- events, event.wire["method"] == method, do: event.wire["params"])

  defp call(pid, method, params) do
    id = "owned-provenance-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    result
  end

  defp observed(ctx), do: Path.join(ctx.root, "provenance-observed.json")

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    bytes
  end

  defp native_id(pid) do
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    native
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
  end

  defp start(ctx) do
    fixture = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: ctx.binary,
             args:
               NativeLaunchFixture.ordinary_args([
                 "-c",
                 ~s(approval_policy="never"),
                 "-c",
                 ~s(sandbox_mode="danger-full-access"),
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: fixture.workspace,
             inherit_env: [],
             env: %{
               "HOME" => fixture.home,
               "CODEX_HOME" => fixture.codex_home,
               "TMPDIR" => ctx.root,
               "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "RUST_LOG" => "off",
               "NO_COLOR" => "1"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_subagent_search", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    pid
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
