defmodule Samgita.Workers.QualityGateWorker do
  @moduledoc """
  Oban worker that runs quality gate checks between phases.

  Triggered by the orchestrator before allowing phase transitions from:
  - development → qa (runs blind review + completion council)
  - qa → deployment (runs full gate suite)

  Results are broadcast via PubSub and stored as project artifacts.
  """

  use Oban.Worker,
    queue: :orchestration,
    max_attempts: 2

  require Logger

  alias Samgita.Domain.Artifact
  alias Samgita.Projects

  alias Samgita.Quality.{
    AntiSycophancy,
    BlindReview,
    CompletionCouncil,
    Gate,
    MockDetector,
    OutputGuardrails,
    SeverityBlocking,
    StaticAnalysis,
    TestCoverage,
    TestMutationDetector
  }

  @impl true
  def perform(%Oban.Job{args: args}) do
    project_id = args["project_id"]
    prd_id = args["prd_id"]
    gate_type = args["gate_type"] || "pre_qa"

    Logger.info("[QualityGateWorker] Starting #{gate_type} gates for project #{project_id}")

    broadcast_activity(project_id, :reason, "Starting quality gate evaluation: #{gate_type}")

    with {:ok, project} <- Projects.get_project(project_id),
         {:ok, prd} <- get_prd(prd_id) do
      results = run_gates(gate_type, project, prd)
      {verdict, gate_results} = Gate.aggregate(results)

      broadcast_activity(
        project_id,
        if(verdict == :pass, do: :completed, else: :failed),
        "Quality gates #{gate_type}: #{verdict} (#{length(results)} gates evaluated)"
      )

      broadcast_gate_results(project_id, verdict, gate_results)

      store_gate_results(project, gate_type, verdict, gate_results)

      if verdict == :pass do
        notify_orchestrator_gate_passed(project_id)
      else
        Logger.warning("[QualityGateWorker] Gates failed for #{project_id}, blocking advancement")
        broadcast_activity(project_id, :failed, "Quality gates blocking phase advancement")
      end

      :ok
    else
      {:error, reason} ->
        Logger.error("[QualityGateWorker] Failed: #{inspect(reason)}")
        broadcast_activity(project_id, :failed, "Quality gate check failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Build gate results summary for display."
  @spec summarize_results([Gate.result()]) :: String.t()
  def summarize_results(results) do
    Enum.map_join(results, "\n", fn r ->
      finding_count = length(r.findings)
      "Gate #{r.gate} (#{r.name}): #{r.verdict} — #{finding_count} findings"
    end)
  end

  ## Internal

  defp run_gates("pre_qa", project, prd) do
    tasks = Projects.list_tasks(project.id)
    project_status = build_project_status(project, tasks)

    blind_result = run_blind_review(project)
    anti_syc = maybe_run_anti_sycophancy(blind_result, project)

    gate_results =
      [
        run_static_analysis(project),
        blind_result,
        anti_syc,
        run_completion_council(prd, project_status)
      ]
      |> Enum.filter(&(&1 != nil))

    # Gate 6: Severity Blocking — final aggregation
    severity_result = SeverityBlocking.evaluate(gate_results)
    gate_results ++ [severity_result]
  end

  defp run_gates("pre_deploy", project, prd) do
    tasks = Projects.list_tasks(project.id)
    project_status = build_project_status(project, tasks)

    blind_result = run_blind_review(project)
    anti_syc = maybe_run_anti_sycophancy(blind_result, project)

    gate_results =
      [
        run_static_analysis(project),
        blind_result,
        anti_syc,
        run_output_guardrails(project),
        run_completion_council(prd, project_status),
        run_test_coverage_gate(project),
        run_mock_detector(project),
        run_test_mutation_detector(project)
      ]
      |> Enum.filter(&(&1 != nil))

    # Gate 6: Severity Blocking — final aggregation
    severity_result = SeverityBlocking.evaluate(gate_results)
    gate_results ++ [severity_result]
  end

  defp run_gates(_type, project, prd) do
    run_gates("pre_qa", project, prd)
  end

  defp maybe_run_anti_sycophancy(blind_result, project) do
    if blind_result.verdict == :pass and AntiSycophancy.should_challenge?(blind_result.findings) do
      Logger.info("[QualityGateWorker] Unanimous blind review — triggering anti-sycophancy check")

      broadcast_activity(
        project.id,
        :reason,
        "Unanimous approval detected — running Devil's Advocate review"
      )

      AntiSycophancy.challenge("", blind_result.findings,
        project_context: "Project: #{project.name}"
      )
    else
      nil
    end
  end

  defp run_static_analysis(project) do
    working_path = project.working_path

    if working_path && File.dir?(working_path) do
      StaticAnalysis.analyze(working_path)
    else
      %{
        gate: 2,
        name: "Static Analysis",
        verdict: :skip,
        findings: [],
        duration_ms: 0
      }
    end
  end

  defp run_blind_review(project) do
    start = System.monotonic_time(:millisecond)

    try do
      {:ok, result} = BlindReview.review("", project_context: "Project: #{project.name}")
      result
    rescue
      e ->
        Logger.warning("[QualityGateWorker] Blind review failed: #{inspect(e)}")

        %{
          gate: 3,
          name: "Blind Review",
          verdict: :skip,
          findings: [],
          duration_ms: System.monotonic_time(:millisecond) - start
        }
    end
  end

  defp run_completion_council(prd, project_status) do
    start = System.monotonic_time(:millisecond)
    prd_content = prd.content || ""

    result =
      try do
        {:ok, council_result} = CompletionCouncil.evaluate(prd_content, project_status)

        verdict = if council_result.verdict == :complete, do: :pass, else: :fail

        findings =
          council_result.votes
          |> Enum.flat_map(fn vote ->
            if vote.vote == :incomplete do
              vote.remaining_issues
              |> Enum.map(fn issue ->
                %{
                  gate: 10,
                  severity: :medium,
                  message: "[#{vote.role}] #{issue}",
                  file: nil,
                  line: nil
                }
              end)
            else
              []
            end
          end)

        %{verdict: verdict, findings: findings}
      rescue
        e ->
          Logger.warning("[QualityGateWorker] Completion council failed: #{inspect(e)}")
          %{verdict: :skip, findings: []}
      end

    %{
      gate: 10,
      name: "Completion Council",
      verdict: result.verdict,
      findings: result.findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  defp run_test_coverage_gate(project) do
    working_path = project.working_path

    if working_path && File.dir?(working_path) do
      TestCoverage.run(working_path)
    else
      # Fall back to task-based check when no working path
      start = System.monotonic_time(:millisecond)
      tasks = Projects.list_tasks(project.id)
      test_tasks = Enum.filter(tasks, &(&1.type == "test"))
      passed = Enum.count(test_tasks, &(&1.status == :completed))
      total = length(test_tasks)

      verdict = if total > 0 and passed == total, do: :pass, else: :warn

      findings =
        if verdict == :warn and total > 0 do
          [
            %{
              gate: 7,
              severity: :medium,
              message: "Test tasks: #{passed}/#{total} passed",
              file: nil,
              line: nil
            }
          ]
        else
          []
        end

      %{
        gate: 7,
        name: "Test Coverage",
        verdict: verdict,
        findings: findings,
        duration_ms: System.monotonic_time(:millisecond) - start
      }
    end
  end

  defp run_mock_detector(project) do
    working_path = project.working_path

    if working_path && File.dir?(working_path) do
      MockDetector.scan(working_path)
    else
      nil
    end
  end

  defp run_test_mutation_detector(project) do
    working_path = project.working_path

    if working_path && File.dir?(working_path) do
      TestMutationDetector.scan(working_path)
    else
      nil
    end
  end

  defp run_output_guardrails(project) do
    import Ecto.Query, only: [where: 2, order_by: 2, limit: 2]

    artifacts =
      Samgita.Domain.Artifact
      |> where(project_id: ^project.id)
      |> order_by(desc: :inserted_at)
      |> limit(50)
      |> Samgita.Repo.all()

    if artifacts == [] do
      nil
    else
      start = System.monotonic_time(:millisecond)

      findings =
        artifacts
        |> Enum.flat_map(fn artifact ->
          result = OutputGuardrails.validate(artifact.content || "")
          result.findings
        end)

      verdict =
        if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

      %{
        gate: 5,
        name: "Output Guardrails",
        verdict: verdict,
        findings: findings,
        duration_ms: System.monotonic_time(:millisecond) - start
      }
    end
  end

  defp get_prd(nil), do: {:error, :no_prd}

  defp get_prd(prd_id) do
    case Samgita.Prds.get_prd(prd_id) do
      {:ok, prd} -> {:ok, prd}
      {:error, :not_found} -> {:error, :prd_not_found}
    end
  end

  defp build_project_status(project, tasks) do
    completed = Enum.count(tasks, &(&1.status == :completed))
    failed = Enum.count(tasks, &(&1.status == :failed))
    pending = Enum.count(tasks, &(&1.status == :pending))
    running = Enum.count(tasks, &(&1.status == :running))

    """
    Project: #{project.name}
    Status: #{project.status}
    Phase: #{project.phase}
    Tasks: #{length(tasks)} total (#{completed} completed, #{running} running, #{pending} pending, #{failed} failed)
    """
  end

  defp broadcast_activity(project_id, stage, message) do
    entry =
      Samgita.Events.build_log_entry(:orchestrator, "quality-gates", stage, message)

    Samgita.Events.activity_log(project_id, entry)
  end

  defp broadcast_gate_results(project_id, verdict, gate_results) do
    Samgita.Events.quality_gate_completed(project_id, verdict, gate_results)
  end

  defp store_gate_results(project, gate_type, verdict, gate_results) do
    summary = summarize_results(gate_results)

    %Artifact{}
    |> Artifact.changeset(%{
      type: :doc,
      path: "quality_gates/#{gate_type}_#{DateTime.to_iso8601(DateTime.utc_now())}.md",
      content: summary,
      project_id: project.id,
      metadata: %{
        gate_type: gate_type,
        verdict: to_string(verdict),
        gate_count: length(gate_results),
        findings_count: gate_results |> Enum.flat_map(& &1.findings) |> length()
      }
    })
    |> Samgita.Repo.insert()
  end

  defp notify_orchestrator_gate_passed(project_id) do
    case Horde.Registry.lookup(Samgita.AgentRegistry, {:orchestrator, project_id}) do
      [{pid, _}] ->
        :gen_statem.cast(pid, :quality_gates_passed)

      [] ->
        Logger.warning("[QualityGateWorker] Orchestrator not found for #{project_id}")
    end
  end
end
