unless Code.ensure_loaded?(SamgitaCodexDriver.NativeLaunchFixture) do
  Code.require_file(
    Path.expand("../../../samgita_codex_driver/test/support/native_launch_fixture.ex", __DIR__)
  )
end

defmodule SamgitaWeb.CodexAuthorityRecordingWebSocket do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaCodexDriver.Transport.WebSocket

  @impl true
  def open(opts) do
    sent_path = Keyword.fetch!(opts, :authority_sent_path)

    with {:ok, connection} <- WebSocket.open(Keyword.delete(opts, :authority_sent_path)) do
      # The fixture creates this journal once. Reconnect must retain its prefix.
      {:ok, Map.put(connection, :authority_sent_path, sent_path)}
    end
  end

  @impl true
  def send(state, json) do
    File.write!(state.authority_sent_path, json <> "\n", [:append])
    WebSocket.send(state, json)
  end

  @impl true
  defdelegate handle_info(message, state), to: WebSocket
  @impl true
  defdelegate close(state), to: WebSocket
  @impl true
  defdelegate metadata(state), to: WebSocket
end

defmodule SamgitaWeb.CodexGenerationRuntimeFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Samgita.DomainFixtures, only: [command: 1]
  alias Samgita.{CodexRuntime, Repo}
  alias Samgita.Domain.NativeRuntimeBinding
  alias SamgitaCodexDriver.{ModelFixture, NativeLaunchFixture, Session}
  alias SamgitaCodexDriver.Transport.Stdio
  alias SamgitaWeb.CodexRuntimeFixture

  def pending do
    binary = System.fetch_env!("CODEX_BINARY")

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"

    Samgita.DomainFixtures.activate_fixture()
    root = Path.join(System.tmp_dir!(), "samgita-native-generation-#{Ecto.UUID.generate()}")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    fixture = ModelFixture.start(root, "command")
    File.write!(fixture.requests, "[]")
    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.mkdir!(Path.join(root, "tmp"))
    sent_path = Path.join(root, "native-sent.jsonl")
    File.write!(sent_path, "")
    {:ok, reservation} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(reservation)
    assert :ok = :gen_tcp.close(reservation)
    token = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    digest = Base.encode16(:crypto.hash(:sha256, token), case: :lower)

    {:ok, native_owner} =
      Stdio.open(
        executable: Path.expand(binary),
        args:
          NativeLaunchFixture.ordinary_args([
            "app-server",
            "--listen",
            "ws://127.0.0.1:#{port}",
            "--ws-auth",
            "capability-token",
            "--ws-token-sha256",
            digest
          ]),
        cwd: fixture.workspace,
        inherit_env: [],
        env: %{
          "HOME" => fixture.home,
          "CODEX_HOME" => fixture.codex_home,
          "TMPDIR" => Path.join(root, "tmp"),
          "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
          "SHELL" => Path.join(fixture.bin, "sh"),
          "CODEX_DISABLE_REMOTE_CONTROL" => "1",
          "NO_COLOR" => "1",
          "RUST_LOG" => "off"
        }
      )

    on_exit(fn ->
      assert :ok = Stdio.close(native_owner)
      assert :ok = ModelFixture.close(fixture)
      File.rm_rf!(root)
    end)

    await_listener(port, System.monotonic_time(:millisecond) + 10_000)

    {:ok, pid} =
      Session.start_link(
        transport:
          {SamgitaWeb.CodexAuthorityRecordingWebSocket,
           [
             url: "ws://127.0.0.1:#{port}/app-server",
             token: token,
             authority_sent_path: sent_path,
             connect_timeout_ms: 1_000
           ]}
      )

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: assert(:ok = Session.close(pid))
      after
        assert :ok = Stdio.close(native_owner)
      end
    end)

    ctx = CodexRuntimeFixture.registered_runtime("Owned native generation fixture", pid)

    CodexRuntimeFixture.invoke(ctx, pid, "initialize", %{
      "clientInfo" => %{"name" => "samgita_native_generation", "version" => "0.1.0"},
      "capabilities" => %{"experimentalApi" => true}
    })

    thread =
      CodexRuntimeFixture.invoke(ctx, pid, "thread/start", %{
        "model" => "mock-model",
        "modelProvider" => "fixture",
        "cwd" => fixture.workspace,
        "sandbox" => "read-only",
        "approvalPolicy" => "on-request",
        "ephemeral" => false,
        "historyMode" => "paginated",
        "config" => %{"web_search" => "disabled"}
      })["thread"]["id"]

    turn =
      CodexRuntimeFixture.invoke(ctx, pid, "turn/start", %{
        "threadId" => thread,
        "input" => [%{"type" => "text", "text" => "Owned native generation fixture"}]
      })["turn"]["id"]

    {event, recorded} =
      await_approval(ctx, pid, System.monotonic_time(:millisecond) + 25_000)

    assert event.wire["method"] == "item/commandExecution/requestApproval"
    assert event.wire["params"]["threadId"] == thread
    assert event.wire["params"]["turnId"] == turn
    assert event.wire["params"]["cwd"] == fixture.workspace

    assert event.wire["params"]["command"] ==
             Path.join(fixture.bin, "sh") <> " -c 'printf samgita_fixture'"

    ctx = Map.put(ctx, :event_id, recorded["id"])
    CodexRuntimeFixture.assert_native_pending(ctx, pid, fixture, event)

    %{
      ctx: ctx,
      pid: pid,
      fixture: fixture,
      event: event,
      recorded: recorded,
      native_owner: native_owner,
      sent_path: sent_path
    }
  end

  defp await_listener(port, deadline) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 25) do
      {:ok, socket} ->
        assert :ok = :gen_tcp.close(socket)

      {:error, _} ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Owned generation listener startup deadline"

        receive do
        after
          min(remaining, 10) -> :ok
        end

        await_listener(port, deadline)
    end
  end

  defp await_approval(ctx, pid, deadline) do
    assert {:ok, events} = Session.drain(pid)
    recorded = Enum.map(events, &{&1, record_event(ctx, &1)})

    case Enum.filter(recorded, fn {event, _} -> event.kind == :server_request end) do
      [{event, record}] ->
        {event, record}

      [] ->
        remaining = deadline - System.monotonic_time(:millisecond)
        assert remaining > 0, "Owned generation approval startup deadline"

        receive do
          {:codex_driver, ^pid, :events_available} -> :ok
          {:codex_driver, ^pid, {:gap, _}} -> flunk("Unexpected initial generation gap")
        after
          min(remaining, 20) -> :ok
        end

        await_approval(ctx, pid, deadline)

      _ ->
        flunk("Unexpected additional native generation approval")
    end
  end

  defp record_event(ctx, event) do
    runtime = Repo.get!(NativeRuntimeBinding, ctx.runtime["id"])

    assert {:ok, recorded} =
             CodexRuntime.record_event(
               ctx.principal,
               ctx.project["id"],
               runtime.id,
               command(%{
                 "expected_version" => runtime.version,
                 "proof" => ctx.proof,
                 "instance_id" => runtime.instance_id,
                 "driver_generation" => event.generation,
                 "source_sequence" => event.sequence,
                 "native" => event.wire
               })
             )

    recorded
  end
end
