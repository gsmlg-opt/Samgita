defmodule Samgita.AgentDevicesTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures

  alias Samgita.{Agents, Error, Principal, Repo}
  alias Samgita.Domain.{Agent, AgentCredential, CommandReceipt, DomainEvent, ProjectAgent}

  # These are approval/authentication checks. They are intentionally outside the
  # permitted functional verification selection while AGENTS.md restricts them.
  @moduletag :device_pairing

  test "operator confirmation creates digest-only trust without granting Project membership" do
    raw = token()
    attrs = pairing(raw)

    assert :unknown = Agents.authenticate_device(raw)
    assert {:ok, agent} = Agents.pair_device(Principal.operator(), attrs)
    assert {:ok, ^agent} = Agents.pair_device(Principal.operator(), attrs)

    assert agent["endpoint_metadata"] == %{"transport" => "inbound_websocket"}
    assert agent["advertised_capabilities"] == ["project_events.v1"]
    assert agent["approved_capabilities"] == ["project_events.v1"]
    assert Repo.aggregate(Agent, :count) == 1
    assert Repo.aggregate(AgentCredential, :count) == 1
    assert Repo.aggregate(ProjectAgent, :count) == 0

    credential = Repo.one!(AgentCredential)
    assert credential.digest == :crypto.hash(:sha256, raw)
    assert credential.reference == "device:" <> attrs["request_id"]
    assert {:ok, principal} = Agents.authenticate_device(raw)
    assert principal.agent_id == agent["id"]
    assert {:ok, ^principal} = Agents.device_principal(credential.digest)
    assert {:ok, ^principal} = Agents.authenticate(raw)

    receipt = Repo.one!(CommandReceipt)
    event = Repo.one!(DomainEvent)
    refute inspect(receipt) =~ raw
    refute inspect(event) =~ raw
    refute inspect(agent) =~ raw
  end

  test "remembered device resumes through a new fenced connection generation" do
    raw = token()
    assert {:ok, agent} = Agents.pair_device(Principal.operator(), pairing(raw))
    assert {:ok, principal} = Agents.authenticate_device(raw)
    assert {:ok, first} = Agents.connect(principal, command())
    assert {:ok, old} = Agents.bind_connection(principal, first["id"])

    assert {:ok, resumed} = Agents.authenticate_device(raw)
    assert {:ok, second} = Agents.connect(resumed, command())
    assert second["agent_id"] == agent["id"]
    assert second["generation"] == first["generation"] + 1
    assert {:error, %Error{code: :unauthorized}} = Agents.bind_connection(old, first["id"])
    assert {:ok, current} = Agents.bind_connection(resumed, second["id"])
    assert current.generation == second["generation"]
    assert Repo.aggregate(AgentCredential, :count) == 1
  end

  test "existing Agent binding keeps identity and memberships and rejects a stale selection" do
    project = project_fixture()
    agent = agent_fixture(%{"name" => "Existing coordinator", "implementation" => "synapsis"})
    member_fixture(project, agent, ["manager"])
    raw = token()
    attrs = Map.merge(pairing(raw), %{"agent_id" => agent["id"], "expected_version" => 0})

    assert {:error, %Error{code: :stale_version}} =
             Agents.pair_device(Principal.operator(), attrs)

    assert :unknown = Agents.authenticate_device(raw)
    attrs = Map.put(attrs, "expected_version", agent["version"])
    assert {:ok, paired} = Agents.pair_device(Principal.operator(), attrs)
    assert paired["id"] == agent["id"]
    assert paired["name"] == "Existing coordinator"
    assert paired["endpoint_metadata"] == %{"transport" => "inbound_websocket"}
    assert Repo.one!(ProjectAgent).roles == ["manager"]
  end

  test "revoked or disabled remembered devices cannot become new pending applicants" do
    raw = token()
    assert {:ok, agent} = Agents.pair_device(Principal.operator(), pairing(raw))
    assert {:ok, principal} = Agents.authenticate_device(raw)
    assert {:ok, connection} = Agents.connect(principal, command())
    credential = Repo.one!(AgentCredential)
    {:ok, current} = Agents.get(Principal.operator(), agent["id"])

    assert {:ok, _} =
             Agents.revoke_credential(
               Principal.operator(),
               agent["id"],
               command(%{
                 "expected_version" => current["version"],
                 "credential_id" => credential.id
               })
             )

    assert {:error, %Error{code: :unauthorized}} = Agents.authenticate_device(raw)
    assert {:error, %Error{code: :unauthorized}} = Agents.device_principal(credential.digest)

    assert {:error, %Error{code: :unauthorized}} =
             Agents.bind_connection(principal, connection["id"])

    assert {:error, %Error{code: :conflict}} =
             Agents.pair_device(Principal.operator(), pairing(raw))

    other_raw = token()
    assert {:ok, other} = Agents.pair_device(Principal.operator(), pairing(other_raw))

    assert {:ok, _} =
             Agents.update(
               Principal.operator(),
               other["id"],
               command(%{"expected_version" => other["version"], "enabled" => false})
             )

    assert {:error, %Error{code: :unauthorized}} = Agents.authenticate_device(other_raw)
  end

  test "ordinary credentials do not bypass device confirmation and cannot be paired again" do
    agent = agent_fixture(%{"endpoint_metadata" => %{"transport" => "inbound_websocket"}})
    raw = credential_fixture(agent)

    assert {:ok, _} = Agents.authenticate(raw)
    assert {:error, %Error{code: :unauthorized}} = Agents.authenticate_device(raw)

    assert {:error, %Error{code: :conflict}} =
             Agents.pair_device(Principal.operator(), pairing(raw))
  end

  test "inbound endpoint has no outbound URL and pairing rejects malformed digests" do
    assert {:error, %Error{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{
                 "name" => "Invalid mixed direction",
                 "endpoint_metadata" => %{
                   "transport" => "inbound_websocket",
                   "url" => "wss://example.test/app-server"
                 }
               })
             )

    assert {:error, %Error{code: :invalid}} =
             Agents.pair_device(
               Principal.operator(),
               Map.put(pairing(token()), "device_digest", String.duplicate("x", 64))
             )

    assert Repo.aggregate(Agent, :count) == 0
    assert Repo.aggregate(AgentCredential, :count) == 0
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  defp pairing(raw) do
    command(%{
      "request_id" => Ecto.UUID.generate(),
      "device_digest" => Base.encode16(:crypto.hash(:sha256, raw), case: :lower),
      "name" => "Synapsis device",
      "implementation" => "synapsis"
    })
  end
end
