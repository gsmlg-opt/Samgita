defmodule Samgita.AgentsTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Error, Principal, Repo}
  alias Samgita.Domain.AgentCredential

  test "credentials are digests only and registry responses have no secrets" do
    a = agent_fixture()
    raw = String.duplicate("test-secret-", 4)

    attrs =
      command(%{
        "expected_version" => a["version"],
        "credential" => raw,
        "reference" => "vault://agent/key"
      })

    assert {:ok, credential} = Agents.put_credential(Principal.operator(), a["id"], attrs)
    assert {:ok, ^credential} = Agents.put_credential(Principal.operator(), a["id"], attrs)
    assert Repo.get!(AgentCredential, credential["id"]).digest == :crypto.hash(:sha256, raw)
    refute Jason.encode!(credential) =~ raw
    refute Map.has_key?(credential, "digest")
    assert {:ok, principal} = Agents.authenticate(raw)
    assert principal.agent_id == a["id"]
    assert {:error, %Error{code: :unauthorized}} = Agents.authenticate("bad")
  end

  test "stable identity differs from replacement connection and external session" do
    p = project_fixture()
    a = agent_fixture()
    member_fixture(p, a)
    {old, connection, raw} = connection_fixture(a)

    assert {:ok, session} =
             Agents.open_session(old, p["id"], command(%{"external_id" => "remote-session"}))

    assert session["id"] != connection["id"]
    assert {:ok, auth} = Agents.authenticate(raw)
    assert {:ok, next} = Agents.connect(auth, command(%{"agent_id" => Ecto.UUID.generate()}))
    assert next["agent_id"] == a["id"]
    assert next["generation"] == connection["generation"] + 1
    assert {:error, %Error{code: :unauthorized}} = Agents.list_sessions(old, p["id"])
    assert {:ok, current} = Agents.bind_connection(auth, next["id"])
    assert {:ok, %{"data" => [^session]}} = Agents.list_sessions(current, p["id"])
  end

  test "protocol and endpoint validation rejects unsupported or secret-bearing descriptors" do
    assert {:error, %Error{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{"name" => "bad", "protocol_version" => "future"})
             )

    assert {:error, %Error{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{
                 "name" => "bad",
                 "endpoint_metadata" => %{"url" => "https://user:secret@example.com/app-server"}
               })
             )

    assert {:error, %Error{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{"name" => "bad", "advertised_capabilities" => ["root-access"]})
             )
  end
end
