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

  test "emits agent task failure event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_failure]])

    Samgita.Telemetry.agent_task_failure(
      %{agent_type: "eng-qa", error: "timeout"},
      %{duration_ms: 5000, retry_count: 2}
    )

    assert_received {[:samgita, :agent, :task_failure], ^ref,
                     %{duration_ms: 5000, retry_count: 2},
                     %{agent_type: "eng-qa", error: "timeout"}}
  end

  test "emits agent spawned event" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :spawned]])

    Samgita.Telemetry.agent_spawned("project-123", "eng-frontend", node())

    assert_received {[:samgita, :agent, :spawned], ^ref, %{count: 1},
                     %{project_id: "project-123", agent_type: "eng-frontend", node: _}}
  end

  test "agent task start includes system_time measurement" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_start]])

    before = System.system_time()
    Samgita.Telemetry.agent_task_start(%{agent_type: "data-ml"})
    after_time = System.system_time()

    assert_received {[:samgita, :agent, :task_start], ^ref, %{system_time: time}, _}
    assert time >= before
    assert time <= after_time
  end

  test "phase transition includes system_time measurement" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :project, :phase_transition]])

    Samgita.Telemetry.phase_transition("p2", :development, :qa)

    assert_received {[:samgita, :project, :phase_transition], ^ref, %{system_time: time},
                     %{from: :development, to: :qa}}

    assert is_integer(time)
  end

  test "agent task complete passes through arbitrary measurements" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_complete]])

    measurements = %{duration_ms: 250, tokens: 1200, chars: 5000}
    Samgita.Telemetry.agent_task_complete(%{agent_type: "eng-api"}, measurements)

    assert_received {[:samgita, :agent, :task_complete], ^ref,
                     %{duration_ms: 250, tokens: 1200, chars: 5000}, _}
  end

  test "agent task failure passes through arbitrary measurements" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:samgita, :agent, :task_failure]])

    measurements = %{duration_ms: 0, retry_count: 0}
    metadata = %{agent_type: "ops-sre", error: "connection_refused"}

    Samgita.Telemetry.agent_task_failure(metadata, measurements)

    assert_received {[:samgita, :agent, :task_failure], ^ref,
                     %{duration_ms: 0, retry_count: 0},
                     %{agent_type: "ops-sre", error: "connection_refused"}}
  end
end
