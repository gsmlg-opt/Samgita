defmodule SamgitaCodexDriver.NativeNotificationTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  test "complete initialized envelopes preserve missing, null, scalar and future fields" do
    pid = connection()
    before = Session.status(pid)

    for wire <- [
          %{"method" => "initialized"},
          %{"method" => "initialized", "params" => nil},
          %{"method" => "initialized", "params" => []},
          %{"method" => "initialized", "params" => "é🙂"},
          %{"method" => "initialized", "params" => false},
          %{
            "method" => "initialized",
            "params" => %{"nested" => [nil, 42, %{"text" => "é🙂"}]},
            "trace" => %{"traceparent" => "synthetic-trace", "future" => true},
            "future" => %{"preserved" => [nil, false]}
          }
        ] do
      assert {:ok, %{outcome: :sent_unconfirmed}} = Session.notify_native(pid, wire)
      assert_receive {:sent, ^pid, ^wire}
      assert Session.status(pid) == before
    end

    assert {:ok, []} = Session.drain(pid)
    assert [] = Session.uncertain_operations(pid)
    refute_receive {:sent, ^pid, _}
  end

  test "notifications during initialization and readiness do not consume correlation or alter phases" do
    pid = connection()
    call = begin_initialize(pid)
    before = :sys.get_state(pid)
    assert before.phase == :initializing
    wire = %{"method" => "initialized", "params" => nil}
    assert {:ok, %{outcome: :sent_unconfirmed}} = Session.notify_native(pid, wire)
    assert_receive {:sent, ^pid, ^wire}
    assert :sys.get_state(pid) == before

    finish_initialize(pid, call)
    before = :sys.get_state(pid)
    assert before.phase == :ready
    assert {:ok, %{outcome: :sent_unconfirmed}} = Session.notify_native(pid, wire)
    assert_receive {:sent, ^pid, ^wire}
    assert :sys.get_state(pid) == before
  end

  test "pinned validation rejects unknown methods while explicit wire validation preserves extensions" do
    pid = connection()
    wire = %{"method" => "future/notification", "params" => nil, "future" => [1, true]}

    assert {:error, %Error{code: :unsupported_method, uncertain: false}} =
             Session.notify_native(pid, wire)

    refute_receive {:sent, ^pid, _}

    assert {:ok, %{outcome: :sent_unconfirmed}} =
             Session.notify_native(pid, wire, validation: :wire)

    assert_receive {:sent, ^pid, ^wire}
  end

  test "initialization waits for its processed-state barrier before asserting transport output" do
    pid = connection()
    :ok = :sys.suspend(pid)
    caller = self()

    barrier =
      Task.async(fn ->
        receive do
          {:trace, ^caller, :send, {:"$gen_call", _, {:initialize, _, _, _}}, ^pid} ->
            receive do
              {:trace, ^caller, :send, {:"$gen_call", _, :status}, ^pid} ->
                :sys.resume(pid)
            end
        end
      end)

    :erlang.trace(self(), true, [:send, {:tracer, barrier.pid}])

    try do
      pending = begin_initialize(pid)
      assert :ok = Task.await(barrier)
      assert %{phase: :initializing, pending: 1} = Session.status(pid)
      finish_initialize(pid, pending)
      assert %{phase: :ready, pending: 0} = Session.status(pid)
    after
      :erlang.trace(self(), false, [:send])
      if Process.alive?(pid), do: :sys.resume(pid)
      Task.shutdown(barrier, :brutal_kill)
    end
  end

  test "malformed envelopes and non-keyword options send nothing and leave the session usable" do
    pid = connection()

    for wire <- [
          nil,
          [],
          %{},
          %{"method" => nil},
          %{"method" => "initialized", "id" => 1},
          %{"method" => "initialized", "id" => nil},
          %{"method" => "initialized", "result" => nil},
          %{"method" => "initialized", "error" => nil}
        ] do
      assert {:error, %Error{code: :invalid_envelope, uncertain: false}} =
               Session.notify_native(pid, wire)
    end

    for opts <- [nil, %{}, [:invalid], [{"validation", :wire}], [{:validation, :wire}, :bad]] do
      assert {:error, %Error{code: :invalid_options, uncertain: false}} =
               Session.notify_native(pid, %{"method" => "initialized"}, opts)
    end

    refute_receive {:sent, ^pid, _}
    assert %{phase: :new, pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "wire byte, depth and JSON bounds apply even to extension notifications" do
    pid = connection(max_message_bytes: 256)
    deep = Enum.reduce(1..65, nil, fn _, nested -> [nested] end)

    for {wire, code} <- [
          {%{"method" => "initialized", "future" => String.duplicate("x", 256)},
           :message_too_large},
          {%{"method" => "initialized", "future" => deep}, :message_too_deep},
          {%{"method" => "initialized", "future" => %{atom_key: true}}, :invalid_json},
          {%{"method" => "future/notification", "params" => self()}, :invalid_json}
        ] do
      assert {:error, %Error{code: ^code, uncertain: false}} =
               Session.notify_native(pid, wire, validation: :wire)
    end

    refute_receive {:sent, ^pid, _}
    assert %{phase: :new, pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "instance, generation and dispatch deadlines fence the local send" do
    pid = connection()
    %{instance_id: instance, generation: generation} = Session.status(pid)
    wire = %{"method" => "initialized"}

    for {opts, code} <- [
          {[expected_instance_id: "stale"], :stale_session},
          {[expected_generation: generation + 1], :stale_session},
          {[dispatch_deadline_ms: System.system_time(:millisecond) - 1], :dispatch_expired},
          {[dispatch_deadline_ms: nil], :invalid_deadline},
          {[dispatch_deadline_ms: "tomorrow"], :invalid_deadline}
        ] do
      assert {:error, %Error{code: ^code, uncertain: false}} =
               Session.notify_native(pid, wire, opts)
    end

    refute_receive {:sent, ^pid, _}

    assert {:ok, %{outcome: :sent_unconfirmed}} =
             Session.notify_native(pid, wire,
               expected_instance_id: instance,
               expected_generation: generation,
               dispatch_deadline_ms: System.system_time(:millisecond) + 10_000
             )

    assert_receive {:sent, ^pid, ^wire}
  end

  test "a queued notification checks its generation after an earlier reconnect" do
    pid = connection()
    %{generation: generation} = Session.status(pid)
    :ok = :sys.suspend(pid)
    reconnect_ref = make_ref()
    notify_ref = make_ref()
    send(pid, {:"$gen_call", {self(), reconnect_ref}, :reconnect})

    send(
      pid,
      {:"$gen_call", {self(), notify_ref},
       {:notify_native, %{"method" => "initialized"}, [expected_generation: generation]}}
    )

    :ok = :sys.resume(pid)
    assert_receive {^reconnect_ref, :ok}
    assert_receive {^notify_ref, {:error, %Error{code: :stale_session, uncertain: false}}}
    refute_receive {:sent, ^pid, _}
    assert Session.status(pid).generation == generation + 1
  end

  test "disconnected notifications fail locally and reconnect never replays a successful send" do
    pid = connection()
    wire = %{"method" => "initialized", "future" => "one-send"}
    assert {:ok, %{outcome: :sent_unconfirmed}} = Session.notify_native(pid, wire)
    assert_receive {:sent, ^pid, ^wire}
    send(pid, :drop_connection)
    assert %{phase: :disconnected} = Session.status(pid)

    assert {:error, %Error{code: :disconnected, uncertain: false}} =
             Session.notify_native(pid, wire)

    assert :ok = Session.reconnect(pid)
    assert %{phase: :new, generation: 2, pending: 0} = Session.status(pid)
    refute_receive {:sent, ^pid, _}
  end

  test "failed notification write exposes its uncertain wire and preserves pending mutation uncertainty" do
    pid = connection([], fail_method: "future/fail")
    finish_initialize(pid, begin_initialize(pid))
    pending = :gen_server.send_request(pid, {:request, "thread/start", %{}, [id: "pending"]})
    assert %{phase: :ready, pending: 1} = Session.status(pid)
    assert_received {:sent, ^pid, %{"id" => "pending"}}
    wire = %{"method" => "future/fail", "params" => nil, "future" => ["kept"]}

    assert {:error, %Error{code: :send_failed, uncertain: true, wire: ^wire}} =
             Session.notify_native(pid, wire, validation: :wire)

    assert_receive {:sent, ^pid, ^wire}
    assert_receive {:codex_driver, ^pid, {:gap, %{reason: :send_failed, generation: 1}}}

    assert {:reply, {:error, %Error{code: :send_failed, uncertain: true}}} =
             :gen_server.receive_response(pending, 5_000)

    assert [%{id: "pending", reason: :send_failed}] = Session.uncertain_operations(pid)
    assert %{phase: :disconnected, pending: 0, uncertain: 1} = Session.status(pid)
    assert :ok = Session.reconnect(pid)
    assert [%{id: "pending", reason: :send_failed}] = Session.uncertain_operations(pid)
    refute_receive {:sent, ^pid, _}
  end

  defp connection(opts \\ [], transport_opts \\ []) do
    {:ok, pid} =
      Session.start_link(
        Keyword.put(opts, :transport, {ScriptedTransport, [observer: self()] ++ transport_opts})
      )

    assert_receive {:transport_opened, ^pid}
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    pid
  end

  defp begin_initialize(pid) do
    pending =
      :gen_server.send_request(
        pid,
        {:initialize, %{"name" => "native_notification_test", "version" => "0.1.0"}, %{},
         [id: "initialize"]}
      )

    assert %{phase: :initializing, pending: 1} = Session.status(pid)
    assert_received {:sent, ^pid, %{"id" => "initialize", "method" => "initialize"}}
    pending
  end

  defp finish_initialize(pid, task) do
    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => "initialize", "result" => result}})
    assert {:reply, {:ok, %{"result" => ^result}}} = :gen_server.receive_response(task, 5_000)
    assert_receive {:sent, ^pid, %{"method" => "initialized"} = canonical}
    assert canonical == %{"method" => "initialized"}
  end
end
