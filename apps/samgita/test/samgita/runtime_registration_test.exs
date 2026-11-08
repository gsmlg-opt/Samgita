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

  test "Codex runtime versions are not pinned but must be well formed" do
    for version <- ["0.163.0", "0.167.0", "1.0.0-alpha.1"] do
      assert {:ok, agent} =
               Agents.register(
                 Principal.operator(),
                 command(%{
                   "name" => "Codex " <> version,
                   "runtime_driver" => "codex",
                   "runtime_version" => version
                 })
               )

      assert agent["runtime_version"] == version
    end

    for version <- ["", "bad version", "-1", String.duplicate("9", 65)] do
      assert {:error, %{code: :invalid}} =
               Agents.register(
                 Principal.operator(),
                 command(%{
                   "name" => "Malformed version",
                   "runtime_driver" => "codex",
                   "runtime_version" => version
                 })
               )
    end

    assert {:error, %{code: :invalid}} =
             Agents.register(
               Principal.operator(),
               command(%{
                 "name" => "Unknown driver",
                 "runtime_driver" => "other",
                 "runtime_version" => "1.0.0"
               })
             )
  end

  test "runtime metadata is an operator command" do
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
