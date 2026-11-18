defmodule Samgita.AgentIngressPairingTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias Samgita.{AgentIngress, Agents, Error, Principal, Repo}
  alias Samgita.Domain.{Agent, AgentCredential}

  # Approval/authentication coverage is retained but is not part of the allowed
  # functional selection while the repository verification restriction applies.
  @moduletag :device_pairing

  test "pending device becomes a connected route only after confirmation and native readiness" do
    socket = fake_socket()
    raw = token()

    assert {:pending, id} = AgentIngress.connect(socket, bootstrap(raw))
    pending = Enum.find(AgentIngress.snapshot().pending, &(&1.id == id))
    assert pending.name == "Synapsis device"
    assert pending.implementation == "synapsis"
    refute inspect(AgentIngress.snapshot()) =~ raw
    refute Map.has_key?(pending, :digest)
    refute Repo.exists?(AgentCredential)

    assert {:ok, agent} = AgentIngress.approve(Principal.operator(), id, command())
    assert_receive {:socket_approved, ^socket, connection, principal}, 1_000
    assert connection["agent_id"] == agent["id"]
    assert principal.connection_id == connection["id"]

    snapshot = AgentIngress.snapshot()
    refute Enum.any?(snapshot.pending, &(&1.id == id))
    assert snapshot.connected[agent["id"]].state == :initializing
    assert :ok = AgentIngress.ready(socket, principal)
    assert AgentIngress.snapshot().connected[agent["id"]].state == :connected
    assert {:ok, remembered} = Agents.authenticate_device(raw)
    assert remembered.agent_id == agent["id"]
    refute inspect(AgentIngress.snapshot()) =~ raw
  end

  test "rejected requests cannot be approved later or leave remembered trust" do
    socket = fake_socket()
    raw = token()
    assert {:pending, id} = AgentIngress.connect(socket, bootstrap(raw))

    assert :ok = AgentIngress.reject(Principal.operator(), id)
    assert_receive {:socket_closed, ^socket}, 1_000

    assert {:error, %Error{code: :not_found}} =
             AgentIngress.approve(Principal.operator(), id, command())

    assert :unknown = Agents.authenticate_device(raw)
    refute Repo.exists?(AgentCredential)
    refute Enum.any?(AgentIngress.snapshot().pending, &(&1.id == id))
  end

  test "expired requests cannot be approved later or leave remembered trust" do
    socket = fake_socket()
    raw = token()
    assert {:pending, id} = AgentIngress.connect(socket, bootstrap(raw))

    # Deliver the same expiry message as the owned five-minute timer. The next
    # call is ordered after it, so no wall-clock sleep is necessary.
    send(AgentIngress, {:pending_expired, id})

    assert {:error, %Error{code: :not_found}} =
             AgentIngress.approve(Principal.operator(), id, command())

    assert_receive {:socket_closed, ^socket}, 1_000
    assert :unknown = Agents.authenticate_device(raw)
    refute Repo.exists?(AgentCredential)
  end

  test "remembered token opens a new generation without another pending request" do
    first_socket = fake_socket()
    raw = token()
    assert {:pending, id} = AgentIngress.connect(first_socket, bootstrap(raw))
    assert {:ok, agent} = AgentIngress.approve(Principal.operator(), id, command())
    assert_receive {:socket_approved, ^first_socket, first, _principal}, 1_000

    second_socket = fake_socket()

    assert {:ok, second, resumed} = AgentIngress.connect(second_socket, bootstrap(raw))
    assert second["agent_id"] == agent["id"]
    assert second["generation"] == first["generation"] + 1
    assert resumed.connection_id == second["id"]
    assert_receive {:socket_closed, ^first_socket}, 1_000
    refute Enum.any?(AgentIngress.snapshot().pending, &(&1.id == id))
    assert AgentIngress.snapshot().connected[agent["id"]].connection_id == second["id"]
    assert Repo.aggregate(Agent, :count) == 1
    assert Repo.aggregate(AgentCredential, :count) == 1
  end

  test "concurrent confirmations consume a pending request once and create one generation" do
    socket = fake_socket()
    raw = token()
    assert {:pending, id} = AgentIngress.connect(socket, bootstrap(raw))

    results =
      for _ <- 1..3 do
        Task.async(fn -> AgentIngress.approve(Principal.operator(), id, command()) end)
      end
      |> Enum.map(&Task.await(&1, 5_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, %Error{code: :not_found}}, &1)) == 2
    assert_receive {:socket_approved, ^socket, connection, _principal}, 1_000
    assert connection["generation"] == 1
    refute_receive {:socket_approved, ^socket, _, _}, 50
    assert Repo.aggregate(Agent, :count) == 1
    assert Repo.aggregate(AgentCredential, :count) == 1
  end

  defp bootstrap(raw) do
    %{
      "type" => "agent/connect",
      "name" => "Synapsis device",
      "implementation" => "synapsis",
      "device_token" => raw
    }
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp fake_socket do
    owner = self()

    socket =
      spawn(fn ->
        monitor = Process.monitor(owner)
        socket_loop(owner, monitor)
      end)

    on_exit(fn ->
      monitor = Process.monitor(socket)
      send(socket, :stop)

      receive do
        {:DOWN, ^monitor, :process, ^socket, _} -> :ok
      after
        1_000 ->
          Process.demonitor(monitor, [:flush])
          Process.exit(socket, :kill)
      end
    end)

    socket
  end

  defp socket_loop(owner, monitor) do
    receive do
      {:agent_ingress_approved, connection, principal} ->
        send(owner, {:socket_approved, self(), connection, principal})
        socket_loop(owner, monitor)

      {:agent_ingress_close, _reason} ->
        send(owner, {:socket_closed, self()})

      :stop ->
        :ok

      {:DOWN, ^monitor, :process, ^owner, _reason} ->
        :ok
    end
  end
end
