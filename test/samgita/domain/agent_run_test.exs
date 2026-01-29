defmodule Samgita.Domain.AgentRunTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.AgentRun

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        AgentRun.changeset(%AgentRun{}, %{
          agent_type: "eng-backend",
          project_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid without agent_type" do
      changeset =
        AgentRun.changeset(%AgentRun{}, %{project_id: Ecto.UUID.generate()})

      refute changeset.valid?
      assert %{agent_type: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without project_id" do
      changeset = AgentRun.changeset(%AgentRun{}, %{agent_type: "eng-backend"})
      refute changeset.valid?
      assert %{project_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "defaults status to idle" do
      changeset =
        AgentRun.changeset(%AgentRun{}, %{
          agent_type: "eng-backend",
          project_id: Ecto.UUID.generate()
        })

      agent_run = Ecto.Changeset.apply_changes(changeset)
      assert agent_run.status == :idle
    end

    test "defaults counters to zero" do
      changeset =
        AgentRun.changeset(%AgentRun{}, %{
          agent_type: "eng-backend",
          project_id: Ecto.UUID.generate()
        })

      agent_run = Ecto.Changeset.apply_changes(changeset)
      assert agent_run.total_tasks == 0
      assert agent_run.total_tokens == 0
      assert agent_run.total_duration_ms == 0
    end

    test "accepts optional fields" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        AgentRun.changeset(%AgentRun{}, %{
          agent_type: "eng-frontend",
          project_id: Ecto.UUID.generate(),
          node: "node1@localhost",
          pid: "#PID<0.123.0>",
          status: :act,
          total_tasks: 5,
          total_tokens: 10_000,
          total_duration_ms: 50_000,
          started_at: now,
          ended_at: now
        })

      assert changeset.valid?
    end

    test "statuses/0 returns all RARV cycle states" do
      assert AgentRun.statuses() == [:idle, :reason, :act, :reflect, :verify, :failed]
    end
  end
end
