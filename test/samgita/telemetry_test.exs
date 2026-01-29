defmodule Samgita.TelemetryTest do
  use ExUnit.Case, async: true

  test "emits agent task start event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_start]])

    Samgita.Telemetry.agent_task_start(%{agent_type: "eng-backend", project_id: "p1"})

    assert_received {[:samgita, :agent, :task_start], ^ref, %{system_time: _},
                     %{agent_type: "eng-backend"}}
  end

  test "emits agent task complete event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_complete]])

    Samgita.Telemetry.agent_task_complete(
      %{agent_type: "eng-backend"},
      %{duration_ms: 100, tokens: 500}
    )

    assert_received {[:samgita, :agent, :task_complete], ^ref, %{duration_ms: 100, tokens: 500},
                     %{agent_type: "eng-backend"}}
  end

  test "emits phase transition event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :project, :phase_transition]])

    Samgita.Telemetry.phase_transition("p1", :bootstrap, :discovery)

    assert_received {[:samgita, :project, :phase_transition], ^ref, _,
                     %{project_id: "p1", from: :bootstrap, to: :discovery}}
  end
end
