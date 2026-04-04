defmodule Samgita.Domain.AgentMessageTest do
  use Samgita.DataCase, async: true

  alias Samgita.Domain.AgentMessage

  describe "changeset/2" do
    test "valid with all required fields" do
      cs =
        AgentMessage.changeset(%AgentMessage{}, %{
          project_id: Ecto.UUID.generate(),
          sender_agent_id: "eng-backend-1",
          recipient_agent_id: "eng-frontend-1",
          message_type: "notify",
          content: "API endpoint /users is ready"
        })

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = AgentMessage.changeset(%AgentMessage{}, %{})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).sender_agent_id
    end

    test "validates message_type inclusion" do
      cs =
        AgentMessage.changeset(%AgentMessage{}, %{
          project_id: Ecto.UUID.generate(),
          sender_agent_id: "a",
          recipient_agent_id: "b",
          message_type: "invalid",
          content: "test"
        })

      refute cs.valid?
    end

    test "accepts broadcast recipient" do
      cs =
        AgentMessage.changeset(%AgentMessage{}, %{
          project_id: Ecto.UUID.generate(),
          sender_agent_id: "eng-backend-1",
          recipient_agent_id: "*",
          message_type: "notify",
          content: "Database schema updated"
        })

      assert cs.valid?
    end

    test "defaults depth to 0" do
      cs =
        AgentMessage.changeset(%AgentMessage{}, %{
          project_id: Ecto.UUID.generate(),
          sender_agent_id: "a",
          recipient_agent_id: "b",
          message_type: "notify",
          content: "test"
        })

      assert Ecto.Changeset.get_field(cs, :depth) == 0
    end

    test "auto-sets inserted_at" do
      cs =
        AgentMessage.changeset(%AgentMessage{}, %{
          project_id: Ecto.UUID.generate(),
          sender_agent_id: "a",
          recipient_agent_id: "b",
          message_type: "notify",
          content: "test"
        })

      assert Ecto.Changeset.get_field(cs, :inserted_at)
    end
  end
end
