defmodule Samgita.Agent.ActivityBroadcaster do
  @moduledoc """
  Centralizes PubSub broadcasting and telemetry emission for agent workers.

  Extracted from `Samgita.Agent.Worker` to make the broadcasting logic
  reusable and independently testable.

  The `data` argument passed to all public functions must be a map or struct
  containing at minimum the keys: `id`, `agent_type`, `project_id`.
  """

  @max_message_length 500

  @doc """
  Broadcasts an agent state change over PubSub and persists the new status
  to the database via the active agent run record.
  """
  @spec broadcast_state_change(map(), atom()) :: :ok
  def broadcast_state_change(data, state) do
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "project:#{data.project_id}",
      {:agent_state_changed, data.id, state}
    )

    update_agent_run_status(data, state)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Broadcasts an activity log entry over PubSub by delegating to
  `Samgita.Events.build_log_entry/5` and `Samgita.Events.activity_log/2`.
  """
  @spec broadcast_activity(map(), atom(), String.t(), keyword()) :: :ok
  def broadcast_activity(data, state, message, opts \\ []) do
    entry = Samgita.Events.build_log_entry(:agent, data.id, state, message, opts)
    Samgita.Events.activity_log(data.project_id, entry)
  end

  @doc """
  Emits a telemetry event for an agent state transition.
  """
  @spec emit_state_transition(map(), atom()) :: :ok
  def emit_state_transition(data, state) do
    :telemetry.execute(
      [:samgita, :agent, :state_transition],
      %{system_time: System.system_time()},
      %{
        agent_id: data.id,
        agent_type: data.agent_type,
        project_id: data.project_id,
        state: state
      }
    )
  rescue
    _ -> :ok
  end

  @doc """
  Emits a telemetry event for an agent error.
  """
  @spec emit_error(map(), atom(), term()) :: :ok
  def emit_error(data, state, error) do
    :telemetry.execute(
      [:samgita, :agent, :error],
      %{system_time: System.system_time()},
      %{
        agent_id: data.id,
        agent_type: data.agent_type,
        project_id: data.project_id,
        state: state,
        error: error
      }
    )
  rescue
    _ -> :ok
  end

  # ---------------------------------------------------------------------------
  # Pure helpers — suitable for direct unit testing without side effects
  # ---------------------------------------------------------------------------

  @doc """
  Returns the map payload that describes a state change event.
  """
  @spec state_change_payload(map(), atom()) :: map()
  def state_change_payload(data, state) do
    %{
      project_id: data.project_id,
      agent_id: data.id,
      agent_type: data.agent_type,
      state: state
    }
  end

  @doc """
  Returns the map payload for an activity log entry.

  The message is truncated to #{@max_message_length} characters if it exceeds
  that length.
  """
  @spec activity_payload(map(), atom(), String.t()) :: map()
  def activity_payload(data, state, message) do
    %{
      project_id: data.project_id,
      agent_id: data.id,
      agent_type: data.agent_type,
      state: state,
      message: truncate_message(message)
    }
  end

  @doc """
  Returns the telemetry metadata map for an agent / state pair.

  Includes a `:system_time` field (from `System.system_time/0`) so callers
  can verify the expected keys without asserting on the exact timestamp value.
  """
  @spec telemetry_metadata(map(), atom()) :: map()
  def telemetry_metadata(data, state) do
    %{
      system_time: System.system_time(),
      agent_id: data.id,
      agent_type: data.agent_type,
      project_id: data.project_id,
      state: state
    }
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp truncate_message(message) when byte_size(message) > @max_message_length do
    String.slice(message, 0, @max_message_length) <> "..."
  end

  defp truncate_message(message), do: message

  defp update_agent_run_status(data, state) do
    case find_active_agent_run(data.project_id, data.agent_type) do
      nil -> :ok
      run -> Samgita.Projects.update_agent_run(run, %{status: state})
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp find_active_agent_run(project_id, agent_type) do
    import Ecto.Query

    Samgita.Domain.AgentRun
    |> where([a], a.project_id == ^project_id and a.agent_type == ^agent_type)
    |> where([a], is_nil(a.ended_at))
    |> Samgita.Repo.one()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
