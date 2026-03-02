defmodule Samgita.Quality.OutputGuardrails do
  @moduledoc """
  Quality Gate 5: Output Guardrails.

  Validates agent output before it is persisted or acted upon:
  - Secret detection (API keys, tokens, passwords in output)
  - Spec compliance (output meets expected format/structure)
  - Dangerous command detection (destructive operations in generated code)
  - Size bounds (output not empty, not excessively large)
  """

  alias Samgita.Quality.Gate

  @max_output_length 500_000
  @min_output_length 1

  # Patterns that indicate leaked secrets
  @secret_patterns [
    {~r/(?:AKIA|ASIA)[A-Z0-9]{16}/, "AWS access key"},
    {~r/(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{36,}/, "GitHub token"},
    {~r/sk-[A-Za-z0-9]{32,}/, "OpenAI/Anthropic API key"},
    {~r/-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----/, "Private key"},
    {~r/(?:password|passwd|pwd)\s*[:=]\s*["'][^"']{4,}["']/i, "Hardcoded password"},
    {~r/(?:secret|token|api_key|apikey)\s*[:=]\s*["'][A-Za-z0-9+\/=]{16,}["']/i,
     "Hardcoded secret"},
    {~r/Bearer\s+[A-Za-z0-9\-._~+\/]+=*/i, "Bearer token"}
  ]

  # Dangerous operations that should not appear in generated code
  @dangerous_patterns [
    {~r/System\.cmd\s*\(\s*"rm"\s*,\s*\["-rf"/, "rm -rf in System.cmd"},
    {~r/File\.rm_rf!\s*\(\s*"\/"/i, "File.rm_rf! on root path"},
    {~r/:os\.cmd\s*\(\s*'rm\s+-rf/, "Erlang os:cmd rm -rf"},
    {~r/DROP\s+DATABASE/i, "DROP DATABASE statement"},
    {~r/DROP\s+TABLE\s+(?!IF\s+EXISTS)/i, "DROP TABLE without IF EXISTS"},
    {~r/TRUNCATE\s+TABLE/i, "TRUNCATE TABLE statement"}
  ]

  @doc """
  Validate agent output before persistence.

  Returns a Gate.result() with findings for any issues detected.
  """
  @spec validate(String.t(), keyword()) :: Gate.result()
  def validate(output, opts \\ []) do
    start = System.monotonic_time(:millisecond)
    context = opts[:context] || %{}

    findings =
      []
      |> check_size(output)
      |> check_secrets(output)
      |> check_dangerous_operations(output)
      |> check_spec_compliance(output, context)

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

  defp check_size(findings, output) when is_binary(output) do
    len = String.length(output)

    cond do
      len < @min_output_length ->
        [
          %{
            gate: 5,
            severity: :medium,
            message: "Output is empty or too short (#{len} chars)",
            file: nil,
            line: nil
          }
          | findings
        ]

      len > @max_output_length ->
        [
          %{
            gate: 5,
            severity: :medium,
            message: "Output exceeds max length (#{len} chars, max #{@max_output_length})",
            file: nil,
            line: nil
          }
          | findings
        ]

      true ->
        findings
    end
  end

  defp check_size(findings, _output) do
    [
      %{
        gate: 5,
        severity: :medium,
        message: "Output is not a string",
        file: nil,
        line: nil
      }
      | findings
    ]
  end

  defp check_secrets(findings, output) when is_binary(output) do
    Enum.reduce(@secret_patterns, findings, fn {pattern, label}, acc ->
      if Regex.match?(pattern, output) do
        [
          %{
            gate: 5,
            severity: :critical,
            message: "Potential secret detected in output: #{label}",
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

  defp check_secrets(findings, _output), do: findings

  defp check_dangerous_operations(findings, output) when is_binary(output) do
    Enum.reduce(@dangerous_patterns, findings, fn {pattern, label}, acc ->
      if Regex.match?(pattern, output) do
        [
          %{
            gate: 5,
            severity: :high,
            message: "Dangerous operation in output: #{label}",
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

  defp check_dangerous_operations(findings, _output), do: findings

  defp check_spec_compliance(findings, output, context) when is_binary(output) do
    expected_format = context[:expected_format]

    case expected_format do
      :markdown ->
        if not String.contains?(output, "#") and String.length(output) > 100 do
          [
            %{
              gate: 5,
              severity: :low,
              message: "Expected markdown output but no headings found",
              file: nil,
              line: nil
            }
            | findings
          ]
        else
          findings
        end

      :json ->
        case Jason.decode(output) do
          {:ok, _} ->
            findings

          {:error, _} ->
            [
              %{
                gate: 5,
                severity: :medium,
                message: "Expected JSON output but parsing failed",
                file: nil,
                line: nil
              }
              | findings
            ]
        end

      _ ->
        findings
    end
  end

  defp check_spec_compliance(findings, _output, _context), do: findings
end
