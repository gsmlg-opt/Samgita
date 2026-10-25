defmodule SamgitaCodexDriver.NativeFuzzySessionValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  alias SamgitaProtocolCodex.Error
  import TurnFixture, only: [call: 3]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @updated "fuzzyFileSearch/sessionUpdated"
  @completed "fuzzyFileSearch/sessionCompleted"
  @subject "Owned fuzzy session λ"
  @control "Owned control session 雪"

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio

    @methods ~w(fuzzyFileSearch/sessionStart fuzzyFileSearch/sessionUpdate fuzzyFileSearch/sessionStop)

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      wire = JSON.decode!(encoded)

      if wire["method"] in @methods do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 64 and byte_size(encoded) <= 4096 do
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
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[features]\napps = false\nplugins = false\nrecommended_plugins = false\nshell_snapshot = false\n"
    )

    capture = start_supervised!({Agent, fn -> [] end})
    Map.merge(ctx, %{capture: capture, config: config, config_bytes: File.read!(config)})
  end

  test "native fuzzy session fields preserve roots queries identity replacement and stop effects",
       ctx do
    first = Path.join(ctx.fixture.workspace, "first")
    second = Path.join(ctx.fixture.workspace, "second")

    files = [
      {first, "needle_alpha.txt", "Owned first fuzzy input λ"},
      {second, "needle_bravo.txt", "Owned second fuzzy input 雪"}
    ]

    for {root, path, body} <- files do
      File.mkdir!(root)
      File.write!(Path.join(root, path), body)
    end

    both = [{first, "needle_alpha.txt"}, {second, "needle_bravo.txt"}]
    first_only = [{first, "needle_alpha.txt"}]
    second_only = [{second, "needle_bravo.txt"}]
    pid = start(ctx)
    start_session(ctx, pid, @subject, [first, second])
    start_session(ctx, pid, @control, [first])
    query(ctx, pid, @subject, "needle", both)
    query(ctx, pid, @control, "alpha", first_only)
    query(ctx, pid, @subject, "", [])
    query(ctx, pid, @subject, "needle_", both)

    # Replacing the exact opaque ID changes its roots. NEEDLE matches both
    # original files, so a single second-root result proves actual rebinding.
    start_session(ctx, pid, @subject, [second])
    query(ctx, pid, @subject, "NEEDLE", second_only)
    query(ctx, pid, @control, "needle_alpha", first_only)
    assert request(ctx, pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => @subject}) == %{}
    assert_missing(ctx, pid, @subject)
    query(ctx, pid, @control, "alpha.txt", first_only)

    for id <- [@subject, @control] do
      assert request(ctx, pid, "fuzzyFileSearch/sessionStop", %{"sessionId" => id}) == %{}
    end

    # Stop removes the map entry; it is not an absolute fence for already
    # spawned notification tasks. No quiet-window or no-more-events claim.
    captures = Agent.get(ctx.capture, & &1)
    assert Enum.count(captures, &(&1["method"] == "fuzzyFileSearch/sessionStart")) == 3
    assert Enum.count(captures, &(&1["method"] == "fuzzyFileSearch/sessionUpdate")) == 8
    assert Enum.count(captures, &(&1["method"] == "fuzzyFileSearch/sessionStop")) == 3

    for {root, path, body} <- files do
      assert File.ls!(root) == [path]
      assert File.read!(Path.join(root, path)) == body
    end

    assert Enum.sort(File.ls!(ctx.fixture.workspace)) == ["first", "second"]
    assert File.read!(ctx.config) == ctx.config_bytes
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{})["data"] == []
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp start_session(ctx, pid, id, roots) do
    assert request(ctx, pid, "fuzzyFileSearch/sessionStart", %{
             "sessionId" => id,
             "roots" => roots
           }) == %{}

    # Completed means scanner idle, not a query-generation or replacement
    # fence. Actual root/query effects below require matching data snapshots.
    assert await(pid, @completed, id, fn params -> params == %{"sessionId" => id} end) ==
             %{"sessionId" => id}
  end

  defp query(ctx, pid, id, query, expected) do
    assert request(ctx, pid, "fuzzyFileSearch/sessionUpdate", %{
             "sessionId" => id,
             "query" => query
           }) == %{}

    # Each nonempty phase uses a distinct query. Neither response ACK nor an
    # uncorrelated completed notice can stand in for actual updated results.
    snapshot =
      await(pid, @updated, id, fn params ->
        params["query"] == query and length(params["files"]) == length(expected) and
          pairs(params["files"]) == Enum.sort(expected)
      end)

    assert snapshot["sessionId"] == id
    assert snapshot["query"] == query
    assert length(snapshot["files"]) == length(expected)
    assert pairs(snapshot["files"]) == Enum.sort(expected)

    if query == "", do: assert(snapshot === %{"sessionId" => id, "query" => "", "files" => []})

    for file <- snapshot["files"] do
      assert file["match_type"] == "file"
      assert file["file_name"] == Path.basename(file["path"])
      assert is_integer(file["score"]) and file["score"] > 0
      assert file["indices"] == Enum.sort(Enum.uniq(file["indices"]))
      chars = String.codepoints(file["path"])
      matched = Enum.map_join(file["indices"], &Enum.at(chars, &1))
      assert String.downcase(matched) == String.downcase(query)
    end

    assert ModelFixture.requests(ctx.fixture) == []
  end

  defp pairs(files), do: Enum.sort(Enum.map(files, &{&1["root"], &1["path"]}))

  defp request(ctx, pid, method, params) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-fuzzy-values-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request(pid, method, params, id: id)

    assert_capture(ctx, before, id, method, params)
    result
  end

  defp assert_missing(ctx, pid, session) do
    before = length(Agent.get(ctx.capture, & &1))
    id = "owned-fuzzy-missing-#{System.unique_integer([:positive, :monotonic])}"
    method = "fuzzyFileSearch/sessionUpdate"
    params = %{"sessionId" => session, "query" => "after_stop"}

    assert {:error, %Error{code: :upstream_error, wire: %{"id" => ^id, "error" => error}}} =
             Session.request(pid, method, params, id: id)

    assert_capture(ctx, before, id, method, params)

    assert error == %{
             "code" => -32_600,
             "message" => "fuzzy file search session not found: #{session}"
           }
  end

  defp assert_capture(ctx, before, id, method, params) do
    assert [wire] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert wire === %{"id" => id, "method" => method, "params" => params}
  end

  defp await(pid, method, id, predicate),
    do: await(pid, method, id, predicate, [], System.monotonic_time(:millisecond) + 10_000)

  defp await(pid, method, id, predicate, events, deadline) do
    assert {:ok, incoming} = Session.drain(pid)
    events = events ++ incoming
    assert length(events) <= 256, "Native fuzzy scenario event buffer exceeded its bound"

    found =
      Enum.find_value(events, fn event ->
        params = event.wire["params"]

        if event.wire["method"] == method and params["sessionId"] == id and predicate.(params),
          do: params
      end)

    if found do
      found
    else
      assert System.monotonic_time(:millisecond) < deadline,
             "Native fuzzy notification deadline for #{inspect({method, id})}: #{inspect(events)}"

      assert Session.status(pid).phase == :ready

      receive do
        {:codex_driver, ^pid, :events_available} -> :ok
        {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected event gap during fuzzy scenario")
      after
        10 -> :ok
      end

      await(pid, method, id, predicate, events, deadline)
    end
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
               %{"name" => "owned_fuzzy_session_values", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
