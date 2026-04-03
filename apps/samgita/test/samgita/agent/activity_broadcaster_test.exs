defmodule Samgita.Agent.ActivityBroadcasterTest do
  use ExUnit.Case, async: true

  alias Samgita.Agent.ActivityBroadcaster

  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------

  defp agent_data do
    %{
      id: "agent-123",
      agent_type: "eng-backend",
      project_id: "project-456"
    }
  end

  # ---------------------------------------------------------------------------
  # state_change_payload/2
  # ---------------------------------------------------------------------------

  describe "state_change_payload/2" do
    test "returns a map with project_id, agent_id, agent_type, and state" do
      data = agent_data()
      payload = ActivityBroadcaster.state_change_payload(data, :idle)

      assert payload.project_id == data.project_id
      assert payload.agent_id == data.id
      assert payload.agent_type == data.agent_type
      assert payload.state == :idle
    end

    test "reflects the given state atom" do
      data = agent_data()

      for state <- [:idle, :reason, :act, :reflect, :verify] do
        payload = ActivityBroadcaster.state_change_payload(data, state)
        assert payload.state == state
      end
    end
  end

  # ---------------------------------------------------------------------------
  # activity_payload/3
  # ---------------------------------------------------------------------------

  describe "activity_payload/3" do
    test "returns a map with expected keys" do
      data = agent_data()
      payload = ActivityBroadcaster.activity_payload(data, :act, "doing work")

      assert Map.has_key?(payload, :project_id)
      assert Map.has_key?(payload, :agent_id)
      assert Map.has_key?(payload, :agent_type)
      assert Map.has_key?(payload, :state)
      assert Map.has_key?(payload, :message)
    end

    test "passes through short messages unchanged" do
      data = agent_data()
      short_msg = "short message"
      payload = ActivityBroadcaster.activity_payload(data, :idle, short_msg)

      assert payload.message == short_msg
    end

    test "truncates messages longer than 500 characters" do
      data = agent_data()
      long_message = String.duplicate("x", 600)
      payload = ActivityBroadcaster.activity_payload(data, :idle, long_message)

      assert byte_size(payload.message) < byte_size(long_message)
      assert String.ends_with?(payload.message, "...")
    end

    test "truncated message starts with the first 500 chars of the original" do
      data = agent_data()
      long_message = String.duplicate("a", 400) <> String.duplicate("b", 200)
      payload = ActivityBroadcaster.activity_payload(data, :idle, long_message)

      assert String.starts_with?(payload.message, String.duplicate("a", 400))
    end

    test "message of exactly 500 characters is not truncated" do
      data = agent_data()
      exact_message = String.duplicate("z", 500)
      payload = ActivityBroadcaster.activity_payload(data, :idle, exact_message)

      assert payload.message == exact_message
    end
  end

  # ---------------------------------------------------------------------------
  # telemetry_metadata/2
  # ---------------------------------------------------------------------------

  describe "telemetry_metadata/2" do
    test "returns a map with all expected keys" do
      data = agent_data()
      meta = ActivityBroadcaster.telemetry_metadata(data, :reflect)

      assert Map.has_key?(meta, :system_time)
      assert Map.has_key?(meta, :agent_id)
      assert Map.has_key?(meta, :agent_type)
      assert Map.has_key?(meta, :project_id)
      assert Map.has_key?(meta, :state)
    end

    test "contains the correct agent data values" do
      data = agent_data()
      meta = ActivityBroadcaster.telemetry_metadata(data, :verify)

      assert meta.agent_id == data.id
      assert meta.agent_type == data.agent_type
      assert meta.project_id == data.project_id
      assert meta.state == :verify
    end

    test "system_time is an integer" do
      data = agent_data()
      meta = ActivityBroadcaster.telemetry_metadata(data, :idle)

      assert is_integer(meta.system_time)
    end
  end
end
