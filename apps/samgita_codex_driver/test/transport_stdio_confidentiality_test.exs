defmodule SamgitaCodexDriver.TransportStdioConfidentialityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias SamgitaCodexDriver.Transport.Stdio.Owner
  alias SamgitaProtocolCodex.Error

  @env_canary "owned-stdio-start-env-canary-38a61"
  @arg_canary "owned-stdio-start-arg-canary-90b27"
  @canaries [@env_canary, @arg_canary]
  @marker "owned_stdio_start_confidentiality_capture_control"

  defmodule RawLogHandler do
    @moduledoc false

    def adding_handler(config), do: {:ok, config}
    def removing_handler(_config), do: :ok

    def log(event, %{config: %{observer: observer}}) do
      send(observer, {:owned_stdio_log, event})
      :ok
    end
  end

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-stdio-confidentiality-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "the owned port startup boundary redacts explicit arguments and environment", %{dir: dir} do
    assert {:unix, :linux} = :os.type()
    launcher = Path.join(dir, "owned-absent-python")
    refute File.exists?(launcher)

    # Exercise the actual Owner/OS boundary independently of Stdio's earlier
    # executable validation. No filesystem race or mocked Port failure is used.
    # This does not qualify a normal-input public Stdio startup failure profile.
    control_options = [
      :binary,
      :exit_status,
      :use_stdio,
      :hide,
      {:args, [@arg_canary]},
      {:env, [{~c"OWNED_STDIO_SYNTHETIC_CREDENTIAL", String.to_charlist(@env_canary)}]}
    ]

    control =
      try do
        port = Port.open({:spawn_executable, launcher}, control_options)
        Port.close(port)
        :unexpected_port_open
      catch
        :error, reason -> {reason, __STACKTRACE__}
      end

    assert {:enoent, stacktrace} = control

    assert Enum.any?(stacktrace, fn
             {:erlang, :open_port, [{:spawn_executable, ^launcher}, ^control_options], _} -> true
             _ -> false
           end)

    for canary <- @canaries, do: assert(:erlang.term_to_binary(control) =~ canary)
    assert launcher_ports(launcher) == []

    observer = self()
    tracer = spawn(fn -> trace_owned_start(observer, %{}) end)
    on_exit(fn -> if Process.alive?(tracer), do: Process.exit(tracer, :kill) end)

    assert :ok =
             :logger.add_handler(RawLogHandler, RawLogHandler, %{
               level: :all,
               config: %{observer: self()}
             })

    on_exit(fn -> :logger.remove_handler(RawLogHandler) end)

    logs =
      capture_log(fn ->
        assert {:tracer, []} = :erlang.trace_info(self(), :tracer)
        assert 1 = :erlang.trace(self(), true, [:procs, :set_on_spawn, {:tracer, tracer}])

        result =
          try do
            Owner.open(launcher, control_options)
          after
            :erlang.trace(self(), false, [:procs, :set_on_spawn])
          end

        # Retain cleanup even if a future regression unexpectedly opens a port.
        if match?({:ok, _, _}, result) do
          {:ok, owner, _port} = result
          Owner.close(owner)
        end

        send(self(), {:owned_stdio_open_result, result})
        assert_receive {:owned_stdio_spawn, ^tracer, owner, mfa}, 2_000
        assert :erlang.term_to_binary(mfa) =~ Atom.to_string(Owner)

        # A start failure can return before proc_lib logs its crash. The traced
        # exit occurs after reporting; a monitor independently confirms death.
        assert_receive {:owned_stdio_exit, ^tracer, ^owner}, 2_000
        assert_receive {:owned_stdio_down, ^tracer, ^owner}, 2_000
        refute Process.alive?(owner)
        assert launcher_ports(launcher) == []

        delivery = :erlang.trace_delivered(self())
        assert_receive {:trace_delivered, _tracee, ^delivery}, 2_000
        barrier = make_ref()
        send(tracer, {:barrier, barrier})
        assert_receive {:owned_stdio_trace_complete, ^tracer, ^barrier, [^owner]}, 2_000

        Logger.error(@marker)
        Logger.flush()
      end)

    assert_receive {:owned_stdio_open_result, result}, 2_000
    events = drain_logs([])
    assert logs =~ @marker
    assert Enum.any?(events, &(inspect(&1, limit: :infinity) =~ @marker))
    assert :ok = :logger.remove_handler(RawLogHandler)

    tracer_monitor = Process.monitor(tracer)
    send(tracer, :stop)
    assert_receive {:DOWN, ^tracer_monitor, :process, ^tracer, :normal}, 2_000

    assert_redacted(events)
    assert_redacted(logs)
    assert_redacted(result)

    assert {:error,
            %Error{code: :process_start_failed, wire: nil, details: %{}, uncertain: false}} =
             result
  end

  defp trace_owned_start(observer, owners) do
    receive do
      {:trace, ^observer, :spawn, owner, mfa} ->
        monitor = Process.monitor(owner)
        send(observer, {:owned_stdio_spawn, self(), owner, mfa})
        trace_owned_start(observer, Map.put(owners, owner, monitor))

      {:trace, owner, :exit, _reason} when is_map_key(owners, owner) ->
        send(observer, {:owned_stdio_exit, self(), owner})
        trace_owned_start(observer, owners)

      {:DOWN, monitor, :process, owner, _reason} when is_map_key(owners, owner) ->
        if owners[owner] == monitor, do: send(observer, {:owned_stdio_down, self(), owner})
        trace_owned_start(observer, owners)

      {:barrier, reference} ->
        send(observer, {:owned_stdio_trace_complete, self(), reference, Map.keys(owners)})
        trace_owned_start(observer, owners)

      :stop ->
        :ok

      _message ->
        trace_owned_start(observer, owners)
    end
  end

  defp launcher_ports(launcher) do
    Enum.filter(Port.list(), fn port ->
      case Port.info(port, :name) do
        {:name, name} -> List.to_string(name) == launcher
        nil -> false
      end
    end)
  end

  defp drain_logs(events) do
    receive do
      {:owned_stdio_log, event} -> drain_logs([event | events])
    after
      0 -> Enum.reverse(events)
    end
  end

  defp assert_redacted(term) do
    raw = :erlang.term_to_binary(term)
    rendered = inspect(term, limit: :infinity, printable_limit: :infinity)

    for canary <- @canaries do
      refute raw =~ canary
      refute rendered =~ canary
    end
  end
end
