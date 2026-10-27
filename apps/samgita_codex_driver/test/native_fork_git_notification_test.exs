defmodule SamgitaCodexDriver.NativeForkGitNotificationTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaProtocolCodex.{Schema, Wire}

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/reasoning_checklist_envelope_fixture.py", __DIR__)
  @script_sha "d42e156eb535595d63140870db8414f9cde90298c349d378a1d413dd2c2ba5ff"
  @provider_base Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_base_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @client "owned_fork_git_notification"
  @branch "samgita-v430-fixture"
  @name "Owned empty Git parent λ"
  @filename "owned-fixture.txt"
  @contents "Owned local Git metadata fixture λ🙂\n"
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  defmodule CaptureStdio do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    alias SamgitaCodexDriver.Transport.Stdio
    alias SamgitaProtocolCodex.Error

    @impl true
    def open(opts) do
      capture = Keyword.fetch!(opts, :capture)

      with {:ok, state} <- Stdio.open(Keyword.delete(opts, :capture)),
           do: {:ok, Map.put(state, :capture, capture)}
    end

    @impl true
    def send(state, encoded) do
      case Stdio.send(state, encoded) do
        {:ok, next} ->
          case record(next.capture, :out, encoded) do
            :ok -> {:ok, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    @impl true
    def handle_info(message, state) do
      case Stdio.handle_info(message, state) do
        {:ok, events, next} ->
          case Enum.reduce_while(events, :ok, &record_event(&1, &2, next.capture)) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_event({:message, encoded}, :ok, capture) do
      case record(capture, :in, encoded) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end

    defp record_event(_event, :ok, _capture), do: {:cont, :ok}

    # Capture native JSONL before Session decoding, without synthesizing frames.
    defp record(capture, direction, encoded),
      do: Agent.get_and_update(capture, &append(&1, direction, encoded))

    defp append(ledger, direction, encoded) do
      size = byte_size(encoded)
      limit = if direction == :out, do: 8192, else: 65_536

      if ledger.count < 128 and size <= limit and ledger.bytes + size <= 2_097_152 do
        entry = %{direction: direction, encoded: encoded, index: ledger.count + 1}

        {:ok,
         %{count: ledger.count + 1, bytes: ledger.bytes + size, records: [entry | ledger.records]}}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@provider_base)) === @provider_base_sha
    python = System.find_executable("python3")
    git = System.find_executable("git")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required"
    assert is_binary(git), "BLOCKED_ENV: Git required"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-fork-git-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    for child <- ~w(home codex workspace tmp bin git-template),
        do: File.mkdir!(Path.join(root, child))

    File.cp!("/bin/sh", Path.join(root, "bin/sh"))
    File.ln_s!(git, Path.join(root, "bin/git"))
    repo = Path.join(root, "workspace/owned-git-project")
    File.mkdir!(repo)
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})

    profile = %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      git: git,
      workspace: Path.join(root, "workspace"),
      repo: repo,
      capture: capture
    }

    # All Git commands are owned, bounded, isolated and confined to this new repo.
    # Establish the oracle before launching either the provider or native Codex.
    git(profile, ["init", "--object-format=sha1", "--initial-branch=#{@branch}"])
    File.write!(Path.join(repo, @filename), @contents, [:exclusive])
    git(profile, ["add", "--", @filename])
    git(profile, ["commit", "-m", "Owned V430 Git metadata fixture"])
    commit = git(profile, ["rev-parse", "HEAD"])
    assert Regex.match?(~r/\A[0-9a-f]{40}\z/, commit)
    assert git(profile, ["symbolic-ref", "--short", "HEAD"]) === @branch
    assert git(profile, ["remote"]) === ""
    assert git(profile, ["status", "--porcelain"]) === ""

    profile =
      Map.put(profile, :expected_git, %{"sha" => commit, "branch" => @branch, "originUrl" => nil})

    git_inputs = tree_snapshot(repo)
    provider = start_provider(profile)
    # Predeclare ordinary fixture configuration before the immutable snapshot;
    # native startup otherwise materializes this entry for an explicit Git cwd.
    File.write!(
      Path.join(root, "codex/config.toml"),
      "\n[projects.#{JSON.encode!(repo)}]\ntrust_level = \"trusted\"\n",
      [:append]
    )

    frozen = frozen_files(profile)
    session = start_native(profile)
    profile = Map.put(profile, :generation, Session.status(session.pid).generation)

    %{
      profile: profile,
      provider: provider,
      session: session,
      frozen: frozen,
      git_inputs: git_inputs
    }
  end

  test "persistent native fork introduces independently observed local Git metadata without inference",
       ctx do
    profile = ctx.profile
    pid = ctx.session.pid
    active_deadline = now() + 20_000
    parent_lower = System.system_time(:millisecond)

    parent =
      call(profile, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => profile.repo,
        "ephemeral" => false,
        "historyMode" => "legacy"
      })["thread"]["id"]

    assert_uuid(parent)
    assert call(profile, pid, "thread/name/set", %{"threadId" => parent, "name" => @name}) === %{}

    saved =
      call(profile, pid, "thread/read", %{"threadId" => parent, "includeTurns" => true})["thread"]

    assert saved["id"] === parent and saved["name"] === @name
    assert saved["turns"] === []
    assert Map.fetch!(saved, "gitInfo") === profile.expected_git
    assert File.regular?(saved["path"])
    parent_bytes = File.read!(saved["path"])
    lower = System.system_time(:millisecond)

    response =
      call(profile, pid, "thread/fork", %{
        "threadId" => parent,
        "cwd" => profile.repo,
        "ephemeral" => false,
        "excludeTurns" => true
      })

    child = response["thread"]["id"]
    assert_uuid(child)
    refute child === parent
    events = collect(pid, child, [], active_deadline)
    upper = System.system_time(:millisecond)
    [event] = notices(events, child)
    snapshot = event.wire["params"]["thread"]
    expected = assert_fork(profile, snapshot, child, parent, lower, upper)
    emitted_at = Map.fetch!(event.wire, "emittedAtMs")
    assert is_integer(emitted_at) and lower <= emitted_at and emitted_at <= upper
    assert event.kind === :notification and event.generation === profile.generation

    assert event.wire === %{
             "method" => "thread/started",
             "params" => %{"thread" => expected},
             "emittedAtMs" => emitted_at
           }

    assert :ok = Schema.validate(schema("ServerNotification.json"), event.wire, max_depth: 32)
    assert response["thread"] === expected
    assert is_map(Map.fetch!(snapshot, "gitInfo"))
    assert Map.fetch!(snapshot, "gitInfo") === profile.expected_git

    [parent_event] = notices(events, parent)
    assert parent_event.sequence < event.sequence
    assert Map.fetch!(parent_event.wire["params"]["thread"], "gitInfo") === nil
    assert parent_lower <= parent_event.wire["emittedAtMs"]
    originals = assert_originals(profile, events)
    assert_original_fork_exchange(profile, event)

    child_saved =
      call(profile, pid, "thread/read", %{"threadId" => child, "includeTurns" => true})["thread"]

    assert child_saved["id"] === child and child_saved["sessionId"] === child
    assert child_saved["forkedFromId"] === parent
    assert child_saved["gitInfo"] === profile.expected_git
    assert child_saved["turns"] === []
    assert child_saved["path"] === expected["path"]
    assert File.read!(saved["path"]) === parent_bytes
    assert now() <= active_deadline
    assert_frozen(ctx)
    assert_ready(profile, pid)

    outgoing = for frame <- capture(profile), frame.direction == :out, do: frame.wire["method"]

    assert outgoing ===
             ~w(initialize initialized server/diagnostics thread/start thread/name/set thread/read thread/fork thread/read)

    close_native(pid, ctx.session.connection, ctx.session.identity)
    close_transport(ctx.provider.transport, ctx.provider.identity)
    assert_frozen(ctx)
    assert assert_originals(profile, events) === originals
    assert File.read!(saved["path"]) === parent_bytes
  end

  defp assert_fork(profile, snapshot, id, parent, lower, upper) do
    created = Map.fetch!(snapshot, "createdAt")
    updated = Map.fetch!(snapshot, "updatedAt")
    recency = Map.fetch!(snapshot, "recencyAt")

    for timestamp <- [created, updated, recency] do
      assert is_integer(timestamp) and div(lower, 1000) <= timestamp and
               timestamp <= div(upper, 1000)
    end

    assert created <= updated and created <= recency
    path = assert_path(profile, Map.fetch!(snapshot, "path"), id, lower, upper)

    # Literal stock persisted-fork shape. The capability-shaped field is kept
    # only as wrapper data; this test does not exercise authorization semantics.
    expected = %{
      "id" => id,
      "sessionId" => id,
      "environments" => [
        %{
          "environmentId" => "local",
          "cwd" => profile.repo,
          "runtimeWorkspaceRoots" => [profile.repo]
        }
      ],
      "extra" => nil,
      "forkedFromId" => parent,
      "parentThreadId" => nil,
      "section" => nil,
      "sectionEnteredAt" => nil,
      "reasoningEffort" => nil,
      "threadSource" => nil,
      "agentNickname" => nil,
      "agentRole" => nil,
      "gitInfo" => profile.expected_git,
      "name" => @name,
      "preview" => "",
      "turns" => [],
      "ephemeral" => false,
      "daybreakEnabled" => nil,
      "projectId" => nil,
      "historyMode" => "legacy",
      "cwd" => profile.repo,
      "modelProvider" => "fixture",
      "model" => "mock-model",
      "cliVersion" => "0.163.0",
      "originator" => @client,
      "source" => "vscode",
      "canAcceptDirectInput" => true,
      "status" => %{"type" => "idle"},
      "createdAt" => created,
      "updatedAt" => updated,
      "recencyAt" => recency,
      "path" => path
    }

    assert map_size(expected) === 32
    assert snapshot === expected
    expected
  end

  defp assert_path(profile, path, id, lower, upper) do
    assert is_binary(path) and Path.type(path) === :absolute
    codex_home = Path.join(profile.root, "codex")
    assert String.starts_with?(path, codex_home <> "/")
    assert File.regular?(path)

    assert [_, year, month, day, date, clock, path_id] =
             Regex.run(
               ~r"\Asessions/([0-9]{4})/([0-9]{2})/([0-9]{2})/rollout-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2}-[0-9]{2}-[0-9]{2})-([0-9a-f-]{36})\.jsonl\z",
               Path.relative_to(path, codex_home)
             )

    assert date === Enum.join([year, month, day], "-")
    assert path_id === id

    assert {:ok, path_at, 0} =
             DateTime.from_iso8601(date <> "T" <> String.replace(clock, "-", ":") <> "Z")

    assert div(lower, 1000) <= DateTime.to_unix(path_at) and
             DateTime.to_unix(path_at) <= div(upper, 1000)

    path
  end

  defp assert_originals(profile, events) do
    original =
      for frame <- capture(profile),
          frame.direction == :in,
          frame.wire["method"] == "thread/started",
          do: frame

    projected = Enum.filter(events, &(&1.wire["method"] == "thread/started"))
    assert length(original) === 2
    assert Enum.map(original, & &1.wire) === Enum.map(projected, & &1.wire)

    for {frame, event} <- Enum.zip(original, projected) do
      assert JSON.decode!(frame.encoded) === event.wire
      assert {:ok, wire} = Wire.decode(frame.encoded, max_depth: 32)
      assert wire === event.wire
    end

    original
  end

  defp assert_original_fork_exchange(profile, event) do
    frames = capture(profile)

    [request] =
      Enum.filter(frames, &(&1.direction == :out and &1.wire["method"] == "thread/fork"))

    [response] =
      Enum.filter(frames, &(&1.direction == :in and &1.wire["id"] == request.wire["id"]))

    [original] = Enum.filter(frames, &(&1.direction == :in and &1.wire === event.wire))
    assert request.index < response.index and response.index < original.index
    assert response.wire["result"]["thread"] === event.wire["params"]["thread"]
  end

  defp collect(pid, child, events, deadline) do
    assert now() < deadline, "Owned fork Git notification deadline"
    assert {:ok, fresh} = Session.drain(pid, 128)
    events = events ++ fresh
    assert length(events) <= 128
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= 2_097_152
    assert %{phase: :ready, gap: nil, generation: generation} = Session.status(pid)
    assert Enum.all?(events, &(&1.generation === generation and &1.kind === :notification))
    sequences = Enum.map(events, & &1.sequence)
    assert sequences === Enum.sort(Enum.uniq(sequences))

    refute Enum.any?(events, fn event ->
             event.wire["method"] in ~w(error warning turn/started turn/completed item/started item/completed)
           end)

    if notices(events, child) != [] do
      events
    else
      Process.sleep(10)
      collect(pid, child, events, deadline)
    end
  end

  defp git(profile, args) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.git,
               python: profile.python,
               args: [
                 "-c",
                 "user.name=Owned fixture",
                 "-c",
                 "user.email=fixture@example.invalid",
                 "-c",
                 "commit.gpgsign=false",
                 "-c",
                 "core.hooksPath=/dev/null" | args
               ],
               cwd: profile.repo,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 16_384
             )

    helper =
      case Port.info(transport.port, :os_pid) do
        {:os_pid, native} -> native
        nil -> 0
      end

    try do
      {output, status} = git_output(transport.port, <<>>, now() + 5_000)
      assert status === 0, "Owned Git fixture command failed: #{output}"
      String.trim(output)
    after
      identity = :atomics.new(1, [])
      :atomics.put(identity, 1, helper)
      close_transport(transport, identity)
    end
  end

  defp git_output(port, output, deadline) do
    assert byte_size(output) <= 16_384
    remaining = deadline - now()
    assert remaining > 0, "Owned Git fixture command deadline"

    receive do
      {^port, {:data, bytes}} -> git_output(port, output <> bytes, deadline)
      {^port, {:exit_status, status}} -> {output, status}
    after
      remaining -> flunk("Owned Git fixture command deadline")
    end
  end

  defp tree_snapshot(root) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true) |> Enum.sort()
    assert length(paths) <= 128

    files =
      for path <- paths,
          File.regular?(path),
          into: %{},
          do: {Path.relative_to(path, root), File.read!(path)}

    assert Enum.reduce(files, 0, fn {_path, bytes}, size -> size + byte_size(bytes) end) <=
             1_048_576

    %{entries: Enum.map(paths, &Path.relative_to(&1, root)), files: files}
  end

  defp start_provider(profile) do
    assert {:ok, transport} =
             Stdio.open(
               executable: profile.python,
               args: [
                 @script,
                 "--root",
                 profile.root,
                 "--scenario",
                 "reasoning",
                 "--answer-phase",
                 "final_answer"
               ],
               cwd: profile.workspace,
               inherit_env: [],
               env: environment(profile),
               max_message_bytes: 4096
             )

    identity = :atomics.new(1, [])
    on_exit(fn -> close_transport(transport, identity) end)
    startup = provider_startup(transport.port, <<>>, now() + 5_000)
    native = Map.fetch!(startup, "pid")
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert is_binary(startup["url"]) and String.starts_with?(startup["url"], "http://127.0.0.1:")
    assert hash(File.read!(profile.python)) === hash(File.read!("/proc/#{native}/exe"))
    %{transport: transport, identity: identity}
  end

  defp provider_startup(port, buffer, deadline) do
    assert now() < deadline, "Owned provider startup deadline"

    receive do
      {^port, {:data, bytes}} -> provider_line(port, buffer <> bytes, deadline)
      {^port, {:exit_status, status}} -> flunk("Owned provider startup exit #{status}")
    after
      10 -> provider_startup(port, buffer, deadline)
    end
  end

  defp provider_line(port, buffer, deadline) do
    assert byte_size(buffer) <= 4096

    case String.split(buffer, "\n", parts: 2) do
      [line, ""] -> JSON.decode!(line)
      [_line, _extra] -> flunk("Unexpected owned provider startup output")
      [_partial] -> provider_startup(port, buffer, deadline)
    end
  end

  defp start_native(profile) do
    assert {:ok, pid} =
             Session.start_link(
               max_events: 128,
               max_event_bytes: 2_097_152,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: profile.capture,
                    executable: profile.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: profile.repo,
                    inherit_env: [],
                    env: environment(profile),
                    max_message_bytes: 65_536
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    identity = :atomics.new(1, [])
    on_exit(fn -> close_native(pid, connection, identity) end)
    info = %{"name" => @client, "version" => "0.1.0"}

    capabilities = %{
      "experimentalApi" => true,
      "optOutNotificationMethods" => ["remoteControl/status/changed"]
    }

    id = request_id()

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(
      profile,
      %{
        "id" => id,
        "method" => "initialize",
        "params" => %{"clientInfo" => info, "capabilities" => capabilities}
      },
      response
    )

    native = call(profile, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    :atomics.put(identity, 1, native)
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, identity: identity}
  end

  defp environment(profile) do
    %{
      "HOME" => Path.join(profile.root, "home"),
      "CODEX_HOME" => Path.join(profile.root, "codex"),
      "TMPDIR" => Path.join(profile.root, "tmp"),
      "PATH" => Path.join(profile.root, "bin") <> ":/usr/bin:/bin",
      "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_TEMPLATE_DIR" => Path.join(profile.root, "git-template"),
      "GIT_AUTHOR_DATE" => "2026-01-01T00:00:00Z",
      "GIT_COMMITTER_DATE" => "2026-01-01T00:00:00Z",
      "GIT_TERMINAL_PROMPT" => "0",
      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
      "PYTHONDONTWRITEBYTECODE" => "1",
      "NO_COLOR" => "1",
      "RUST_LOG" => "off",
      "TZ" => "UTC"
    }
  end

  defp frozen_files(profile) do
    for name <- ~w(codex/config.toml codex/models.json requests.json provider-events.json),
        into: %{},
        do: {name, File.read!(Path.join(profile.root, name))}
  end

  defp assert_frozen(ctx) do
    profile = ctx.profile
    assert frozen_files(profile) === ctx.frozen
    assert ctx.frozen["requests.json"] === "[]"
    assert ctx.frozen["provider-events.json"] === "[]"
    refute File.exists?(Path.join(profile.root, "provider-error.json"))
    assert File.ls!(profile.workspace) === ["owned-git-project"]
    assert tree_snapshot(profile.repo) === ctx.git_inputs
    assert File.read!(Path.join(profile.repo, @filename)) === @contents
    assert hash(File.read!(@script)) === @script_sha
    assert hash(File.read!(@provider_base)) === @provider_base_sha
  end

  defp call(profile, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert_exchange(profile, wire, response)
    result
  end

  defp assert_exchange(profile, wire, response) do
    assert [sent, received] = Enum.filter(capture(profile), &(&1.wire["id"] == wire["id"]))
    assert sent.direction === :out and received.direction === :in
    assert sent.index < received.index
    assert sent.wire === wire and sent.encoded === JSON.encode!(wire)
    assert received.wire === response
    assert Enum.sort(Map.keys(response)) === ["id", "result"]
  end

  defp capture(profile) do
    Agent.get(profile.capture, & &1.records)
    |> Enum.reverse()
    |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
  end

  defp notices(events, id),
    do:
      Enum.filter(
        events,
        &(&1.wire["method"] == "thread/started" and
            get_in(&1.wire, ["params", "thread", "id"]) == id)
      )

  defp schema(relative) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/0.163.0/experimental/" <> relative)
    |> File.read!()
    |> JSON.decode!()
  end

  defp assert_ready(profile, pid) do
    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.status(pid).generation === profile.generation
    assert Session.uncertain_operations(pid) === []
  end

  defp close_native(pid, connection, identity) do
    assert :ok = StdioSessionFixture.close(pid, connection)
    close_transport(connection, identity)
  end

  defp close_transport(connection, identity) do
    monitor = Process.monitor(connection.owner.pid)
    assert :ok = Stdio.close(connection)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(connection.owner.completion, 1) === 1
    assert Port.info(connection.port) === nil
    native = :atomics.get(identity, 1)
    if native > 0, do: refute(File.exists?("/proc/#{native}"))
  end

  defp assert_uuid(id), do: assert(is_binary(id) and Regex.match?(@uuid, id))
  defp request_id, do: "owned-fork-git-#{System.unique_integer([:positive, :monotonic])}"
  defp now, do: System.monotonic_time(:millisecond)
  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
