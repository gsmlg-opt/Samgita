defmodule SamgitaCodexDriver.SessionConfidentialityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SamgitaCodexDriver.Session
  alias SamgitaProtocolCodex.Error

  @params_canary "owned-session-pending-params-canary-95a73"
  @message_canary "owned-session-native-message-canary-b2d48"
  @data_canary "owned-session-native-data-canary-c6e91"
  @env_canary "owned-session-explicit-env-canary-d4f82"
  @canaries [@params_canary, @message_canary, @data_canary, @env_canary]

  defmodule OwnedTransport do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport

    import Kernel, except: [send: 2]

    @impl true
    def open(opts) do
      owner = self()

      resource =
        spawn(fn ->
          monitor = Process.monitor(owner)

          receive do
            :stop -> :ok
            {:DOWN, ^monitor, :process, ^owner, _reason} -> :ok
          end
        end)

      state = opts |> Map.new() |> Map.merge(%{resource: resource, sent: []})
      Kernel.send(state.observer, {:owned_opened, owner, resource, state.env})

      if state[:open_gate] do
        receive do
          {:release_owned_open, ^resource} -> :ok
        after
          2_000 -> raise "owned replacement open gate unconfirmed"
        end
      end

      fault!(state, :open)
      {:ok, state}
    end

    @impl true
    def send(state, body) do
      wire = JSON.decode!(body)
      Kernel.send(state.observer, {:owned_sent, self(), wire})
      fault!(state, :send)
      {:ok, %{state | sent: [wire | state.sent]}}
    end

    @impl true
    def handle_info({:incoming, wire}, state),
      do: {:ok, [{:message, JSON.encode!(wire)}], state}

    def handle_info({:controlled_crash, _sensitive_last_message}, _state),
      do: raise("controlled_owned_session_confidentiality_crash")

    def handle_info({:arm_fault, role, kind}, state),
      do: {:ok, [], Map.put(state, :fault, {role, kind})}

    def handle_info(_message, state) do
      fault!(state, :handle_info)
      :unknown
    end

    @impl true
    def close(nil), do: :ok

    def close(state) do
      fault!(state, :close)
      monitor = Process.monitor(state.resource)
      Kernel.send(state.resource, :stop)

      receive do
        {:DOWN, ^monitor, :process, resource, _reason} ->
          Kernel.send(state.observer, {:owned_closed, self(), resource})
          fault!(state, :close_confirmed)
          :ok
      after
        2_000 -> raise "owned confidentiality fixture shutdown unconfirmed"
      end
    end

    @impl true
    def metadata(state) do
      fault!(state, :metadata)
      %{transport: :confidentiality_fixture, connected: true}
    end

    defp fault!(%{fault: {role, kind}} = state, role) do
      payload = %{"credential" => state.env}

      case kind do
        :raise ->
          failure = RuntimeError.exception("Owned callback failed: #{inspect(payload)}")
          :erlang.raise(:error, failure, [{__MODULE__, role, [payload], []}])

        :throw ->
          throw(payload)

        :exit ->
          exit(payload)
      end
    end

    defp fault!(_state, _role), do: :ok
  end

  defmodule SequencedOpenTransport do
    @moduledoc false
    @behaviour SamgitaCodexDriver.Transport
    import Kernel, except: [send: 2]

    @impl true
    def open(opts) do
      action =
        Agent.get_and_update(opts[:open_sequence], fn [action | rest] -> {action, rest} end)

      Kernel.send(opts[:observer], {:owned_open_attempt, self(), action})

      case action do
        :ok ->
          OwnedTransport.open(opts)

        {:error, failure} ->
          {:error, failure}

        {:fault, kind} ->
          OwnedTransport.open(Keyword.merge(opts, fault: {:open, kind}, open_gate: true))
      end
    end

    @impl true
    defdelegate send(state, body), to: OwnedTransport
    @impl true
    defdelegate handle_info(message, state), to: OwnedTransport
    @impl true
    defdelegate close(state), to: OwnedTransport
    @impl true
    defdelegate metadata(state), to: OwnedTransport
  end

  defmodule CrashLogHandler do
    @moduledoc false

    def adding_handler(config), do: {:ok, config}
    def removing_handler(_config), do: :ok

    def log(%{meta: %{pid: pid}} = event, %{config: %{session: pid, observer: observer}}) do
      send(observer, {:owned_crash_log, pid, event})
      :ok
    end

    def log(event, %{config: %{observer: observer}}) do
      send(observer, {:owned_raw_log, event})
      :ok
    end

    def log(_event, _config), do: :ok
  end

  test "default OTP status redacts traffic and preserves exact authorized results" do
    {pid, resource, resource_monitor} = ready()
    session_monitor = Process.monitor(pid)
    pending = pending_request(pid)
    wire = native_error()

    failed =
      Task.async(fn ->
        Session.request(pid, "thread/read", %{"threadId" => "owned-missing"}, id: wire["id"])
      end)

    assert_receive {:owned_sent, ^pid, %{"id" => "native-error"}}, 2_000
    send(pid, {:incoming, wire})
    assert {:error, %Error{code: :upstream_error, wire: ^wire} = failure} = Task.await(failed)
    assert failure.details == %{"upstream_code" => -32_000}
    assert failure.uncertain == false
    assert_redacted(inspect(failure, limit: :infinity, printable_limit: :infinity))
    assert_redacted(Exception.message(failure))

    # A real unmatched native response remains queued until the owner drains it.
    send(pid, {:incoming, wire})
    assert %{phase: :ready, pending: 1, buffered_events: 1} = Session.status(pid)
    assert_status_confidential(pid)
    assert {:ok, [%{kind: :late_response, wire: ^wire}]} = Session.drain(pid)

    result = %{
      "id" => "pending-sensitive",
      "result" => %{"preserved" => @params_canary, "nested" => [nil, @data_canary]}
    }

    send(pid, {:incoming, result})
    assert {:ok, ^result} = Task.await(pending)
    assert %{phase: :ready, pending: 0, buffered_events: 0, uncertain: 0} = Session.status(pid)
    assert Session.uncertain_operations(pid) == []
    assert :ok = Session.close(pid)
    assert_receive {:owned_closed, ^pid, ^resource}, 2_000
    assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
    assert_receive {:DOWN, ^session_monitor, :process, ^pid, :normal}, 2_000
    refute Process.alive?(pid)
  end

  test "explicit OTP debug exposes raw history outside formatted status" do
    {pid, resource, resource_monitor} = ready()
    session_monitor = Process.monitor(pid)
    pending = pending_request(pid)
    wire = native_error()
    send(pid, {:incoming, wire})
    assert %{pending: 1, buffered_events: 1} = Session.status(pid)
    assert_status_confidential(pid)

    # Privileged sys debugging retains raw events/state outside format_status.
    # Preserve this exposure as a positive regression, not a privacy guarantee.
    assert :ok = :sys.log(pid, true)
    assert %{pending: 1, buffered_events: 1} = Session.status(pid)

    assert {:status, ^pid, {:module, :gen_server}, parts} = :sys.get_status(pid)
    assert [dictionary, :running, _parent, debug, formatted] = parts

    assert_canaries(debug)
    assert_redacted(dictionary)
    assert_redacted(formatted)
    data = formatted |> Keyword.get_values(:data) |> List.flatten()
    assert {~c"State", :redacted} in data
    assert {~c"Logged events", []} in data

    assert :ok = :sys.log(pid, false)
    assert_status_confidential(pid)
    assert {:ok, [%{kind: :late_response, wire: ^wire}]} = Session.drain(pid)
    result = %{"id" => "pending-sensitive", "result" => %{"preserved" => @params_canary}}
    send(pid, {:incoming, result})
    assert {:ok, ^result} = Task.await(pending)
    assert %{pending: 0, buffered_events: 0, uncertain: 0} = Session.status(pid)
    assert :ok = Session.close(pid)
    assert_receive {:owned_closed, ^pid, ^resource}, 2_000
    assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
    assert_receive {:DOWN, ^session_monitor, :process, ^pid, :normal}, 2_000
    refute Process.alive?(pid)
  end

  test "owned callback failure is typed and redacted before OTP reporting and resource exit" do
    {pid, resource, resource_monitor} = ready()
    session_monitor = Process.monitor(pid)
    pending = pending_request(pid)
    wire = native_error()
    send(pid, {:incoming, wire})
    assert %{pending: 1, buffered_events: 1} = Session.status(pid)
    assert_status_confidential(pid)
    assert :ok = :sys.log(pid, true)
    assert %{pending: 1, buffered_events: 1} = Session.status(pid)

    # Inspect structured Logger events too: formatted CaptureLog output alone
    # could conceal sensitive fields through a struct's Inspect implementation.
    assert :ok =
             :logger.add_handler(CrashLogHandler, CrashLogHandler, %{
               level: :all,
               config: %{session: pid, observer: self()}
             })

    on_exit(fn -> :logger.remove_handler(CrashLogHandler) end)

    logs =
      capture_log(fn ->
        send(pid, {:controlled_crash, wire})

        assert {:error,
                %Error{
                  code: :transport_callback_failed,
                  details: %{"request_id" => "pending-sensitive"},
                  uncertain: true
                }} = Task.await(pending)

        assert_receive {:owned_closed, ^pid, ^resource}, 2_000
        assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
        assert %{phase: :disconnected, pending: 0, uncertain: 1} = Session.status(pid)

        assert [%{id: "pending-sensitive", reason: :transport_callback_failed}] =
                 Session.uncertain_operations(pid)

        assert :ok = Session.close(pid)
        assert_receive {:DOWN, ^session_monitor, :process, ^pid, :normal}, 2_000
        Logger.flush()
      end)

    assert logs == ""
    assert_redacted(logs)
    refute_receive {:owned_crash_log, ^pid, _event}
    assert :ok = :logger.remove_handler(CrashLogHandler)
    refute Process.alive?(pid)
    refute Process.alive?(resource)
    refute_receive {:owned_opened, ^pid, _, _}
    refute_receive {:owned_sent, ^pid, _}
  end

  for kind <- [:raise, :throw, :exit],
      role <- [:open, :send, :handle_info, :metadata, :close, :close_confirmed] do
    test "#{kind} in transport #{role} is contained before raw Logger emission" do
      assert :ok =
               :logger.add_handler(CrashLogHandler, CrashLogHandler, %{
                 level: :all,
                 config: %{observer: self()}
               })

      on_exit(fn -> :logger.remove_handler(CrashLogHandler) end)

      logs =
        capture_log(fn ->
          callback_failure(unquote(role), unquote(kind))
          Logger.flush()
        end)

      assert_redacted(logs)
      Enum.each(raw_logs([]), &assert_redacted/1)
      assert :ok = :logger.remove_handler(CrashLogHandler)
    end
  end

  defp callback_failure(:open, kind) do
    env = %{"OWNED_SYNTHETIC_CREDENTIAL" => @env_canary}
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error,
              %Error{code: :transport_callback_failed, details: %{"callback" => "open"}} = failure} =
               Session.start_link(
                 transport: {OwnedTransport, [observer: self(), env: env, fault: {:open, kind}]}
               )

      assert_receive {:owned_opened, pid, resource, ^env}, 2_000
      session_monitor = Process.monitor(pid)
      resource_monitor = Process.monitor(resource)
      assert_redacted(failure)
      assert_receive {:DOWN, ^session_monitor, :process, ^pid, _reason}, 2_000
      assert_receive {:DOWN, ^resource_monitor, :process, ^resource, _reason}, 2_000
      refute Process.alive?(resource)
      # OTP27 proc_lib flushes linked EXIT on failed initialization. The public
      # return and owner/resource monitors are the observable failure contract.
      refute_receive {:EXIT, ^pid, _reason}
      refute_receive {:owned_sent, ^pid, _}
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp callback_failure(role, kind) do
    {pid, resource, resource_monitor} = ready()
    monitor = Process.monitor(pid)
    pending = pending_request(pid)
    send(pid, {:arm_fault, role, kind})

    case role do
      :send ->
        assert {:error, %Error{code: :transport_callback_failed, uncertain: true}} =
                 Session.request(pid, "thread/start", %{}, id: "send-failed")

        assert_receive {:owned_sent, ^pid, %{"id" => "send-failed"}}, 2_000

      :metadata ->
        assert {:error,
                %Error{code: :transport_callback_failed, details: %{"callback" => "metadata"}}} =
                 Session.status(pid)

      :handle_info ->
        send(pid, {:callback_fault, native_error()})

      close when close in [:close, :close_confirmed] ->
        assert {:error,
                %Error{code: :transport_callback_failed, details: %{"callback" => "close"}}} =
                 Session.close(pid)
    end

    assert {:error, %Error{uncertain: true}} = Task.await(pending)
    expected_uncertain = if role == :send, do: 2, else: 1
    phase = if role in [:close, :close_confirmed], do: :shutdown_failed, else: :disconnected

    assert %{phase: ^phase, generation: 1, pending: 0, uncertain: ^expected_uncertain} =
             Session.status(pid)

    assert length(Session.uncertain_operations(pid)) == expected_uncertain
    refute_receive {:owned_opened, ^pid, _, _}
    refute_receive {:owned_sent, ^pid, _}

    if role in [:close, :close_confirmed] do
      assert {:error, %Error{code: :transport_callback_failed}} = Session.reconnect(pid)
      assert {:error, %Error{code: :transport_callback_failed}} = Session.close(pid)
      refute_receive {:owned_opened, ^pid, _, _}

      if role == :close do
        # Failed before confirmation: ownership guardian must still reap it when
        # this explicitly owned Session stops. Do not report successful close.
        assert Process.alive?(resource)
        refute_receive {:owned_closed, ^pid, ^resource}
      else
        assert_receive {:owned_closed, ^pid, ^resource}, 2_000
      end

      assert :ok = GenServer.stop(pid)
    else
      assert_receive {:owned_closed, ^pid, ^resource}, 2_000
      assert :ok = Session.close(pid)
    end

    assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 2_000
    refute Process.alive?(pid)
    refute Process.alive?(resource)
  end

  for kind <- [:raise, :throw, :exit] do
    @tag :replacement_open
    test "#{kind} during explicit replacement open terminates the resource owner" do
      assert :ok =
               :logger.add_handler(CrashLogHandler, CrashLogHandler, %{
                 level: :all,
                 config: %{observer: self()}
               })

      on_exit(fn -> :logger.remove_handler(CrashLogHandler) end)

      logs =
        capture_log(fn ->
          replacement_open_failure(unquote(kind))
          Logger.flush()
        end)

      assert_redacted(logs)
      Enum.each(raw_logs([]), &assert_redacted/1)
      assert :ok = :logger.remove_handler(CrashLogHandler)
    end
  end

  @tag :replacement_open
  test "a normally returned replacement open Error remains exact and permits an explicit retry" do
    failure = Error.new(:transport_connect_failed, %{"safe" => true}, wire: native_error())
    {pid, resource, resource_monitor} = sequenced_ready([:ok, {:error, failure}, :ok])
    pending = pending_request(pid)
    assert_receive {:owned_open_attempt, ^pid, :ok}, 2_000

    assert {:error, ^failure} = Session.reconnect(pid)
    assert_receive {:owned_open_attempt, ^pid, {:error, ^failure}}, 2_000
    assert_receive {:owned_closed, ^pid, ^resource}, 2_000
    assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
    assert {:error, %Error{code: :explicit_reconnect, uncertain: true}} = Task.await(pending)
    assert %{phase: :disconnected, generation: 1, pending: 0, uncertain: 1} = Session.status(pid)
    refute_receive {:owned_opened, ^pid, _, _}

    assert :ok = Session.reconnect(pid)
    assert_receive {:owned_open_attempt, ^pid, :ok}, 2_000
    assert_receive {:owned_opened, ^pid, next_resource, _env}, 2_000
    next_monitor = Process.monitor(next_resource)
    assert %{phase: :new, generation: 2, pending: 0, uncertain: 1} = Session.status(pid)
    refute_receive {:owned_sent, ^pid, _}
    assert :ok = Session.close(pid)
    assert_receive {:owned_closed, ^pid, ^next_resource}, 2_000
    assert_receive {:DOWN, ^next_monitor, :process, ^next_resource, :normal}, 2_000
    refute_receive {:owned_open_attempt, ^pid, _}
  end

  defp replacement_open_failure(kind) do
    {pid, resource, resource_monitor} = sequenced_ready([:ok, {:fault, kind}, :ok])
    session_monitor = Process.monitor(pid)
    pending = pending_request(pid)
    assert_receive {:owned_open_attempt, ^pid, :ok}, 2_000

    reconnect = Task.async(fn -> Session.reconnect(pid) end)
    assert_receive {:owned_open_attempt, ^pid, {:fault, ^kind}}, 2_000
    assert_receive {:owned_closed, ^pid, ^resource}, 2_000
    assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
    assert_receive {:owned_opened, ^pid, replacement, _env}, 2_000
    replacement_monitor = Process.monitor(replacement)
    assert Process.alive?(replacement)

    assert {:error,
            %Error{
              code: :explicit_reconnect,
              details: %{"request_id" => "pending-sensitive"},
              uncertain: true
            }} = Task.await(pending)

    send(pid, {:release_owned_open, replacement})

    assert {:error,
            %Error{code: :transport_callback_failed, details: %{"callback" => "open"}} = failure} =
             Task.await(reconnect)

    assert_redacted(failure)

    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :explicit_reconnect, generation: 1}}},
                   2_000

    terminal =
      receive do
        {:DOWN, ^session_monitor, :process, ^pid, reason} -> reason
      after
        2_000 -> :still_alive
      end

    if terminal == :still_alive do
      # Baseline diagnostic: demonstrate both the leaked partial allocation and
      # permitted replacement, then clean every owned resource before failing.
      assert Process.alive?(replacement)
      assert %{phase: :disconnected, generation: 1, uncertain: 1} = Session.status(pid)
      assert :ok = Session.reconnect(pid)
      assert_receive {:owned_open_attempt, ^pid, :ok}, 2_000
      assert_receive {:owned_opened, ^pid, next_resource, _env}, 2_000
      next_monitor = Process.monitor(next_resource)
      assert %{phase: :new, generation: 2, uncertain: 1} = Session.status(pid)
      assert Process.alive?(replacement)
      assert :ok = Session.close(pid)
      assert_receive {:owned_closed, ^pid, ^next_resource}, 2_000
      assert_receive {:DOWN, ^next_monitor, :process, ^next_resource, :normal}, 2_000
      assert_receive {:DOWN, ^session_monitor, :process, ^pid, :normal}, 2_000
    end

    assert_receive {:DOWN, ^replacement_monitor, :process, ^replacement, :normal}, 2_000
    refute Process.alive?(replacement)
    refute Process.alive?(pid)
    refute_receive {:owned_open_attempt, ^pid, _}
    refute_receive {:owned_sent, ^pid, _}

    assert terminal == :normal,
           "replacement open exception left its owner and partial allocation alive; another explicit reconnect succeeded"
  end

  defp sequenced_ready(actions) do
    sequence = start_supervised!({Agent, fn -> actions end}, id: make_ref())

    ready(
      transport:
        {SequencedOpenTransport,
         [
           observer: self(),
           env: %{"OWNED_SYNTHETIC_CREDENTIAL" => @env_canary},
           open_sequence: sequence
         ]}
    )
  end

  defp ready(overrides \\ []) do
    env = %{"OWNED_SYNTHETIC_CREDENTIAL" => @env_canary}

    pid =
      start_supervised!(
        {Session,
         Keyword.merge(
           [
             owner: self(),
             transport: {OwnedTransport, [observer: self(), env: env]},
             request_timeout_ms: 10_000
           ],
           overrides
         )},
        id: make_ref()
      )

    assert_receive {:owned_opened, ^pid, resource, ^env}, 2_000
    resource_monitor = Process.monitor(resource)

    initialize =
      Task.async(fn ->
        Session.initialize(pid, %{"name" => "confidentiality_test", "version" => "0.1.0"})
      end)

    assert_receive {:owned_sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "owned-fixture/0.163.0",
      "codexHome" => "/owned-synthetic-home",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => id, "result" => result}})
    assert {:ok, %{"id" => ^id, "result" => ^result}} = Task.await(initialize)
    assert_receive {:owned_sent, ^pid, %{"method" => "initialized"}}, 2_000
    {pid, resource, resource_monitor}
  end

  defp pending_request(pid) do
    wire = %{
      "id" => "pending-sensitive",
      "method" => "turn/start",
      "params" => %{
        "threadId" => "owned-thread",
        "input" => [%{"type" => "text", "text" => @params_canary}]
      }
    }

    task = Task.async(fn -> Session.request_native(pid, wire, validation: :wire) end)
    assert_receive {:owned_sent, ^pid, ^wire}, 2_000
    assert Session.status(pid).pending == 1
    task
  end

  defp native_error do
    %{
      "id" => "native-error",
      "error" => %{
        "code" => -32_000,
        "message" => @message_canary,
        "data" => %{"credential" => @data_canary, "nested" => [nil, @env_canary]}
      }
    }
  end

  defp assert_status_confidential(pid) do
    # Positive control uses privileged OTP access only on this owned fixture.
    # The transport retains actual sent frames, independently of OTP debugging.
    assert_canaries(:sys.get_state(pid))
    assert {:status, ^pid, {:module, :gen_server}, parts} = status = :sys.get_status(pid)
    assert [_dictionary, :running, _parent, [], _formatted] = parts
    assert_redacted(status)
  end

  defp assert_canaries(term) do
    raw = :erlang.term_to_binary(term)
    for canary <- @canaries, do: assert(raw =~ canary)
  end

  defp assert_redacted(term) do
    raw = :erlang.term_to_binary(term)
    rendered = inspect(term, limit: :infinity, printable_limit: :infinity)

    for canary <- @canaries do
      refute raw =~ canary
      refute rendered =~ canary
    end
  end

  defp raw_logs(events) do
    receive do
      {:owned_raw_log, event} -> raw_logs([event | events])
    after
      0 -> events
    end
  end
end
