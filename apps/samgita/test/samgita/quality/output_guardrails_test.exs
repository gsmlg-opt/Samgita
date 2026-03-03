defmodule Samgita.Quality.OutputGuardrailsTest do
  use ExUnit.Case, async: true

  alias Samgita.Quality.OutputGuardrails

  describe "validate/2 - valid output" do
    test "passes with normal text output" do
      output = "This is a normal agent response with sufficient length."
      result = OutputGuardrails.validate(output)

      assert result.gate == 5
      assert result.name == "Output Guardrails"
      assert result.verdict == :pass
      assert result.findings == []
      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "passes with long output under max length" do
      output = String.duplicate("a", 100_000)
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes with markdown content" do
      output = """
      # Heading
      This is markdown content with proper structure.
      ## Subheading
      Content here.
      """

      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes with valid JSON" do
      output = ~s({"key": "value", "number": 42})
      result = OutputGuardrails.validate(output, context: %{expected_format: :json})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes with DROP TABLE IF EXISTS (safe pattern)" do
      output = "DROP TABLE IF EXISTS users;"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - empty/too-short output" do
    test "detects empty string" do
      result = OutputGuardrails.validate("")

      assert result.verdict == :fail
      assert length(result.findings) == 1

      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :medium
      assert finding.message == "Output is empty or too short (0 chars)"
      assert finding.file == nil
      assert finding.line == nil
    end
  end

  describe "validate/2 - overly large output" do
    test "detects output exceeding max length" do
      output = String.duplicate("x", 500_001)
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      assert length(result.findings) == 1

      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :medium
      assert finding.message =~ "Output exceeds max length"
      assert finding.message =~ "500001 chars"
      assert finding.message =~ "max 500000"
    end

    test "passes at exactly max length" do
      output = String.duplicate("x", 500_000)
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - secret detection: AWS keys" do
    test "detects AKIA AWS access key" do
      output = "AWS key: AKIAIOSFODNN7EXAMPLE"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      assert length(result.findings) == 1

      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: AWS access key"
    end

    test "detects ASIA AWS session key" do
      output = "Session: ASIAJEXAMPLEXEG2JICEA"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: AWS access key"
    end
  end

  describe "validate/2 - secret detection: GitHub tokens" do
    test "detects ghp_ GitHub personal access token" do
      output = "Token: ghp_1234567890abcdefghijklmnopqrstuvwxyz"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: GitHub token"
    end

    test "detects gho_ GitHub OAuth token" do
      output = "OAuth: gho_abcdefghijklmnopqrstuvwxyz1234567890"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: GitHub token"
    end

    test "detects ghu_ GitHub user token" do
      output = "User token: ghu_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: GitHub token"
    end

    test "detects ghs_ GitHub server token" do
      output = "Server: ghs_abcdefghijklmnopqrstuvwxyz1234567890"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: GitHub token"
    end

    test "detects ghr_ GitHub refresh token" do
      output = "Refresh: ghr_1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: GitHub token"
    end
  end

  describe "validate/2 - secret detection: API keys" do
    test "detects sk- OpenAI/Anthropic API key" do
      output = "API_KEY=sk-#{String.duplicate("x", 32)}"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: OpenAI/Anthropic API key"
    end

    test "detects longer sk- key" do
      output = "export ANTHROPIC_API_KEY=sk-#{String.duplicate("abcdef123456", 10)}"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: OpenAI/Anthropic API key"
    end
  end

  describe "validate/2 - secret detection: private keys" do
    test "detects RSA private key" do
      output = """
      -----BEGIN RSA PRIVATE KEY-----
      MIIEpAIBAAKCAQEA...
      -----END RSA PRIVATE KEY-----
      """

      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: Private key"
    end

    test "detects EC private key" do
      output = "-----BEGIN EC PRIVATE KEY-----\nMHc..."
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Private key"
    end

    test "detects DSA private key" do
      output = "-----BEGIN DSA PRIVATE KEY-----"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Private key"
    end

    test "detects generic private key" do
      output = "-----BEGIN PRIVATE KEY-----"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Private key"
    end
  end

  describe "validate/2 - secret detection: hardcoded passwords" do
    test "detects password with colon" do
      output = ~s(password: "SuperSecret123")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: Hardcoded password"
    end

    test "detects passwd with equals" do
      output = ~s(passwd = 'MyP@ssw0rd')
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Hardcoded password"
    end

    test "detects pwd (case insensitive)" do
      output = ~s(PWD="test1234")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Hardcoded password"
    end

    test "does not flag short passwords (< 4 chars)" do
      output = ~s(password: "abc")
      result = OutputGuardrails.validate(output)

      # Should pass because password is too short to be flagged
      assert result.verdict == :pass
    end
  end

  describe "validate/2 - secret detection: hardcoded secrets" do
    test "detects secret with base64-like value" do
      output = ~s(secret: "dGVzdHNlY3JldDEyMzQ1Ng==")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: Hardcoded secret"
    end

    test "detects token field" do
      output = ~s(token = "AbCdEfGhIjKlMnOpQrSt")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Hardcoded secret"
    end

    test "detects api_key field" do
      output = ~s(api_key: "1234567890abcdef1234567890abcdef")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Hardcoded secret"
    end

    test "detects apikey field (case insensitive)" do
      output = ~s(APIKEY = "ABCDEFGH12345678IJKLMNOP")
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Hardcoded secret"
    end
  end

  describe "validate/2 - secret detection: Bearer tokens" do
    test "detects Bearer token" do
      output = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :critical
      assert finding.message == "Potential secret detected in output: Bearer token"
    end

    test "detects bearer token (case insensitive)" do
      output = "bearer AbCdEfGh123456"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Potential secret detected in output: Bearer token"
    end
  end

  describe "validate/2 - dangerous code patterns: System.cmd rm -rf" do
    test "detects System.cmd with rm -rf" do
      output = ~s|System.cmd("rm", ["-rf", "/tmp/data"])|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: rm -rf in System.cmd"
    end

    test "detects System.cmd with whitespace after paren" do
      output = ~s|System.cmd( "rm", ["-rf"|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Dangerous operation in output: rm -rf in System.cmd"
    end
  end

  describe "validate/2 - dangerous code patterns: File.rm_rf!" do
    test "detects File.rm_rf! on root path" do
      output = ~s|File.rm_rf!("/")|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: File.rm_rf! on root path"
    end

    test "detects File.rm_rf! with whitespace" do
      output = ~s|File.rm_rf!(  "/"  )|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Dangerous operation in output: File.rm_rf! on root path"
    end

    test "allows File.rm_rf! on non-root path" do
      output = ~s|File.rm_rf!("/tmp/safe_dir")|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - dangerous code patterns: Erlang os:cmd" do
    test "detects :os.cmd with rm -rf" do
      output = ~s|:os.cmd('rm -rf /data')|
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: Erlang os:cmd rm -rf"
    end
  end

  describe "validate/2 - dangerous code patterns: DROP DATABASE" do
    test "detects DROP DATABASE statement" do
      output = "DROP DATABASE production;"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: DROP DATABASE statement"
    end

    test "detects drop database (case insensitive)" do
      output = "drop database staging"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Dangerous operation in output: DROP DATABASE statement"
    end
  end

  describe "validate/2 - dangerous code patterns: DROP TABLE" do
    test "detects DROP TABLE without IF EXISTS" do
      output = "DROP TABLE users;"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: DROP TABLE without IF EXISTS"
    end

    test "detects drop table (case insensitive)" do
      output = "drop table sessions"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Dangerous operation in output: DROP TABLE without IF EXISTS"
    end

    test "allows DROP TABLE IF EXISTS (safe pattern)" do
      output = "DROP TABLE IF EXISTS users;"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - dangerous code patterns: TRUNCATE TABLE" do
    test "detects TRUNCATE TABLE statement" do
      output = "TRUNCATE TABLE logs;"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.severity == :high
      assert finding.message == "Dangerous operation in output: TRUNCATE TABLE statement"
    end

    test "detects truncate table (case insensitive)" do
      output = "truncate table events"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Dangerous operation in output: TRUNCATE TABLE statement"
    end
  end

  describe "validate/2 - format validation: JSON" do
    test "fails on invalid JSON when expected" do
      output = ~s({invalid json})
      result = OutputGuardrails.validate(output, context: %{expected_format: :json})

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :medium
      assert finding.message == "Expected JSON output but parsing failed"
    end

    test "passes on valid JSON array" do
      output = ~s([1, 2, 3])
      result = OutputGuardrails.validate(output, context: %{expected_format: :json})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes on complex nested JSON" do
      output = ~s({"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]})
      result = OutputGuardrails.validate(output, context: %{expected_format: :json})

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - format validation: markdown" do
    test "warns on markdown without headings when output is long" do
      output = String.duplicate("This is plain text without any headings. ", 10)
      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})

      # :low severity is not blocking, so verdict should be :pass
      assert result.verdict == :pass
      assert length(result.findings) == 1
      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :low
      assert finding.message == "Expected markdown output but no headings found"
    end

    test "passes on short markdown without headings" do
      output = "Short text under 100 chars"
      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes on markdown with headings" do
      output = "# Title\n" <> String.duplicate("Content ", 20)
      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "passes with hash in middle of long text" do
      output = String.duplicate("text ", 15) <> " #hashtag " <> String.duplicate("more ", 10)
      result = OutputGuardrails.validate(output, context: %{expected_format: :markdown})

      assert result.verdict == :pass
      assert result.findings == []
    end
  end

  describe "validate/2 - non-string output" do
    test "fails on nil output" do
      result = OutputGuardrails.validate(nil)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.gate == 5
      assert finding.severity == :medium
      assert finding.message == "Output is not a string"
    end

    test "fails on integer output" do
      result = OutputGuardrails.validate(123)

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Output is not a string"
    end

    test "fails on map output" do
      result = OutputGuardrails.validate(%{key: "value"})

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Output is not a string"
    end

    test "fails on list output" do
      result = OutputGuardrails.validate(["a", "b", "c"])

      assert result.verdict == :fail
      finding = hd(result.findings)
      assert finding.message == "Output is not a string"
    end
  end

  describe "validate/2 - multiple findings" do
    test "accumulates multiple secret violations" do
      # Use proper format for sk- key (32+ consecutive alphanumeric chars)
      sk_key = "sk-" <> String.duplicate("x", 40)

      output = """
      AWS_KEY=AKIAIOSFODNN7EXAMPLE
      GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwxyz
      API_KEY=#{sk_key}
      """

      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      assert length(result.findings) == 3
      assert Enum.all?(result.findings, fn f -> f.severity == :critical end)

      messages = Enum.map(result.findings, & &1.message)
      assert "Potential secret detected in output: AWS access key" in messages
      assert "Potential secret detected in output: GitHub token" in messages
      assert "Potential secret detected in output: OpenAI/Anthropic API key" in messages
    end

    test "accumulates multiple dangerous patterns" do
      output = """
      System.cmd("rm", ["-rf", "/tmp"])
      DROP DATABASE test;
      TRUNCATE TABLE logs;
      """

      result = OutputGuardrails.validate(output)

      assert result.verdict == :fail
      assert length(result.findings) == 3
      assert Enum.all?(result.findings, fn f -> f.severity == :high end)

      messages = Enum.map(result.findings, & &1.message)
      assert "Dangerous operation in output: rm -rf in System.cmd" in messages
      assert "Dangerous operation in output: DROP DATABASE statement" in messages
      assert "Dangerous operation in output: TRUNCATE TABLE statement" in messages
    end

    test "combines secrets, dangerous patterns, and format issues" do
      output = """
      {invalid json
      password: "secret123"
      DROP TABLE users;
      """

      result = OutputGuardrails.validate(output, context: %{expected_format: :json})

      assert result.verdict == :fail
      assert length(result.findings) == 3

      severities = Enum.map(result.findings, & &1.severity)
      assert :critical in severities
      assert :high in severities
      assert :medium in severities
    end
  end

  describe "validate/2 - edge cases" do
    test "handles single character output" do
      result = OutputGuardrails.validate("x")

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles output with unicode characters" do
      output = "Hello 世界 🌍 café"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles output with newlines and special characters" do
      output = "Line 1\n\nLine 2\r\nLine 3\t\tTabbed"
      result = OutputGuardrails.validate(output)

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles empty context" do
      output = "Normal output"
      result = OutputGuardrails.validate(output, context: %{})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles unknown format in context" do
      output = "Normal output"
      result = OutputGuardrails.validate(output, context: %{expected_format: :unknown})

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "handles context with other keys" do
      output = "Normal output"

      result =
        OutputGuardrails.validate(output,
          context: %{task_id: 123, agent_type: :frontend}
        )

      assert result.verdict == :pass
      assert result.findings == []
    end

    test "does not flag safe code examples in comments" do
      output = """
      # This function is safe
      def cleanup(path) when path != "/" do
        File.rm_rf!(path)
      end
      """

      result = OutputGuardrails.validate(output)

      # Should pass - rm_rf! is not on root path
      assert result.verdict == :pass
    end

    test "measures duration accurately" do
      output = String.duplicate("test content ", 1000)
      result = OutputGuardrails.validate(output)

      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
      # Should complete quickly (less than 1 second)
      assert result.duration_ms < 1000
    end
  end

  describe "validate/2 - findings structure" do
    test "all findings have required fields" do
      output = """
      AKIAIOSFODNN7EXAMPLE
      DROP DATABASE test;
      """

      result = OutputGuardrails.validate(output)

      for finding <- result.findings do
        assert is_integer(finding.gate)
        assert finding.gate == 5
        assert finding.severity in [:critical, :high, :medium, :low, :cosmetic]
        assert is_binary(finding.message)
        assert finding.file == nil
        assert finding.line == nil
      end
    end

    test "result has required structure" do
      result = OutputGuardrails.validate("test")

      assert is_map(result)
      assert Map.has_key?(result, :gate)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :verdict)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :duration_ms)

      assert result.gate == 5
      assert result.name == "Output Guardrails"
      assert result.verdict in [:pass, :fail]
      assert is_list(result.findings)
      assert is_integer(result.duration_ms)
    end
  end
end
