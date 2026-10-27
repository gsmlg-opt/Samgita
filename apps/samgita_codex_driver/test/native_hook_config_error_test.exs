defmodule SamgitaCodexDriver.NativeHookConfigErrorTest do
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
  @selection "model_provider = \"fixture\"\n"
  @missing_providers [
    "samgita-v396-missing-provider-a",
    "samgita-v396-missing-provider-b"
  ]

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

    defp record(state, direction, encoded) do
      case JSON.decode(encoded) do
        {:ok, wire} ->
          if selected?(direction, wire),
            do: Agent.get_and_update(state.capture, &append(&1, direction, encoded, wire)),
            else: :ok

        {:error, _} ->
          :ok
      end
    end

    defp selected?(:out, %{"id" => _, "method" => _}), do: true
    defp selected?(:in, %{"id" => _} = wire), do: not Map.has_key?(wire, "method")
    defp selected?(_direction, _wire), do: false

    defp append(ledger, direction, encoded, wire) do
      entries = Map.fetch!(ledger, direction)
      size = byte_size(encoded)
      limit = if direction == :out, do: 4096, else: 65_536

      if length(entries) < 16 and size <= limit and ledger.bytes + size <= 1_048_576 do
        next =
          ledger
          |> Map.put(direction, entries ++ [%{encoded: encoded, wire: wire}])
          |> Map.put(:bytes, ledger.bytes + size)

        {:ok, next}
      else
        {{:error, Error.new(:test_capture_overflow)}, ledger}
      end
    end

    @impl true
    def close(state), do: Stdio.close(state)
    @impl true
    def metadata(state), do: Stdio.metadata(state)
  end

  setup tags do
    assert hash(File.read!(@provider)) == @provider_sha
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @provider)

    ctx =
      try do
        TurnFixture.setup(tags)
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    assert hash(File.read!(ctx.binary)) == @binary_sha
    TurnFixture.configure_model(ctx, %{})
    config = Path.join(ctx.fixture.codex_home, "config.toml")

    File.write!(
      config,
      ~s(cli_auth_credentials_store = "ephemeral"\n) <>
        "check_for_update_on_startup = false\nallow_login_shell = false\n" <>
        File.read!(config) <>
        "\n[memories]\ngenerate_memories = false\nuse_memories = false\n" <>
        "\n[analytics]\nenabled = false\n" <>
        ~s(\n[otel]\nexporter = "none"\ntrace_exporter = "none"\nmetrics_exporter = "none"\n) <>
        "\n[features]\nremote_plugin = false\napps = false\nshell_snapshot = false\nmemories = false\n"
    )

    original = File.read!(config)
    assert length(:binary.matches(original, @selection)) == 1
    on_exit(fn -> replace_config!(config, original) end)
    other = Path.join(ctx.root, "owned-hook-catalog-cwd λ")
    File.mkdir!(other)
    cwds = [ctx.fixture.workspace, other, ctx.fixture.workspace]

    inputs =
      Map.new(
        [
          Path.join(ctx.fixture.codex_home, "turn-models.json"),
          ctx.fixture.requests,
          @provider,
          __ENV__.file,
          Path.join(__DIR__, "support/model_fixture.ex"),
          Path.join(__DIR__, "support/turn_fixture.ex"),
          Path.join(__DIR__, "support/native_launch_fixture.ex"),
          Path.join(__DIR__, "support/stdio_session_fixture.ex")
        ],
        &{&1, snapshot(&1)}
      )

    capture = start_supervised!({Agent, fn -> %{out: [], in: [], bytes: 0} end})

    Map.merge(ctx, %{
      config: config,
      original: original,
      cwds: cwds,
      inputs: inputs,
      capture: capture
    })
  end

  test "native hooks catalog reports exact current configuration errors and recovers in place",
       ctx do
    session = start(ctx)
    pid = session.pid
    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    baseline = catalog(ctx.cwds, [])
    assert_catalog_twice(ctx, pid, baseline, ctx.original)

    for provider <- @missing_providers do
      # The pinned provider lookup defines this literal independently of the
      # native result. The catalog reports the requested cwd, not config.toml.
      message = "Model provider `#{provider}` not found"

      expected =
        %{
          "data" =>
            Enum.map(ctx.cwds, fn cwd ->
              %{
                "cwd" => cwd,
                "hooks" => [],
                "warnings" => [],
                "errors" => [%{"path" => cwd, "message" => message}]
              }
            end)
        }

      changed =
        String.replace(ctx.original, @selection, "model_provider = \"#{provider}\"\n",
          global: false
        )

      assert changed != ctx.original

      try do
        replace_config!(ctx.config, changed)
        assert_catalog_twice(ctx, pid, expected, changed)
      after
        replace_config!(ctx.config, ctx.original)
      end

      assert_catalog_twice(ctx, pid, baseline, ctx.original)
    end

    assert call(ctx, pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}
    assert_quiet(ctx, pid, ctx.original)
    assert_inventory(ctx)
    close(session)
    assert_inputs(ctx, ctx.original)
  end

  defp catalog(cwds, errors) do
    %{
      "data" =>
        Enum.map(cwds, fn cwd ->
          %{"cwd" => cwd, "hooks" => [], "warnings" => [], "errors" => errors}
        end)
    }
  end

  defp assert_catalog_twice(ctx, pid, expected, config) do
    for _ <- 1..2 do
      assert_inputs(ctx, config)
      assert call(ctx, pid, "hooks/list", %{"cwds" => ctx.cwds}) === expected
      assert_quiet(ctx, pid, config)
    end
  end

  defp replace_config!(path, contents) do
    temporary = path <> ".owned-hook-config-#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, contents, [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp assert_quiet(ctx, pid, config) do
    assert {:ok, events} = Session.drain(pid, 256)
    assert length(events) <= 256
    assert Enum.reduce(events, 0, &(byte_size(JSON.encode!(&1.wire)) + &2)) <= 1_048_576
    assert Session.uncertain_operations(pid) == []
    assert Session.interaction_outcomes(pid) == []

    assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind in [:server_request, :unsupported_server_request] or method == "error" or
               String.starts_with?(method, "thread/") or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)

    assert_inputs(ctx, config)
  end

  defp start(ctx) do
    assert_inputs(ctx, ctx.original)

    assert {:ok, pid} =
             Session.start_link(
               max_events: 256,
               max_event_bytes: 1_048_576,
               max_message_bytes: 65_536,
               transport:
                 {CaptureStdio,
                  [
                    capture: ctx.capture,
                    executable: ctx.binary,
                    args:
                      NativeLaunchFixture.ordinary_args(["app-server", "--listen", "stdio://"]),
                    cwd: ctx.fixture.workspace,
                    inherit_env: [],
                    max_message_bytes: 65_536,
                    env: %{
                      "HOME" => ctx.fixture.home,
                      "CODEX_HOME" => ctx.fixture.codex_home,
                      "TMPDIR" => ctx.root,
                      "PATH" => ctx.fixture.bin <> ":/usr/bin:/bin",
                      "CODEX_DISABLE_REMOTE_CONTROL" => "1",
                      "NO_COLOR" => "1",
                      "RUST_LOG" => "off"
                    }
                  ]}
             )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)
    id = request_id()
    info = %{"name" => "owned_hook_config_error", "version" => "0.1.0"}
    capabilities = %{"experimentalApi" => true}

    wire = %{
      "id" => id,
      "method" => "initialize",
      "params" => %{"clientInfo" => info, "capabilities" => capabilities}
    }

    assert {:ok, %{"id" => ^id, "result" => %{"platformOs" => "linux"}} = response} =
             Session.initialize(pid, info, capabilities, id: id, timeout_ms: 5_000)

    assert_exchange(ctx, wire, response)
    native = call(ctx, pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    %{pid: pid, connection: connection, native: native}
  end

  defp call(ctx, pid, method, params) do
    id = request_id()
    wire = %{"id" => id, "method" => method, "params" => params}

    case Session.request_native(pid, wire, timeout_ms: 5_000) do
      {:ok, %{"id" => ^id, "result" => result} = response} ->
        assert_exchange(ctx, wire, response)
        result

      other ->
        flunk("Native #{method} did not succeed: #{inspect(upstream_summary(other))}")
    end
  end

  defp upstream_summary({:error, %SamgitaProtocolCodex.Error{wire: wire}}) when is_map(wire),
    do: wire |> Map.get("error", %{}) |> Map.take(["code", "message"])

  defp upstream_summary(_reply), do: :unexpected_reply

  defp assert_exchange(ctx, wire, response) do
    ledger = Agent.get(ctx.capture, & &1)
    assert [sent] = Enum.filter(ledger.out, &(&1.wire["id"] == wire["id"]))
    assert [received] = Enum.filter(ledger.in, &(&1.wire["id"] == wire["id"]))
    assert sent.wire === wire
    assert sent.encoded === JSON.encode!(wire)
    assert JSON.decode!(sent.encoded) === wire
    assert received.wire === response
    assert JSON.decode!(received.encoded) === response
    assert Map.keys(response) |> Enum.sort() == ["id", "result"]
  end

  defp close(session) do
    assert :ok = Session.close(session.pid)
    assert :atomics.get(session.connection.owner.completion, 1) == 1
    assert Port.info(session.connection.port) == nil
    refute File.exists?("/proc/#{session.native}")
  end

  defp assert_inventory(ctx) do
    ledger = Agent.get(ctx.capture, & &1)

    assert Enum.map(ledger.out, & &1.wire["method"]) ===
             ["initialize", "server/diagnostics", "thread/loaded/list"] ++
               List.duplicate("hooks/list", 10) ++ ["thread/loaded/list"]

    assert length(ledger.in) == 14
    ids = Enum.map(ledger.out, & &1.wire["id"])
    assert length(Enum.uniq(ids)) == 14
    assert MapSet.new(Enum.map(ledger.in, & &1.wire["id"])) == MapSet.new(ids)
  end

  defp assert_inputs(ctx, config) do
    assert snapshot(ctx.config) === %{bytes: config, sha256: hash(config)}
    for {path, original} <- ctx.inputs, do: assert(snapshot(path) === original)
    assert ModelFixture.requests(ctx.fixture) == []
    for cwd <- Enum.uniq(ctx.cwds), do: assert(File.ls!(cwd) == [])
  end

  defp snapshot(path) do
    assert File.stat!(path).size <= 1_048_576
    bytes = File.read!(path)
    assert byte_size(bytes) <= 1_048_576
    %{bytes: bytes, sha256: hash(bytes)}
  end

  defp request_id,
    do: "owned-hook-config-error-#{System.unique_integer([:positive, :monotonic])}"

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
