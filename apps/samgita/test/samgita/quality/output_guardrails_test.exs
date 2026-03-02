defmodule Samgita.Quality.OutputGuardrailsTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.OutputGuardrails

  describe "validate/2" do
    test "passes valid output" do
      result = OutputGuardrails.validate("This is a perfectly normal task output.")
      assert result.gate == 5
      assert result.name == "Output Guardrails"
      assert result.verdict == :pass
      assert result.findings == []
    end

    test "flags empty output" do
      result = OutputGuardrails.validate("")
      assert result.verdict == :fail
      assert Enum.any?(result.findings, &String.contains?(&1.message, "empty or too short"))
    end

    test "flags overly long output" do
      long = String.duplicate("x", 500_001)
      result = OutputGuardrails.validate(long)
      assert result.verdict == :fail
      assert Enum.any?(result.findings, &String.contains?(&1.message, "exceeds max length"))
    end

    test "detects AWS access key" do
      output = "config = %{access_key: \"AKIAIOSFODNN7EXAMPLE\"}"
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :critical and String.contains?(f.message, "AWS access key")
             end)
    end

    test "detects GitHub token" do
      output = "token = \"ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij\""
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :critical and String.contains?(f.message, "GitHub token")
             end)
    end

    test "detects private key" do
      output = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQ..."
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :critical and String.contains?(f.message, "Private key")
             end)
    end

    test "detects hardcoded password" do
      output = ~s(password = "super_secret_p4ss!")
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :critical and String.contains?(f.message, "Hardcoded password")
             end)
    end

    test "detects dangerous rm -rf operation" do
      output = ~s|System.cmd("rm", ["-rf", "/"])|
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :high and String.contains?(f.message, "rm -rf")
             end)
    end

    test "detects DROP DATABASE" do
      output = "Repo.query!(\"DROP DATABASE production\")"
      result = OutputGuardrails.validate(output)
      assert result.verdict == :fail

      assert Enum.any?(result.findings, fn f ->
               f.severity == :high and String.contains?(f.message, "DROP DATABASE")
             end)
    end

    test "checks markdown spec compliance" do
      long_text = String.duplicate("No headings here. ", 10)
      result = OutputGuardrails.validate(long_text, context: %{expected_format: :markdown})
      assert Enum.any?(result.findings, &String.contains?(&1.message, "no headings"))
    end

    test "passes markdown with headings" do
      output = "# Title\n\nSome content here with details."
      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})
      assert result.verdict == :pass
    end

    test "checks JSON spec compliance" do
      result = OutputGuardrails.validate("not json", context: %{expected_format: :json})
      assert result.verdict == :fail
      assert Enum.any?(result.findings, &String.contains?(&1.message, "JSON"))
    end

    test "passes valid JSON" do
      result = OutputGuardrails.validate(~s({"key": "value"}), context: %{expected_format: :json})
      assert result.verdict == :pass
    end

    test "includes duration_ms" do
      result = OutputGuardrails.validate("normal output")
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end
  end
end
