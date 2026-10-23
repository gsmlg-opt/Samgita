defmodule SamgitaCodexDriver.InitializationTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  for experimental <- [false, true] do
    @tag experimental: experimental
    test "only matching validated success emits canonical initialized once, experimental=#{experimental}",
         context do
      pid = connection()
      id = "successful-initialize"
      task = begin_initialize(pid, id, %{"experimentalApi" => context.experimental})
      response = success(id)
      unrelated = success("unmatched-initialize")

      send(pid, {:incoming, unrelated})
      assert %{phase: :initializing, pending: 1} = Session.status(pid)
      assert_late_response(pid, unrelated)
      refute_initialized(pid)
      refute_task_reply(task)

      send(pid, {:incoming, response})
      assert {:ok, ^response} = Task.await(task)
      assert %{phase: :ready, pending: 0, generation: 1} = Session.status(pid)
      assert_initialized(pid)

      send(pid, {:incoming, response})
      assert %{phase: :ready, pending: 0} = Session.status(pid)
      assert_late_response(pid, response)
      refute_initialized(pid)
      assert :ok = Session.close(pid)
    end
  end

  test "upstream initialization error and its late success emit no notification" do
    pid = connection()
    id = "rejected-initialize"
    task = begin_initialize(pid, id)

    error = %{
      "id" => id,
      "error" => %{"code" => -32_600, "message" => "Synthetic initialization rejection"}
    }

    send(pid, {:incoming, error})

    assert {:error, %Error{code: :upstream_error, wire: ^error, uncertain: false}} =
             Task.await(task)

    assert %{phase: :new, pending: 0} = Session.status(pid)
    refute_initialized(pid)

    late = success(id)
    send(pid, {:incoming, late})
    assert %{phase: :new, pending: 0} = Session.status(pid)
    assert_late_response(pid, late)
    refute_initialized(pid)
    assert :ok = Session.close(pid)
  end

  for malformed <- [:missing_fields, :wrong_type] do
    @tag malformed: malformed
    test "malformed initialize result disconnects without initialized, variant=#{malformed}",
         context do
      pid = connection()
      id = "malformed-initialize"
      task = begin_initialize(pid, id)

      result =
        if context.malformed == :missing_fields,
          do: %{},
          else: Map.put(success(id)["result"], "platformOs", 42)

      send(pid, {:incoming, %{"id" => id, "result" => result}})
      assert {:error, %Error{code: :schema_violation, uncertain: false}} = Task.await(task)

      assert %{
               phase: :disconnected,
               pending: 0,
               gap: %{reason: :invalid_response},
               transport: %{connected: false}
             } = Session.status(pid)

      assert_received {:transport_closed, ^pid}
      refute_initialized(pid)
      send(pid, {:incoming, success(id)})
      assert %{phase: :disconnected, pending: 0} = Session.status(pid)
      refute_initialized(pid)
      assert :ok = Session.close(pid)
    end
  end

  test "initialize deadline closes the connection and late success cannot establish readiness" do
    pid = connection()
    id = "expired-initialize"
    task = begin_initialize(pid, id, %{}, timeout_ms: 500)
    assert {:error, %Error{code: :deadline_exceeded, uncertain: false}} = Task.await(task)

    assert %{
             phase: :disconnected,
             pending: 0,
             gap: %{reason: :initialization_deadline_exceeded}
           } = Session.status(pid)

    assert_received {:transport_closed, ^pid}
    refute_initialized(pid)
    send(pid, {:incoming, success(id)})
    assert %{phase: :disconnected, pending: 0} = Session.status(pid)
    refute_initialized(pid)
    assert :ok = Session.close(pid)
  end

  test "failed initialized send disconnects and never returns initialize success" do
    pid = connection(fail_method: "initialized")
    id = "notification-send-failure"
    task = begin_initialize(pid, id)
    send(pid, {:incoming, success(id)})

    assert {:error, %Error{code: :initialization_send_failed, uncertain: false}} =
             Task.await(task)

    assert %{
             phase: :disconnected,
             pending: 0,
             gap: %{reason: :initialization_send_failed}
           } = Session.status(pid)

    # ScriptedTransport records the attempted write before returning its failure.
    assert_initialized(pid)
    assert_received {:transport_closed, ^pid}
    send(pid, {:incoming, success(id)})
    assert %{phase: :disconnected, pending: 0} = Session.status(pid)
    refute_initialized(pid)
    assert :ok = Session.close(pid)
  end

  test "reconnect requires a fresh handshake and old IDs cannot complete the new pending handshake" do
    pid = connection()
    abandoned_id = "first-generation-pending"
    abandoned = begin_initialize(pid, abandoned_id)
    assert :ok = Session.reconnect(pid)
    assert {:error, %Error{code: :explicit_reconnect, uncertain: false}} = Task.await(abandoned)
    assert_received {:transport_closed, ^pid}
    assert_received {:transport_opened, ^pid}
    assert %{phase: :new, generation: 2, pending: 0} = Session.status(pid)
    refute_initialized(pid)
    assert {:error, %Error{code: :not_initialized}} = Session.request(pid, "thread/list")

    second_id = "second-generation-initialize"
    second = begin_initialize(pid, second_id)
    old_response = success(abandoned_id)
    send(pid, {:incoming, old_response})
    assert %{phase: :initializing, generation: 2, pending: 1} = Session.status(pid)
    assert_late_response(pid, old_response)
    refute_initialized(pid)
    refute_task_reply(second)
    second_response = success(second_id)
    send(pid, {:incoming, second_response})
    assert {:ok, ^second_response} = Task.await(second)
    assert %{phase: :ready, generation: 2, pending: 0} = Session.status(pid)
    assert_initialized(pid)

    assert :ok = Session.reconnect(pid)
    assert_received {:transport_closed, ^pid}
    assert_received {:transport_opened, ^pid}
    assert %{phase: :new, generation: 3, pending: 0} = Session.status(pid)
    refute_initialized(pid)
    assert {:error, %Error{code: :not_initialized}} = Session.request(pid, "thread/list")

    third_id = "third-generation-initialize"
    third = begin_initialize(pid, third_id)
    send(pid, {:incoming, second_response})
    assert %{phase: :initializing, generation: 3, pending: 1} = Session.status(pid)
    assert_late_response(pid, second_response)
    refute_initialized(pid)
    refute_task_reply(third)
    third_response = success(third_id)
    send(pid, {:incoming, third_response})
    assert {:ok, ^third_response} = Task.await(third)
    assert %{phase: :ready, generation: 3, pending: 0} = Session.status(pid)
    assert_initialized(pid)
    assert :ok = Session.close(pid)
  end

  defp connection(transport_opts \\ []) do
    opts = [
      owner: self(),
      transport: {ScriptedTransport, Keyword.put(transport_opts, :observer, self())}
    ]

    pid = start_supervised!({Session, opts}, id: make_ref())
    assert_receive {:transport_opened, ^pid}, 2_000
    pid
  end

  defp begin_initialize(pid, id, capabilities \\ %{}, opts \\ []) do
    info = %{"name" => "samgita_initialization_test", "version" => "0.1.0"}
    opts = Keyword.put(opts, :id, id)
    task = Task.async(fn -> Session.initialize(pid, info, capabilities, opts) end)

    assert_receive {:sent, ^pid,
                    %{
                      "id" => ^id,
                      "method" => "initialize",
                      "params" => %{"clientInfo" => ^info, "capabilities" => ^capabilities}
                    }},
                   2_000

    assert %{phase: :initializing, pending: 1} = Session.status(pid)
    refute_initialized(pid)
    task
  end

  defp success(id) do
    %{
      "id" => id,
      "result" => %{
        "userAgent" => "codex/0.163.0",
        "codexHome" => "/synthetic-initialization-home",
        "platformFamily" => "unix",
        "platformOs" => "linux"
      }
    }
  end

  defp assert_initialized(pid) do
    assert_received {:sent, ^pid, wire}
    assert wire == %{"method" => "initialized"}
    refute_initialized(pid)
  end

  defp refute_initialized(pid), do: refute_received({:sent, ^pid, %{"method" => "initialized"}})

  defp refute_task_reply(%Task{ref: ref}), do: refute_received({^ref, _result})

  defp assert_late_response(pid, wire) do
    assert {:ok, [%{kind: :late_response, wire: ^wire}]} = Session.drain(pid)
  end
end
