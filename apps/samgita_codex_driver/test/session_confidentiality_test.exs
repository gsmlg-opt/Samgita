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
  @crash "controlled_owned_session_confidentiality_crash"

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
      {:ok, state}
    end

    @impl true
    def send(state, body) do
      wire = JSON.decode!(body)
      Kernel.send(state.observer, {:owned_sent, self(), wire})
      {:ok, %{state | sent: [wire | state.sent]}}
    end

    @impl true
    def handle_info({:incoming, wire}, state),
      do: {:ok, [{:message, JSON.encode!(wire)}], state}

    def handle_info({:controlled_crash, _sensitive_last_message}, _state),
      do: raise("controlled_owned_session_confidentiality_crash")

    def handle_info(_message, _state), do: :unknown

    @impl true
    def close(nil), do: :ok

    def close(state) do
      monitor = Process.monitor(state.resource)
      Kernel.send(state.resource, :stop)

      receive do
        {:DOWN, ^monitor, :process, resource, _reason} ->
          Kernel.send(state.observer, {:owned_closed, self(), resource})
          :ok
      after
        2_000 -> raise "owned confidentiality fixture shutdown unconfirmed"
      end
    end

    @impl true
    def metadata(_state), do: %{transport: :confidentiality_fixture, connected: true}
  end

  defmodule CrashLogHandler do
    @moduledoc false

    def adding_handler(config), do: {:ok, config}
    def removing_handler(_config), do: :ok

    def log(%{meta: %{pid: pid}} = event, %{config: %{session: pid, observer: observer}}) do
      send(observer, {:owned_crash_log, pid, event})
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

  test "owned Session crash redacts OTP reports and settles pending work before resource exit" do
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
                  code: :session_stopped,
                  details: %{"request_id" => "pending-sensitive"},
                  uncertain: true
                }} = Task.await(pending)

        assert_receive {:owned_closed, ^pid, ^resource}, 2_000
        assert_receive {:DOWN, ^resource_monitor, :process, ^resource, :normal}, 2_000
        assert_receive {:DOWN, ^session_monitor, :process, ^pid, reason}, 2_000
        assert {%RuntimeError{message: @crash}, stacktrace} = reason
        assert is_list(stacktrace) and stacktrace != []
        assert_redacted(reason)
        Logger.flush()
      end)

    assert logs =~ @crash
    assert_redacted(logs)
    assert_receive {:owned_crash_log, ^pid, event}, 2_000
    events = crash_logs(pid, [event])
    assert Enum.any?(events, &(inspect(&1, limit: :infinity) =~ @crash))
    Enum.each(events, &assert_redacted/1)
    assert :ok = :logger.remove_handler(CrashLogHandler)
    refute Process.alive?(pid)
    refute Process.alive?(resource)
    refute_receive {:owned_opened, ^pid, _, _}
    refute_receive {:owned_sent, ^pid, _}
  end

  defp ready do
    env = %{"OWNED_SYNTHETIC_CREDENTIAL" => @env_canary}

    pid =
      start_supervised!(
        {Session,
         owner: self(),
         transport: {OwnedTransport, [observer: self(), env: env]},
         request_timeout_ms: 10_000},
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

  defp crash_logs(pid, events) do
    receive do
      {:owned_crash_log, ^pid, event} -> crash_logs(pid, [event | events])
    after
      0 -> events
    end
  end
end
