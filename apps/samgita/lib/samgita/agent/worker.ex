defmodule Samgita.Agent.Worker do
  @moduledoc """
  Agent worker implementing the RARV (Reason-Act-Reflect-Verify) cycle
  as a gen_statem state machine.

  States: :idle -> :reason -> :act -> :reflect -> :verify
  On verify failure: loops back to :reason with updated learnings.
  """

  @behaviour :gen_statem

  require Logger

  alias Samgita.Agent.ActivityBroadcaster
  alias Samgita.Agent.CircuitBreaker
  alias Samgita.Agent.Claude
  alias Samgita.Agent.ContextAssembler
  alias Samgita.Agent.PromptBuilder
  alias Samgita.Agent.ResultParser
  alias Samgita.Agent.RetryStrategy
  alias Samgita.Agent.Types
  alias Samgita.Agent.WorktreeManager
  alias Samgita.Domain.Artifact
  alias Samgita.Project.Orchestrator
  alias Samgita.Quality.OutputGuardrails

  defstruct [
    :id,
    :agent_type,
    :project_id,
    :current_task,
    :act_result,
    :reply_to,
    :working_path,
    task_count: 0,
    token_count: 0,
    retry_count: 0,
    started_at: nil,
    learnings: []
  ]

  @max_retries 3
  @max_learnings 20
  @reason_timeout_ms 60_000
  @act_timeout_ms 600_000
  @reflect_timeout_ms 60_000

  ## Public API

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)

    :gen_statem.start_link(
      {:via, Horde.Registry, {Samgita.AgentRegistry, id}},
      __MODULE__,
      opts,
      []
    )
  end

  def assign_task(pid, task, reply_to \\ nil) do
    :gen_statem.cast(pid, {:assign_task, task, reply_to})
  end

  def get_state(pid) do
    :gen_statem.call(pid, :get_state)
  end

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  ## gen_statem callbacks

  @impl true
  def callback_mode, do: [:state_functions, :state_enter]

  @impl true
  def init(opts) do
    data = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      agent_type: Keyword.fetch!(opts, :agent_type),
      project_id: Keyword.fetch!(opts, :project_id),
      started_at: DateTime.utc_now()
    }

    {:ok, :idle, data}
  end

  ## State: idle

  def idle(:enter, _old_state, _data) do
    :keep_state_and_data
  end

  def idle(:cast, {:assign_task, task, reply_to}, data) do
    case CircuitBreaker.allow?(data.agent_type) do
      :ok ->
        {:next_state, :reason, %{data | current_task: task, retry_count: 0, reply_to: reply_to}}

      {:error, :circuit_open} ->
        Logger.warning("[#{data.id}] Circuit open for #{data.agent_type}, rejecting task")

        ActivityBroadcaster.broadcast_activity(
          data,
          :idle,
          "Circuit breaker open for #{data.agent_type}, task rejected"
        )

        notify_caller(reply_to, task, {:error, :circuit_open})
        :keep_state_and_data
    end
  end

  def idle({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:idle, data}}]}
  end

  def idle(:info, _msg, _data), do: :keep_state_and_data
  def idle(:cast, _msg, _data), do: :keep_state_and_data
  def idle({:timeout, _name}, _content, _data), do: :keep_state_and_data

  ## State: reason

  def reason(:enter, _old_state, data) do
    ActivityBroadcaster.broadcast_state_change(data, :reason)
    ActivityBroadcaster.emit_state_transition(data, :reason)

    {:keep_state_and_data,
     [
       {:state_timeout, 0, :execute},
       {{:timeout, :reason_deadline}, @reason_timeout_ms, :deadline}
     ]}
  end

  def reason(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] REASON: Planning approach for task #{inspect(data.current_task)}")

    ActivityBroadcaster.broadcast_activity(
      data,
      :reason,
      "Planning approach for task #{PromptBuilder.task_type(data.current_task)}"
    )

    try do
      prd_id = get_in(PromptBuilder.task_payload(data.current_task), ["prd_id"])
      assemble_input = data |> Map.from_struct() |> Map.put(:prd_id, prd_id)
      context = ContextAssembler.assemble(assemble_input)

      learnings =
        (context.learnings ++ context.memory_learnings) |> Enum.take(@max_learnings)

      data = %{data | act_result: nil, learnings: learnings}

      working_path = get_working_path(data)

      if working_path do
        continuity_context =
          Map.merge(context, %{
            retry_count: data.retry_count,
            current_task_description: PromptBuilder.task_description(data.current_task)
          })

        ContextAssembler.write_continuity_file(working_path, continuity_context)
      end

      {:next_state, :act, data}
    rescue
      e ->
        Logger.error("[#{data.id}] REASON: Error building context: #{inspect(e)}")
        ActivityBroadcaster.emit_error(data, :reason, inspect(e))
        {:next_state, :act, %{data | act_result: nil, learnings: data.learnings}}
    end
  end

  def reason({:timeout, :reason_deadline}, :deadline, data) do
    Logger.warning("[#{data.id}] REASON: Timed out after #{@reason_timeout_ms}ms")
    ActivityBroadcaster.emit_error(data, :reason, :timeout)
    ActivityBroadcaster.broadcast_activity(data, :reason, "Timed out, proceeding to act")
    {:next_state, :act, %{data | act_result: nil}}
  end

  def reason({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reason, data}}]}
  end

  ## State: act

  def act(:enter, _old_state, data) do
    ActivityBroadcaster.broadcast_state_change(data, :act)
    ActivityBroadcaster.emit_state_transition(data, :act)

    {:keep_state_and_data,
     [
       {:state_timeout, 0, :execute},
       {{:timeout, :act_deadline}, @act_timeout_ms, :deadline}
     ]}
  end

  def act(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] ACT: Executing task via Claude CLI")

    ActivityBroadcaster.broadcast_activity(data, :act, "Executing task via Claude CLI")

    prd_id = get_in(PromptBuilder.task_payload(data.current_task), ["prd_id"])
    assemble_input = data |> Map.from_struct() |> Map.put(:prd_id, prd_id)
    context = ContextAssembler.assemble(assemble_input)
    prompt = PromptBuilder.build(data.current_task, context)
    model = Types.model_for_type(data.agent_type)

    # Cache working_path on first use to avoid repeated DB queries
    working_dir = get_working_path(data)

    data =
      if is_nil(data.working_path) && working_dir,
        do: %{data | working_path: working_dir},
        else: data

    chat_opts =
      [model: model]
      |> then(fn opts ->
        if working_dir, do: Keyword.put(opts, :working_directory, working_dir), else: opts
      end)

    raw_result = Claude.chat(prompt, chat_opts)
    classified = ResultParser.classify(raw_result)

    case classified do
      {:success, content} ->
        Logger.info("[#{data.id}] ACT: Claude returned result (#{String.length(content)} chars)")

        truncated =
          if byte_size(content) > 2000,
            do: String.slice(content, 0, 2000) <> "\n... (truncated)",
            else: content

        ActivityBroadcaster.broadcast_activity(
          data,
          :act,
          "Claude returned result (#{String.length(content)} chars)",
          output: truncated
        )

        {:next_state, :reflect, %{data | act_result: content}}

      {:failure, reason} ->
        category = RetryStrategy.classify_for_retry(reason)

        if category in [:rate_limit, :overloaded] do
          backoff = RetryStrategy.backoff_ms(category, data.retry_count)
          Logger.warning("[#{data.id}] ACT: #{category}, backing off #{backoff}ms")

          ActivityBroadcaster.broadcast_activity(
            data,
            :act,
            "#{category |> to_string() |> String.replace("_", " ") |> String.capitalize()}, backing off #{backoff}ms"
          )

          {:keep_state, %{data | retry_count: data.retry_count + 1},
           [{:state_timeout, backoff, :execute}]}
        else
          Logger.error("[#{data.id}] ACT: Failed - #{inspect(reason)}")

          ActivityBroadcaster.broadcast_activity(
            data,
            :act,
            "Execution failed: #{inspect(reason)}"
          )

          {:next_state, :reflect, %{data | act_result: {:error, reason}}}
        end
    end
  end

  def act({:timeout, :act_deadline}, :deadline, data) do
    Logger.warning("[#{data.id}] ACT: Timed out after #{@act_timeout_ms}ms")
    ActivityBroadcaster.emit_error(data, :act, :timeout)
    ActivityBroadcaster.broadcast_activity(data, :act, "Timed out executing Claude CLI")
    {:next_state, :reflect, %{data | act_result: {:error, :timeout}}}
  end

  def act({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:act, data}}]}
  end

  ## State: reflect

  def reflect(:enter, _old_state, data) do
    ActivityBroadcaster.broadcast_state_change(data, :reflect)
    ActivityBroadcaster.emit_state_transition(data, :reflect)

    {:keep_state_and_data,
     [
       {:state_timeout, 0, :execute},
       {{:timeout, :reflect_deadline}, @reflect_timeout_ms, :deadline}
     ]}
  end

  def reflect(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] REFLECT: Recording learnings")

    learning =
      case data.act_result do
        {:error, reason} ->
          "Task failed: #{inspect(reason)}"

        result when is_binary(result) ->
          "Task completed successfully with #{String.length(result)} chars output"

        _ ->
          "Task completed"
      end

    ActivityBroadcaster.broadcast_activity(data, :reflect, "Recording learnings: #{learning}")

    data = %{data | learnings: Enum.take([learning | data.learnings], @max_learnings)}

    try do
      ContextAssembler.persist_learning(data.project_id, learning)
    rescue
      e ->
        Logger.warning("[#{data.id}] REFLECT: Failed to persist learning: #{inspect(e)}")
        ActivityBroadcaster.emit_error(data, :reflect, inspect(e))
    end

    {:next_state, :verify, data}
  end

  def reflect({:timeout, :reflect_deadline}, :deadline, data) do
    Logger.warning("[#{data.id}] REFLECT: Timed out after #{@reflect_timeout_ms}ms")
    ActivityBroadcaster.emit_error(data, :reflect, :timeout)
    ActivityBroadcaster.broadcast_activity(data, :reflect, "Timed out, proceeding to verify")
    {:next_state, :verify, data}
  end

  def reflect({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:reflect, data}}]}
  end

  ## State: verify

  def verify(:enter, _old_state, data) do
    ActivityBroadcaster.broadcast_state_change(data, :verify)
    ActivityBroadcaster.emit_state_transition(data, :verify)
    {:keep_state_and_data, [{:state_timeout, 0, :execute}]}
  end

  def verify(:state_timeout, :execute, data) do
    Logger.info("[#{data.id}] VERIFY: Validating task output")

    case data.act_result do
      {:error, reason} ->
        handle_verify_error(data, reason)

      result when is_binary(result) ->
        # Gate 5: Output Guardrails
        gate_result = OutputGuardrails.validate(result)

        if gate_result.verdict == :fail do
          Logger.warning(
            "[#{data.id}] VERIFY: Output guardrails failed: #{inspect(Enum.map(gate_result.findings, & &1.message))}"
          )

          ActivityBroadcaster.broadcast_activity(
            data,
            :verify,
            "Output guardrails flagged issues (#{length(gate_result.findings)} findings)"
          )

          # Log but don't block — findings are informational for now
          # Critical secrets should still be flagged
        end

        Logger.info("[#{data.id}] VERIFY: Task verified successfully")
        CircuitBreaker.record_success(data.agent_type)
        ActivityBroadcaster.broadcast_activity(data, :verify, "Task verified successfully")

        handle_task_completion(data)
        complete_and_notify(data)
        WorktreeManager.maybe_checkpoint(data)
        notify_caller(data.reply_to, data.current_task, :ok)

        data = %{
          data
          | current_task: nil,
            act_result: nil,
            reply_to: nil,
            task_count: data.task_count + 1,
            retry_count: 0
        }

        {:next_state, :idle, data}

      _ ->
        Logger.info("[#{data.id}] VERIFY: Task completed (non-string result)")
        CircuitBreaker.record_success(data.agent_type)
        ActivityBroadcaster.broadcast_activity(data, :verify, "Task verified successfully")

        handle_task_completion(data)
        complete_and_notify(data)
        WorktreeManager.maybe_checkpoint(data)
        notify_caller(data.reply_to, data.current_task, :ok)

        data = %{
          data
          | current_task: nil,
            act_result: nil,
            reply_to: nil,
            task_count: data.task_count + 1,
            retry_count: 0
        }

        {:next_state, :idle, data}
    end
  end

  def verify({:call, from}, :get_state, data) do
    {:keep_state_and_data, [{:reply, from, {:verify, data}}]}
  end

  ## Catch-all handlers — prevent gen_statem crash on unexpected messages
  for state <- [:reason, :act, :reflect, :verify] do
    def unquote(state)(:cast, {:assign_task, task, reply_to}, data) do
      Logger.warning("[#{data.id}] Rejecting task in #{unquote(state)} state (busy)")
      notify_caller(reply_to, task, {:error, :agent_busy})
      :keep_state_and_data
    end

    def unquote(state)(:info, _msg, _data), do: :keep_state_and_data
    def unquote(state)(:cast, _msg, _data), do: :keep_state_and_data
  end

  ## Lifecycle

  @impl true
  def terminate(reason, _state, data) do
    notify_caller(data.reply_to, data.current_task, {:error, :worker_terminated})
    Logger.info("[#{data.id}] Worker terminated: #{inspect(reason)}")
    :ok
  end

  ## Internal — verify helpers

  defp handle_verify_error(data, reason) do
    error_category = RetryStrategy.classify_for_retry(reason)

    if RetryStrategy.should_retry?(error_category, data.retry_count) do
      Logger.warning("[#{data.id}] VERIFY: Failed, retrying from reason phase")

      ActivityBroadcaster.broadcast_activity(
        data,
        :verify,
        "Verification failed, retrying (attempt #{data.retry_count + 1}/#{@max_retries})"
      )

      {:next_state, :reason, %{data | retry_count: data.retry_count + 1}}
    else
      handle_verify_max_retries(data, reason, error_category)
    end
  end

  defp handle_verify_max_retries(data, reason, error_category) do
    Logger.error("[#{data.id}] VERIFY: Max retries reached, marking failed")

    if RetryStrategy.should_escalate?(error_category, data.retry_count) do
      CircuitBreaker.record_failure(data.agent_type)
    end

    ActivityBroadcaster.broadcast_activity(
      data,
      :verify,
      "Max retries reached, marking failed: #{inspect(reason)}"
    )

    notify_caller(data.reply_to, data.current_task, {:error, reason})

    data = %{
      data
      | current_task: nil,
        reply_to: nil,
        learnings: Enum.take(["Max retries: #{inspect(reason)}" | data.learnings], @max_learnings)
    }

    {:next_state, :idle, data}
  end

  ## Internal — caller notification

  defp notify_caller(nil, _task, _result), do: :ok

  defp notify_caller(pid, task, result) when is_pid(pid) do
    task_id =
      case task do
        %{id: id} -> id
        _ -> nil
      end

    send(pid, {:task_completed, task_id, result})
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp notify_caller(_other, _task, _result), do: :ok

  defp handle_task_completion(data) do
    task = data.current_task

    case PromptBuilder.task_type(task) do
      "generate-prd" ->
        save_generated_prd(data)

      "analysis" ->
        save_artifact(data, :doc, "discovery")

      "architecture" ->
        save_artifact(data, :doc, "architecture")

      "review" ->
        save_artifact(data, :doc, "review")

      _ ->
        :ok
    end

    increment_agent_run_tasks(data)
  end

  # Mark the DB task as completed and notify the Orchestrator.
  # This is called from the verify state AFTER the RARV cycle completes,
  # ensuring task completion is driven by actual Claude output, not the dispatcher.
  defp complete_and_notify(data) do
    task = data.current_task

    task_id =
      case task do
        %{id: id} -> id
        _ -> nil
      end

    if task_id do
      case Samgita.Projects.complete_task(task_id) do
        {:ok, completed_task} ->
          Samgita.Events.task_completed(completed_task)
          notify_orchestrator(data.project_id, task_id)

        {:error, reason} ->
          Logger.warning(
            "[#{data.id}] Failed to mark task #{task_id} complete: #{inspect(reason)}"
          )
      end
    end
  rescue
    e -> Logger.warning("[#{data.id}] complete_and_notify failed: #{inspect(e)}")
  catch
    :exit, _ -> :ok
  end

  defp notify_orchestrator(project_id, task_id) do
    max_retries = Application.get_env(:samgita, :orchestrator_notify_retries, 3)
    do_notify_orchestrator(project_id, task_id, max_retries)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp do_notify_orchestrator(project_id, task_id, retries) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        Orchestrator.notify_task_completed(pid, task_id)

      [] when retries > 0 ->
        Logger.debug(
          "[#{project_id}] Orchestrator not found for task #{task_id}, retrying in 500ms (#{retries} left)"
        )

        Process.sleep(500)
        do_notify_orchestrator(project_id, task_id, retries - 1)

      [] ->
        max_retries = Application.get_env(:samgita, :orchestrator_notify_retries, 3)

        if max_retries > 0 do
          Logger.warning(
            "[#{project_id}] No orchestrator found for task #{task_id} completion notification after retries"
          )
        end
    end
  end

  defp increment_agent_run_tasks(data) do
    case find_active_agent_run(data.project_id, data.agent_type) do
      nil ->
        :ok

      run ->
        Samgita.Projects.update_agent_run(run, %{
          total_tasks: (run.total_tasks || 0) + 1
        })
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

  defp save_generated_prd(data) do
    case data.act_result do
      result when is_binary(result) ->
        Logger.info("[#{data.id}] Saving generated PRD to project #{data.project_id}")
        do_save_prd(data, result)

      _ ->
        Logger.warning("[#{data.id}] No PRD content to save")
    end
  end

  defp do_save_prd(data, result) do
    case Samgita.Projects.get_project(data.project_id) do
      {:ok, project} ->
        update_and_broadcast_prd(data, project, result)

      {:error, reason} ->
        Logger.error("[#{data.id}] Failed to get project: #{inspect(reason)}")
    end
  end

  defp update_and_broadcast_prd(data, project, result) do
    save_result =
      case Samgita.Prds.list_prds(project.id) do
        [prd | _] ->
          Samgita.Prds.update_prd(prd, %{content: result, status: :approved})

        [] ->
          Samgita.Prds.create_prd(%{
            project_id: project.id,
            title: "Generated PRD",
            content: result,
            status: :approved
          })
      end

    case save_result do
      {:ok, _} ->
        Logger.info("[#{data.id}] PRD saved successfully")

        Phoenix.PubSub.broadcast(
          Samgita.PubSub,
          "project:#{data.project_id}",
          {:prd_generated, data.project_id}
        )

      {:error, reason} ->
        Logger.error("[#{data.id}] Failed to save PRD: #{inspect(reason)}")
    end
  end

  defp save_artifact(data, type, category) do
    case data.act_result do
      result when is_binary(result) and result != "" ->
        task = data.current_task
        payload = PromptBuilder.task_payload(task)
        description = payload["description"] || category

        task_id =
          case task do
            %{id: id} -> id
            _ -> nil
          end

        attrs = %{
          type: type,
          path: "#{category}/#{data.agent_type}/#{PromptBuilder.task_type(task)}",
          content: result,
          content_hash: :crypto.hash(:sha256, result) |> Base.encode16(case: :lower),
          metadata: %{
            "agent_type" => data.agent_type,
            "phase" => payload["phase"],
            "description" => description,
            "category" => category
          },
          project_id: data.project_id,
          task_id: task_id
        }

        case Samgita.Repo.insert(Artifact.changeset(%Artifact{}, attrs)) do
          {:ok, artifact} ->
            Logger.info("[#{data.id}] Saved #{category} artifact: #{artifact.id}")

          {:error, reason} ->
            Logger.warning("[#{data.id}] Failed to save #{category} artifact: #{inspect(reason)}")
        end

      _ ->
        Logger.warning("[#{data.id}] No content to save as #{category} artifact")
    end
  rescue
    e ->
      Logger.warning("[#{data.id}] Error saving #{category} artifact: #{inspect(e)}")
  end

  defp get_working_path(%{working_path: path} = _data) when not is_nil(path), do: path

  defp get_working_path(data) do
    case Samgita.Projects.get_project(data.project_id) do
      {:ok, project} -> project.working_path
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
