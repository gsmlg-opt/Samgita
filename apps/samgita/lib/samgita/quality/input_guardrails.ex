defmodule Samgita.Quality.InputGuardrails do
  @moduledoc """
  Quality Gate 1: Input Guardrails.

  Validates task scope and detects potential prompt injection before
  tasks are sent to agent workers.

  Checks:
  - Task description length bounds (not too short, not too long)
  - Prohibited patterns (shell injection, prompt override attempts)
  - Task type validity
  - Payload structure validation
  """

  alias Samgita.Quality.Gate

  @max_description_length 10_000
  @min_description_length 5

  # Patterns that indicate prompt injection attempts
  @injection_patterns [
    ~r/ignore\s+(all\s+)?previous\s+instructions/i,
    ~r/forget\s+(all\s+)?your\s+(previous\s+)?instructions/i,
    ~r/you\s+are\s+now\s+a/i,
    ~r/system\s*:\s*you\s+are/i,
    ~r/\bsudo\b.*\brm\b/i,
    ~r/\brm\s+-rf\s+\//,
    ~r/;\s*(curl|wget)\s+/i,
    ~r/\|\s*(bash|sh|zsh)\b/i,
    ~r/`[^`]*\b(rm|curl|wget|nc|ncat)\b/i,
    ~r/\$\([^)]*\b(rm|curl|wget)\b/i
  ]

  @valid_task_types [
    "bootstrap",
    "generate-prd",
    "analysis",
    "architecture",
    "implement",
    "test",
    "review",
    "deploy",
    "monitor"
  ]

  @doc """
  Validate a task before execution.

  Returns a Gate.result() with findings for any issues detected.
  """
  @spec validate(map()) :: Gate.result()
  def validate(task_args) do
    start = System.monotonic_time(:millisecond)

    findings =
      []
      |> check_description(task_args)
      |> check_injection(task_args)
      |> check_task_type(task_args)
      |> check_payload_structure(task_args)

    verdict =
      if Gate.has_blocking_findings?(findings), do: :fail, else: :pass

    %{
      gate: 1,
      name: "Input Guardrails",
      verdict: verdict,
      findings: findings,
      duration_ms: System.monotonic_time(:millisecond) - start
    }
  end

  defp check_description(findings, task_args) do
    description = get_description(task_args)

    cond do
      is_nil(description) ->
        findings

      String.length(description) < @min_description_length ->
        [
          %{
            gate: 1,
            severity: :medium,
            message:
              "Task description too short (#{String.length(description)} chars, min #{@min_description_length})",
            file: nil,
            line: nil
          }
          | findings
        ]

      String.length(description) > @max_description_length ->
        [
          %{
            gate: 1,
            severity: :high,
            message:
              "Task description exceeds max length (#{String.length(description)} chars, max #{@max_description_length})",
            file: nil,
            line: nil
          }
          | findings
        ]

      true ->
        findings
    end
  end

  defp check_injection(findings, task_args) do
    text = get_all_text(task_args)

    Enum.reduce(@injection_patterns, findings, fn pattern, acc ->
      if Regex.match?(pattern, text) do
        [
          %{
            gate: 1,
            severity: :critical,
            message: "Potential prompt injection detected: #{inspect(Regex.source(pattern))}",
            file: nil,
            line: nil
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  defp check_task_type(findings, task_args) do
    task_type = task_args["type"] || task_args[:type]

    if task_type && task_type not in @valid_task_types do
      [
        %{
          gate: 1,
          severity: :low,
          message: "Unknown task type: #{task_type}",
          file: nil,
          line: nil
        }
        | findings
      ]
    else
      findings
    end
  end

  defp check_payload_structure(findings, task_args) do
    payload = task_args["payload"] || task_args[:payload] || %{}

    cond do
      not is_map(payload) ->
        [
          %{
            gate: 1,
            severity: :medium,
            message:
              "Task payload must be a map, got: #{inspect(payload |> then(& &1.__struct__), label: "")}",
            file: nil,
            line: nil
          }
          | findings
        ]

      map_size(payload) > 50 ->
        [
          %{
            gate: 1,
            severity: :medium,
            message: "Task payload has too many keys (#{map_size(payload)}, max 50)",
            file: nil,
            line: nil
          }
          | findings
        ]

      true ->
        findings
    end
  end

  defp get_description(task_args) do
    payload = task_args["payload"] || task_args[:payload] || %{}
    payload["description"] || payload[:description] || task_args["description"]
  end

  defp get_all_text(task_args) do
    payload = task_args["payload"] || task_args[:payload] || %{}
    description = payload["description"] || payload[:description] || ""
    agent_type = task_args["agent_type"] || task_args[:agent_type] || ""
    task_type = task_args["type"] || task_args[:type] || ""
    "#{description} #{agent_type} #{task_type}"
  end
end
