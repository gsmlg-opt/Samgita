defmodule SamgitaCodexDriver.RetainedOutputNotificationContractTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.{Error, Schema, Wire}

  @method "item/fileChange/outputDelta"
  @params %{
    "threadId" => "synthetic-thread",
    "turnId" => "synthetic-turn",
    "itemId" => "synthetic-patch"
  }

  test "synthetic retained legacy output validates and round trips without native emission evidence" do
    for delta <- ["", "Synthetic λ🙂\n\u0000\"\\"] do
      params = Map.put(@params, "delta", delta)
      assert :ok = Schema.validate_notification(:server_notification, @method, params)
      wire = %{"method" => @method, "params" => params}
      assert {:ok, encoded} = Wire.encode(wire)
      assert {:ok, ^wire} = Wire.decode(encoded)
    end

    params = Map.put(@params, "delta", "Synthetic retained output")

    for field <- ~w(threadId turnId itemId delta), bad <- [:missing, nil, 17] do
      invalid =
        if bad == :missing, do: Map.delete(params, field), else: Map.put(params, field, bad)

      assert {:error, %Error{code: :schema_violation}} =
               Schema.validate_notification(:server_notification, @method, invalid)
    end
  end

  test "scripted retained output stays an unchanged notification and cannot settle an RPC" do
    for experimental <- [false, true] do
      pid = ready(experimental)

      pending =
        Task.async(fn -> Session.request(pid, "thread/list", %{}, id: "synthetic-read") end)

      assert_receive {:sent, ^pid, %{"method" => "thread/list", "id" => "synthetic-read"}}, 2_000

      wire = %{
        "method" => @method,
        "params" => Map.put(@params, "delta", "Synthetic λ🙂\n"),
        "future" => %{"retained" => [nil, true]}
      }

      send(pid, {:incoming, wire})
      assert_receive {:codex_driver, ^pid, :events_available}, 2_000
      assert {:ok, [%{kind: :notification, wire: ^wire} = event]} = Session.drain(pid)
      refute Map.has_key?(event, :handle)
      assert %{phase: :ready, pending: 1, interactions: 0, uncertain: 0} = Session.status(pid)
      assert Task.yield(pending, 0) == nil
      refute_receive {:sent, ^pid, %{"result" => _}}, 0

      reply = %{"id" => "synthetic-read", "result" => %{"data" => [], "nextCursor" => nil}}
      send(pid, {:incoming, reply})
      assert {:ok, ^reply} = Task.await(pending)
      assert %{phase: :ready, pending: 0, interactions: 0, uncertain: 0} = Session.status(pid)
      assert :ok = Session.close(pid)
    end
  end

  defp ready(experimental) do
    {:ok, pid} = Session.start_link(transport: {ScriptedTransport, observer: self()})
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    assert_receive {:transport_opened, ^pid}

    task =
      Task.async(fn ->
        Session.initialize(pid, %{"name" => "synthetic_retained_output", "version" => "0.1.0"}, %{
          "experimentalApi" => experimental
        })
      end)

    assert_receive {:sent, ^pid, %{"method" => "initialize", "id" => id}}, 2_000

    send(
      pid,
      {:incoming,
       %{
         "id" => id,
         "result" => %{
           "userAgent" => "synthetic",
           "codexHome" => "/synthetic",
           "platformFamily" => "unix",
           "platformOs" => "linux"
         }
       }}
    )

    assert {:ok, _} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
    pid
  end
end
