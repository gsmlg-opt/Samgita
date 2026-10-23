defmodule Samgita.RuntimeRegistrationTest do
  use Samgita.DataCase, async: false
  import Samgita.DomainFixtures
  alias Samgita.{Agents, Principal}

  test "native runtime metadata does not replace ordinary Agent registration or grant membership" do
    assert {:ok, agent} =
             Agents.register(
               Principal.operator(),
               command(%{
                 "name" => "Ordinary runtime owner",
                 "runtime_driver" => "codex",
                 "runtime_version" => "0.163.0"
               })
             )

    assert agent["runtime_driver"] == "codex"
    assert agent["runtime_version"] == "0.163.0"
    assert agent["protocol"] == "samgita"
    assert agent["approved_capabilities"] == []
    refute Repo.exists?(from m in Samgita.Domain.ProjectAgent, where: m.agent_id == ^agent["id"])
    refute Repo.exists?(from a in Samgita.Domain.TaskAttempt, where: a.agent_id == ^agent["id"])
  end

  test "runtime versions are pinned and metadata is an operator command" do
    assert {:error, %{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{
                 "name" => "Wrong version",
                 "runtime_driver" => "codex",
                 "runtime_version" => "future"
               })
             )

    agent = agent_fixture()
    {principal, _, _} = connection_fixture(agent)

    assert {:error, %{code: :forbidden}} =
             Agents.update(
               principal,
               agent["id"],
               command(%{
                 "expected_version" => agent["version"],
                 "runtime_driver" => "codex",
                 "runtime_version" => "0.163.0"
               })
             )
  end
end
