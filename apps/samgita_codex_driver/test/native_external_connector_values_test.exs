defmodule SamgitaCodexDriver.NativeExternalConnectorValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{
    ModelFixture,
    NativeLaunchFixture,
    Session,
    StdioSessionFixture,
    TurnFixture
  }

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @detect "externalAgentConfig/detect"
  @histories "externalAgentConfig/import/readHistories"
  @atlas %{"name" => "Owned Atlas", "sessionCount" => 2, "source" => "remoteMcpServersConfig"}
  @echo %{"name" => "Owned Echo", "sessionCount" => 1, "source" => "sessionToolUse"}

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

      if wire["method"] in [
           "externalAgentConfig/detect",
           "externalAgentConfig/import/readHistories"
         ] do
        capture(state, encoded, wire)
      else
        Stdio.send(state, encoded)
      end
    end

    defp capture(state, encoded, wire) do
      if length(Agent.get(state.capture, & &1)) < 32 and byte_size(encoded) <= 4096 do
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
    inputs = foreign_inputs(ctx)

    Map.merge(ctx, %{
      capture: start_supervised!({Agent, fn -> [] end}),
      inputs: inputs,
      config: config,
      config_bytes: File.read!(config),
      journal: File.read!(ctx.fixture.requests)
    })
  end

  test "native detected connector facts persist without importing a session", ctx do
    {pid, native} = start(ctx)
    assert histories(ctx, pid) === %{"data" => [], "connectors" => []}

    claude = detect(ctx, pid, "claude-code")
    assert_detected(claude, [@atlas], ctx.inputs.claude_paths, ctx.inputs.cwd)
    assert histories(ctx, pid) === %{"data" => [], "connectors" => [@atlas]}

    cursor = detect(ctx, pid, "cursor")
    assert_detected(cursor, [@echo], [ctx.inputs.cursor_path], ctx.inputs.cwd)

    # Pinned upstream reads detected records through an "imported" candidate API.
    # It relabels every source as remoteMcpServersConfig, including Cursor tool-use
    # provenance. These are persisted candidates; no import has been performed.
    persisted = %{
      "data" => [],
      "connectors" => [@atlas, %{@echo | "source" => "remoteMcpServersConfig"}]
    }

    assert histories(ctx, pid) === persisted

    assert_detected(
      detect(ctx, pid, "claude-code"),
      [@atlas],
      ctx.inputs.claude_paths,
      ctx.inputs.cwd
    )

    assert_detected(
      detect(ctx, pid, "cursor"),
      [@echo],
      [ctx.inputs.cursor_path],
      ctx.inputs.cwd
    )

    assert histories(ctx, pid) === persisted
    assert_retained(ctx, pid)
    close(pid, native)

    {cold, cold_native} = start(ctx)
    assert cold_native != native
    assert histories(ctx, cold) === persisted
    assert_retained(ctx, cold)

    captured = Agent.get(ctx.capture, & &1)
    assert length(captured) == 9
    assert length(Enum.uniq_by(captured, & &1["id"])) == 9

    assert Enum.map(captured, & &1["method"]) == [
             @histories,
             @detect,
             @histories,
             @detect,
             @histories,
             @detect,
             @detect,
             @histories,
             @histories
           ]

    close(cold, cold_native)
  end

  defp foreign_inputs(ctx) do
    home = ctx.fixture.home
    cwd = ctx.fixture.workspace

    claude =
      for suffix <- ["a", "b"] do
        session = Path.join(home, ".claude/projects/owned-project/owned-#{suffix}.jsonl")
        manifest = Path.join(home, ".config/Claude/claude-code-sessions/owned-#{suffix}.json")

        record = %{
          "type" => "user",
          "cwd" => cwd,
          "timestamp_ms" => 1_700_000_000_000,
          "attributionMcpServer" => "owned-atlas-#{suffix}",
          "message" => %{"content" => "Owned source fixture #{String.upcase(suffix)}."}
        }

        metadata = %{
          "cliSessionId" => "owned-#{suffix}",
          "remoteMcpServersConfig" => [
            %{"uuid" => "owned-atlas-#{suffix}", "name" => "Owned Atlas"}
          ]
        }

        {session, [{session, JSON.encode!(record) <> "\n"}, {manifest, JSON.encode!(metadata)}]}
      end

    cursor_root = Path.join(home, ".cursor/projects/empty-window")
    cursor_path = Path.join(cursor_root, "agent-transcripts/owned-c/owned-c.jsonl")
    cursor_metadata = Path.join(cursor_root, "mcps/owned-echo/SERVER_METADATA.json")

    # This is historical foreign source data read by detection, never a tool call.
    cursor_records = [
      %{
        "role" => "user",
        "cwd" => cwd,
        "timestamp_ms" => 1_700_000_000_000,
        "message" => %{"content" => "Owned source fixture C."}
      },
      %{
        "role" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_use",
              "name" => "CallMcpTool",
              "input" => %{
                "server" => "owned-echo",
                "toolName" => "fixture_noop",
                "arguments" => %{}
              }
            }
          ]
        }
      }
    ]

    files =
      Enum.flat_map(claude, &elem(&1, 1)) ++
        [
          {cursor_path, Enum.map_join(cursor_records, "\n", &JSON.encode!/1) <> "\n"},
          {cursor_metadata,
           JSON.encode!(%{"serverIdentifier" => "owned-echo", "serverName" => "Owned Echo"})}
        ]

    for {path, bytes} <- files do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes, [:exclusive])
    end

    assert length(files) == 6

    %{
      cwd: cwd,
      claude_paths: Enum.map(claude, &elem(&1, 0)),
      cursor_path: cursor_path,
      files: Map.new(files, fn {path, bytes} -> {path, %{bytes: bytes, sha256: hash(bytes)}} end)
    }
  end

  defp detect(ctx, pid, source) do
    request(ctx, pid, @detect, %{
      "includeHome" => true,
      "cwds" => [],
      "maxSessionAgeDays" => 1,
      "maxSessions" => 10,
      "migrationSource" => source
    })
  end

  defp histories(ctx, pid), do: request(ctx, pid, @histories, nil)

  defp assert_detected(result, connectors, paths, cwd) do
    assert Map.fetch!(result, "connectors") === connectors

    assert [%{"itemType" => "SESSIONS", "cwd" => nil, "details" => details}] =
             Map.fetch!(result, "items")

    sessions = Map.fetch!(details, "sessions")

    assert Enum.sort(Enum.map(sessions, &{Map.fetch!(&1, "path"), Map.fetch!(&1, "cwd")})) ===
             Enum.sort(Enum.map(paths, &{&1, cwd}))

    for path <- paths, do: assert(File.regular?(path))
    assert File.dir?(cwd)
  end

  defp request(ctx, pid, method, params) when method in [@detect, @histories] do
    before = length(Agent.get(ctx.capture, & &1))
    wire = envelope(method, params)
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [captured] = Agent.get(ctx.capture, &Enum.drop(&1, before))
    assert captured === wire
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    result
  end

  defp call(pid, method, params) do
    wire = envelope(method, params)
    id = wire["id"]

    assert {:ok, %{"id" => ^id, "result" => result}} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    result
  end

  defp envelope(method, params) do
    %{
      "id" => "owned-external-connectors-#{System.unique_integer([:positive, :monotonic])}",
      "method" => method,
      "params" => params
    }
  end

  defp assert_retained(ctx, pid) do
    for {path, expected} <- ctx.inputs.files do
      assert File.read!(path) === expected.bytes
      assert hash(File.read!(path)) == expected.sha256
    end

    assert File.read!(ctx.config) === ctx.config_bytes
    assert File.read!(ctx.fixture.requests) === ctx.journal
    assert ModelFixture.requests(ctx.fixture) == []
    assert call(pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
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
               %{"name" => "owned_external_connector_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native)
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {pid, native}
  end

  defp close(pid, native) do
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    :ok
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
