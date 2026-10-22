defmodule Samgita.DomainFixtures do
  @moduledoc false
  alias Samgita.{Agents, Params, Platform, Principal, Projects}

  def command(attrs \\ %{}),
    do: Map.merge(%{"command_id" => Ecto.UUID.generate()}, Params.strings(attrs))

  def project_fixture(attrs \\ %{}) do
    {:ok, project} =
      Projects.create(
        Principal.operator(),
        command(Map.merge(%{"name" => "P3 project"}, Params.strings(attrs)))
      )

    project
  end

  def agent_fixture(attrs \\ %{}) do
    defaults = %{
      "name" => "Reference Agent",
      "advertised_capabilities" => SamgitaProtocol.capabilities(),
      "approved_capabilities" => SamgitaProtocol.capabilities()
    }

    {:ok, agent} =
      Agents.register(Principal.operator(), command(Map.merge(defaults, Params.strings(attrs))))

    agent
  end

  def credential_fixture(agent) do
    raw = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    {:ok, current} = Agents.get(Principal.operator(), agent["id"])

    {:ok, _} =
      Agents.put_credential(
        Principal.operator(),
        agent["id"],
        command(%{
          "expected_version" => current["version"],
          "credential" => raw,
          "reference" => "test-only"
        })
      )

    raw
  end

  def member_fixture(project, agent, roles \\ ~w(manager worker reviewer)) do
    {:ok, current} = Projects.get(Principal.operator(), project["id"])

    {:ok, member} =
      Projects.put_member(
        Principal.operator(),
        project["id"],
        command(%{
          "agent_id" => agent["id"],
          "roles" => roles,
          "expected_version" => current["version"]
        })
      )

    member
  end

  def connection_fixture(agent, raw \\ nil) do
    raw = raw || credential_fixture(agent)
    {:ok, principal} = Agents.authenticate(raw)
    {:ok, connection} = Agents.connect(principal, command())
    {:ok, bound} = Agents.bind_connection(principal, connection["id"])
    {bound, connection, raw}
  end

  def activate_fixture do
    {:ok, authority} = Platform.status(Principal.operator())

    if authority["owner"] == "hub" do
      authority
    else
      {:ok, active} =
        Platform.activate(
          Principal.operator(),
          command(%{
            "expected_version" => authority["version"],
            "evidence" => %{
              "legacy_fenced" => true,
              "effects_resolved" => true,
              "reference" => "isolated-P3-scratch-database"
            }
          })
        )

      active
    end
  end
end
