defmodule SamgitaMemory.Formation.TelemetryHandlerTest do
  use SamgitaMemory.DataCase

  alias SamgitaMemory.Formation.TelemetryHandler
  alias SamgitaMemory.Memories
  alias SamgitaMemory.PRD

  setup do
    # Handler is already attached by the application supervisor
    :ok
  end

  describe "PRD requirement completed" do
    test "creates episodic memory from completion event" do
      {:ok, execution} = PRD.start_execution("telemetry-test-prd", title: "Test")

      :telemetry.execute(
        [:prd, :requirement, :completed],
        %{duration: 5000},
        %{
          prd_id: execution.id,
          requirement_id: "req-1",
          summary: "Implemented user auth",
          project: "test-proj",
          agent_id: "eng-backend"
        }
      )

      # Check that an episodic memory was created
      memories =
        Memories.retrieve(nil,
          scope: {:project, "test-proj"},
          tags: ["prd"]
        )

      assert length(memories) >= 1
    end
  end

  describe "agent error" do
    test "creates episodic memory from error event" do
      :telemetry.execute(
        [:agent, :error],
        %{},
        %{
          summary: "Failed to parse JSON response",
          agent_id: "eng-backend",
          project: "test-proj",
          error_type: "parse_error"
        }
      )

      memories =
        Memories.retrieve(nil,
          scope: {:project, "test-proj"},
          tags: ["error"]
        )

      assert length(memories) >= 1
      assert String.contains?(hd(memories).content, "Failed to parse JSON")
    end
  end

  describe "thinking revision" do
    test "creates procedural memory from revision event" do
      :telemetry.execute(
        [:thinking, :revision],
        %{},
        %{
          topic: "database design",
          original: "use NoSQL",
          revised: "use PostgreSQL",
          reason: "need relational queries",
          project: "test-proj",
          chain_id: "chain-1"
        }
      )

      memories =
        Memories.retrieve(nil,
          scope: {:project, "test-proj"},
          type: :procedural,
          tags: ["revision-pattern"]
        )

      assert length(memories) >= 1
      assert String.contains?(hd(memories).content, "database design")
    end
  end
end
