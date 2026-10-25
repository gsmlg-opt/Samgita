defmodule SamgitaCodexDriver.NativeCommandOutputStreamValuesTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{NativeLaunchFixture, Session, StdioSessionFixture}

  @moduletag :real_codex
  @moduletag timeout: 30_000
  @binary_sha "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @process_id "owned-command-output-streams"
  @request_id "owned-command-output-stream-request"
  @stdout "Owned stdout λ\0\xFF\n"
  @stderr "Owned stderr 🙂\0\xFE\n"
  @script ~S"""
  import os, pathlib, sys
  pathlib.Path(sys.argv[1]).write_text(str(os.getpid()), encoding="ascii")
  os.write(1, b"Owned stdout \xce\xbb\x00\xff\n")
  os.write(2, b"Owned stderr \xf0\x9f\x99\x82\x00\xfe\n")
  raise SystemExit(7)
  """

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
      if length(Agent.get(state.capture, & &1)) < 16 and byte_size(encoded) <= 8192 do
        with {:ok, next} <- Stdio.send(state, encoded) do
          Agent.update(state.capture, &(&1 ++ [JSON.decode!(encoded)]))
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

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: pinned CODEX_BINARY required"

    assert hash(File.read!(binary)) == @binary_sha
    python = System.find_executable("python3")
    assert is_binary(python), "BLOCKED_ENV: Python 3 required for owned native command"

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-command-streams-#{Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)}"
      )

    for directory <- ~w(home codex workspace tmp),
        do: File.mkdir_p!(Path.join(root, directory))

    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      binary: Path.expand(binary),
      python: python,
      workspace: Path.join(root, "workspace"),
      child_record: Path.join(root, "owned-command.pid"),
      capture: start_supervised!({Agent, fn -> [] end})
    }
  end

  test "native stdout and stderr labels retain exact bytes and complete before the correlated reply",
       ctx do
    {pid, native} = start(ctx)
    assert {:ok, startup} = Session.drain(pid)
    refute Enum.any?(startup, &(&1.wire["method"] == "command/exec/outputDelta"))

    request = %{
      "id" => @request_id,
      "method" => "command/exec",
      "params" => %{
        "command" => [ctx.python, "-I", "-c", @script, ctx.child_record],
        "processId" => @process_id,
        "cwd" => ctx.workspace,
        "streamStdoutStderr" => true,
        "timeoutMs" => 5_000,
        "outputBytesCap" => 4096
      }
    }

    requested_at = System.system_time(:millisecond)

    assert {:ok, %{"id" => @request_id, "result" => result}} =
             Session.request_native(pid, request, timeout_ms: 10_000)

    replied_at = System.system_time(:millisecond)
    assert result === %{"exitCode" => 7, "stdout" => "", "stderr" => ""}

    # Pinned command_exec.rs joins both output workers, whose notifications wait
    # for their send, before returning this response. No sleep/poll is required.
    assert {:ok, events} = Session.drain(pid)
    assert length(events) <= 16
    assert Enum.sum(Enum.map(events, &byte_size(JSON.encode!(&1.wire)))) <= 8192

    deltas = Enum.filter(events, &(&1.wire["method"] == "command/exec/outputDelta"))
    assert deltas != []
    assert Enum.map(deltas, & &1.sequence) == Enum.sort(Enum.map(deltas, & &1.sequence))
    assert Enum.uniq(Enum.map(deltas, & &1.sequence)) == Enum.map(deltas, & &1.sequence)
    assert Enum.uniq(Enum.map(deltas, & &1.generation)) == [Session.status(pid).generation]

    for event <- deltas do
      assert event.kind == :notification
      assert Enum.sort(Map.keys(event.wire)) == ~w(emittedAtMs method params)
      emitted_at = Map.fetch!(event.wire, "emittedAtMs")
      assert is_integer(emitted_at) and requested_at <= emitted_at and emitted_at <= replied_at
      params = event.wire["params"]
      assert Enum.sort(Map.keys(params)) == ~w(capReached deltaBase64 processId stream)
      assert params["processId"] == @process_id
      assert params["stream"] in ["stdout", "stderr"]
      assert params["capReached"] === false
      assert {:ok, bytes} = Base.decode64(params["deltaBase64"])
      assert bytes != ""
      assert Base.encode64(bytes) == params["deltaBase64"]
    end

    assert Enum.sort(Enum.uniq(Enum.map(deltas, & &1.wire["params"]["stream"]))) ==
             ["stderr", "stdout"]

    # Each pipe preserves its own bytes. The relative ordering of the two pipes
    # is deliberately unconstrained by the native server.
    assert output(deltas, "stdout") === @stdout
    assert output(deltas, "stderr") === @stderr
    assert {:ok, []} = Session.drain(pid)

    child = ctx.child_record |> File.read!() |> String.to_integer()
    assert child > 0 and child != native
    refute File.exists?("/proc/#{child}")

    assert call(pid, "thread/loaded/list", %{}) === %{"data" => [], "nextCursor" => nil}

    # No thread or inference request is issued: this is a native process API
    # operation without a model provider or synthetic app-server frames.
    captured = Agent.get(ctx.capture, & &1)

    assert Enum.map(captured, & &1["method"]) ==
             ~w(initialize initialized server/diagnostics command/exec thread/loaded/list)

    assert Enum.filter(captured, &(&1["method"] == "command/exec")) === [request]
    assert Session.uncertain_operations(pid) == []
    assert %{phase: :ready, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
    assert :ok = Session.close(pid)
    refute File.exists?("/proc/#{native}")
    refute File.exists?("/proc/#{child}")
  end

  defp output(events, stream) do
    events
    |> Enum.filter(&(&1.wire["params"]["stream"] == stream))
    |> Enum.map(&Base.decode64!(&1.wire["params"]["deltaBase64"]))
    |> IO.iodata_to_binary()
  end

  defp start(ctx) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {CaptureStdio,
           [
             capture: ctx.capture,
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
             cwd: ctx.workspace,
             inherit_env: [],
             env: %{
               "HOME" => Path.join(ctx.root, "home"),
               "CODEX_HOME" => Path.join(ctx.root, "codex"),
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => System.get_env("PATH", "/usr/bin:/bin"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off",
               "PYTHONDONTWRITEBYTECODE" => "1"
             }
           ]}
      )

    %{connection: connection} = :sys.get_state(pid)
    on_exit(fn -> StdioSessionFixture.close(pid, connection) end)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "owned_command_output_stream_values", "version" => "0.1.0"},
               %{"experimentalApi" => true},
               timeout_ms: 5_000
             )

    native = call(pid, "server/diagnostics", %{})["process"]["id"]
    assert is_integer(native) and native > 0
    assert hash(File.read!("/proc/#{native}/exe")) == @binary_sha
    {pid, native}
  end

  defp call(pid, method, params) do
    assert {:ok, %{"result" => result}} = Session.request(pid, method, params, timeout_ms: 5_000)
    result
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
