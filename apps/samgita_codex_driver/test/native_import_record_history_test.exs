defmodule SamgitaCodexDriver.NativeImportRecordHistoryTest do
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
  @provider Path.expand("../../../scripts/codex/model_fixture.py", __DIR__)
  @provider_sha "a18341e8c05ecec4ffe4b685f37dc0b8a123f81704a34f84a92cda0b4cbddbd8"
  @max_file_bytes 2_097_152
  @max_line_bytes 65_536

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
          case record(next, :out, encoded) do
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
          case record_events(next, events) do
            :ok -> {:ok, events, next}
            {:error, failure} -> {:error, failure, next}
          end

        other ->
          other
      end
    end

    defp record_events(state, events) do
      Enum.reduce_while(events, :ok, fn event, :ok ->
        case record_event(state, event) do
          :ok -> {:cont, :ok}
          failure -> {:halt, failure}
        end
      end)
    end

    defp record_event(state, {:message, encoded}), do: record(state, :in, encoded)
    defp record_event(_state, _event), do: :ok

    # Preserve original framed bytes before the Session's JSON decoder. Decode
    # only when the test reads the ledger, never substitute a reconstructed wire.
    defp record(state, direction, encoded) do
      Agent.get_and_update(state.capture, fn ledger ->
        size = byte_size(encoded)

        if ledger.count < 128 and size <= 65_536 and ledger.bytes + size <= 2_097_152 do
          entry = %{direction: direction, encoded: encoded}

          {:ok,
           %{
             count: ledger.count + 1,
             bytes: ledger.bytes + size,
             records: [entry | ledger.records]
           }}
        else
          {{:error, Error.new(:test_capture_overflow)}, ledger}
        end
      end)
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    binary = Path.expand(binary)
    assert hash(File.read!(binary)) === @binary_sha
    assert hash(File.read!(@provider)) === @provider_sha

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-record-history-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    File.mkdir!(Path.join(root, "tmp"))
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    fixture =
      try do
        ModelFixture.start(root, "assistant")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> close_provider(fixture) end)
    File.write!(fixture.requests, "[]")
    capture = start_supervised!({Agent, fn -> %{count: 0, bytes: 0, records: []} end})
    ctx = %{binary: binary, root: root, fixture: fixture, capture: capture}
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\napps = false\nplugins = false\nremote_plugin = false\nrecommended_plugins = false\nshell_snapshot = false\nmemories = false\n"
    )

    inputs = [
      config,
      Path.join(fixture.codex_home, "turn-models.json"),
      @provider,
      __ENV__.file,
      Path.join(__DIR__, "support/model_fixture.ex"),
      Path.join(__DIR__, "support/turn_fixture.ex"),
      Path.join(__DIR__, "support/native_launch_fixture.ex"),
      Path.join(__DIR__, "support/stdio_session_fixture.ex")
    ]

    Map.merge(ctx, %{
      reported: Path.join(root, "reported-metadata-only"),
      inputs: Map.new(inputs, &{&1, bounded_file(&1)})
    })
  end

  test "reported import histories preserve distinct supplied outcomes and native identities across cold restart",
       ctx do
    assert_retained(ctx)
    warm = start(ctx)
    assert_no_threads(ctx, warm.pid)
    assert histories(ctx, warm.pid) === %{"data" => [], "connectors" => []}

    params_a = %{
      "providerId" => "owned-history-provider-a",
      "itemTypeResults" => [
        %{
          "itemType" => "SESSIONS",
          "successes" => [
            %{
              "itemType" => "SESSIONS",
              "cwd" => ctx.fixture.workspace,
              "source" => Path.join(ctx.reported, "a-source.jsonl"),
              "target" => Path.join(ctx.reported, "a-target"),
              "title" => "Reported session A λ"
            }
          ],
          "failures" => []
        },
        %{
          "itemType" => "CONFIG",
          "successes" => [
            %{
              "itemType" => "CONFIG",
              "cwd" => nil,
              "source" => "Reported config A source",
              "target" => "Reported config A target",
              "title" => nil
            }
          ],
          "failures" => [
            %{
              "itemType" => "CONFIG",
              "cwd" => ctx.fixture.workspace,
              "errorType" => "reported_config_a",
              "subErrorType" => "reported_parse_a",
              "failureStage" => "reported_stage_a",
              "message" => "Reported config A failure",
              "source" => Path.join(ctx.reported, "a-config.toml")
            }
          ]
        }
      ]
    }

    first = record(ctx, warm.pid, params_a)

    # Independent complete oracle: do not flatten or otherwise derive the
    # expected native history from the request being tested. Native storage
    # flattens groups; the group's own itemType is not a persistence claim.
    expected_a = %{
      "importId" => first.id,
      "providerId" => "owned-history-provider-a",
      "completedAtMs" => first.completed_at,
      "successes" => [
        %{
          "itemType" => "SESSIONS",
          "cwd" => ctx.fixture.workspace,
          "source" => Path.join(ctx.reported, "a-source.jsonl"),
          "target" => Path.join(ctx.reported, "a-target"),
          "title" => "Reported session A λ"
        },
        %{
          "itemType" => "CONFIG",
          "cwd" => nil,
          "source" => "Reported config A source",
          "target" => "Reported config A target",
          "title" => nil
        }
      ],
      "failures" => [
        %{
          "itemType" => "CONFIG",
          "cwd" => ctx.fixture.workspace,
          "errorType" => "reported_config_a",
          "subErrorType" => "reported_parse_a",
          "failureStage" => "reported_stage_a",
          "message" => "Reported config A failure",
          "source" => Path.join(ctx.reported, "a-config.toml")
        }
      ]
    }

    assert first.histories === %{"data" => [expected_a], "connectors" => []}
    assert_retained(ctx)

    params_b = %{
      "providerId" => "owned-history-provider-b",
      "itemTypeResults" => [
        %{
          "itemType" => "COMMANDS",
          "successes" => [
            %{
              "itemType" => "COMMANDS",
              "cwd" => nil,
              "source" => Path.join(ctx.reported, "b-command.md"),
              "target" => Path.join(ctx.reported, "b-target.md"),
              "title" => "Reported command B"
            }
          ],
          "failures" => [
            %{
              "itemType" => "COMMANDS",
              "cwd" => nil,
              "errorType" => "reported_command_b",
              "subErrorType" => nil,
              "failureStage" => "reported_stage_b_one",
              "message" => "Reported command B failure one",
              "source" => nil
            },
            %{
              "itemType" => "COMMANDS",
              "cwd" => ctx.fixture.workspace,
              "errorType" => "reported_command_b_two",
              "subErrorType" => "reported_detail_b",
              "failureStage" => "reported_stage_b",
              "message" => "Reported command B failure two",
              "source" => Path.join(ctx.reported, "b-failure.md")
            }
          ]
        }
      ]
    }

    second = record(ctx, warm.pid, params_b)
    refute second.id === first.id

    expected_b = %{
      "importId" => second.id,
      "providerId" => "owned-history-provider-b",
      "completedAtMs" => second.completed_at,
      "successes" => [
        %{
          "itemType" => "COMMANDS",
          "cwd" => nil,
          "source" => Path.join(ctx.reported, "b-command.md"),
          "target" => Path.join(ctx.reported, "b-target.md"),
          "title" => "Reported command B"
        }
      ],
      "failures" => [
        %{
          "itemType" => "COMMANDS",
          "cwd" => nil,
          "errorType" => "reported_command_b",
          "subErrorType" => nil,
          "failureStage" => "reported_stage_b_one",
          "message" => "Reported command B failure one",
          "source" => nil
        },
        %{
          "itemType" => "COMMANDS",
          "cwd" => ctx.fixture.workspace,
          "errorType" => "reported_command_b_two",
          "subErrorType" => "reported_detail_b",
          "failureStage" => "reported_stage_b",
          "message" => "Reported command B failure two",
          "source" => Path.join(ctx.reported, "b-failure.md")
        }
      ]
    }

    expected = %{
      "data" => Enum.sort_by([expected_a, expected_b], &{-&1["completedAtMs"], &1["importId"]}),
      "connectors" => []
    }

    assert second.histories === expected
    assert_idle(ctx, warm.pid)
    assert_retained(ctx)
    close(warm)
    assert_retained(ctx)

    cold = start(ctx)
    refute cold.native === warm.native
    assert_no_threads(ctx, cold.pid)
    assert histories(ctx, cold.pid) === expected
    assert_idle(ctx, cold.pid)
    assert_retained(ctx)
    close(cold)
    assert_retained(ctx)
    assert_wire_inventory(ctx, [params_a, params_b])
    close_provider(ctx.fixture)
    assert_retained(ctx)
    assert hash(File.read!(ctx.binary)) === @binary_sha
  end

  defp record(ctx, pid, params) do
    before_ms = System.system_time(:millisecond)
    response = call(ctx, pid, "externalAgentConfig/import/recordHistory", params)
    after_ms = System.system_time(:millisecond)
    assert %{"importId" => id} = response
    assert Map.keys(response) === ["importId"]
    assert_uuid(id)
    result = histories(ctx, pid)
    assert [stored] = Enum.filter(Map.fetch!(result, "data"), &(&1["importId"] == id))
    completed_at = Map.fetch!(stored, "completedAtMs")
    assert is_integer(completed_at) and completed_at > 0
    assert completed_at >= before_ms and completed_at <= after_ms
    %{id: id, completed_at: completed_at, histories: result}
  end

  defp start(ctx) do
    assert {:ok, pid} =
             Session.start_link(
               max_pending: 8,
               max_events: 64,
               max_event_bytes: @max_file_bytes,
               max_message_bytes: @max_line_bytes,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => Path.join(ctx.root, "tmp"),
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      monitor = Process.monitor(connection.owner.pid)
      assert :ok = StdioSessionFixture.close(pid, connection)
      assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
      assert :atomics.get(connection.owner.completion, 1) === 1
      assert Port.info(connection.port) === nil
    end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_native_record_history", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) === @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params) do
    id = "owned-record-history-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}

    assert {:ok, %{"id" => ^id, "result" => result} = response} =
             Session.request_native(pid, wire, timeout_ms: 5_000)

    assert [sent, received] = Enum.filter(capture(ctx), &(&1.wire["id"] == id))
    assert sent.direction === :out and received.direction === :in
    assert sent.wire === wire and received.wire === response
    assert JSON.decode!(sent.encoded) === wire
    assert JSON.decode!(received.encoded) === response
    result
  end

  defp capture(ctx) do
    Agent.get(ctx.capture, fn ledger ->
      ledger.records
      |> Enum.reverse()
      |> Enum.map(&Map.put(&1, :wire, JSON.decode!(&1.encoded)))
    end)
  end

  defp histories(ctx, pid),
    do: call(ctx, pid, "externalAgentConfig/import/readHistories", nil)

  defp assert_no_threads(ctx, pid) do
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    listed = call(ctx, pid, "thread/list", %{"limit" => 10, "useStateDbOnly" => true})
    assert Map.fetch!(listed, "data") === []
    assert Map.fetch!(listed, "nextCursor") === nil
    assert Map.fetch!(listed, "backwardsCursor") === nil
  end

  defp assert_idle(ctx, pid) do
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert Session.uncertain_operations(pid) === []
    assert {:ok, events} = Session.drain(pid, 64)
    assert length(events) <= 64
    assert byte_size(JSON.encode!(Enum.map(events, & &1.wire))) <= @max_file_bytes
    assert Enum.all?(events, &(&1.wire["method"] != "error"))
    assert bounded_file(ctx.fixture.requests) === "[]"
  end

  defp assert_retained(ctx) do
    for {path, bytes} <- ctx.inputs, do: assert(bounded_file(path) === bytes)
    assert bounded_file(ctx.fixture.requests) === "[]"
    assert File.ls!(ctx.fixture.workspace) === []
    refute File.exists?(ctx.reported)
    assert Path.wildcard(Path.join(ctx.fixture.codex_home, "sessions/**/rollout-*.jsonl")) === []
  end

  defp assert_wire_inventory(ctx, reports) do
    records = capture(ctx)
    outgoing = for %{direction: :out, wire: wire} <- records, do: wire

    allowed =
      ~w(initialize initialized server/diagnostics thread/loaded/list thread/list externalAgentConfig/import/recordHistory externalAgentConfig/import/readHistories)

    assert Enum.all?(outgoing, &(&1["method"] in allowed))
    assert Enum.count(outgoing, &(&1["method"] == "initialize")) === 2
    assert Enum.count(outgoing, &(&1["method"] == "initialized")) === 2
    assert Enum.count(outgoing, &(&1["method"] == "server/diagnostics")) === 2

    assert for(
             wire <- outgoing,
             wire["method"] == "externalAgentConfig/import/recordHistory",
             do: wire["params"]
           ) === reports

    assert Enum.count(outgoing, &(&1["method"] == "externalAgentConfig/import/readHistories")) ===
             4

    for %{direction: :in, wire: wire} <- records do
      method = wire["method"]

      if is_binary(method) do
        refute String.starts_with?(method, [
                 "thread/",
                 "turn/",
                 "item/",
                 "externalAgentConfig/import/"
               ])
      end
    end

    assert length(records) <= 128
    for record <- records, do: assert(byte_size(record.encoded) <= @max_line_bytes)
  end

  defp close(session) do
    monitor = Process.monitor(session.connection.owner.pid)
    assert :ok = Session.close(session.pid)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(session.connection.owner.completion, 1) === 1
    assert Port.info(session.connection.port) === nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp close_provider(fixture) do
    monitor = Process.monitor(fixture.transport.owner.pid)
    assert :ok = ModelFixture.close(fixture)
    assert_receive {:DOWN, ^monitor, :process, _, _}, 1_000
    assert :atomics.get(fixture.transport.owner.completion, 1) === 1
    assert Port.info(fixture.port) === nil
  end

  defp bounded_file(path) do
    assert %{type: :regular, size: size} = File.stat!(path)
    assert size > 0 and size <= @max_file_bytes
    bytes = File.read!(path)
    assert byte_size(bytes) === size
    bytes
  end

  defp assert_uuid(value) do
    assert is_binary(value) and
             value =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
