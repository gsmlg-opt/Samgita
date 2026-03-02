defmodule SamgitaProviderTest do
  use ExUnit.Case, async: true

  describe "query/2 with :mock provider" do
    setup do
      Application.put_env(:samgita_provider, :provider, :mock)
      on_exit(fn -> Application.delete_env(:samgita_provider, :provider) end)
    end

    test "returns mock response" do
      assert {:ok, "mock response"} = SamgitaProvider.query("hello")
    end

    test "ignores opts for mock" do
      assert {:ok, "mock response"} =
               SamgitaProvider.query("hello", system_prompt: "test", max_turns: 1)
    end
  end

  describe "provider/0" do
    test "defaults to ClaudeCode" do
      Application.delete_env(:samgita_provider, :provider)
      assert SamgitaProvider.provider() == SamgitaProvider.ClaudeCode
    end

    test "returns configured provider" do
      Application.put_env(:samgita_provider, :provider, :mock)
      assert SamgitaProvider.provider() == :mock
      Application.delete_env(:samgita_provider, :provider)
    end

    test "can be configured with Codex provider" do
      Application.put_env(:samgita_provider, :provider, SamgitaProvider.Codex)
      assert SamgitaProvider.provider() == SamgitaProvider.Codex
      Application.delete_env(:samgita_provider, :provider)
    end
  end

  describe "Codex.build_args/2" do
    test "builds exec --full-auto args with prompt" do
      assert SamgitaProvider.Codex.build_args("hello world", []) ==
               ["exec", "--full-auto", "hello world"]
    end

    test "prepends system prompt to prompt text" do
      args = SamgitaProvider.Codex.build_args("test", system_prompt: "You are helpful")
      assert List.last(args) == "You are helpful\n\ntest"
    end

    test "adds writable-root when working_directory is set" do
      args = SamgitaProvider.Codex.build_args("test", working_directory: "/tmp/project")
      assert args == ["exec", "--full-auto", "--writable-root", "/tmp/project", "test"]
    end

    test "combines system prompt and working directory" do
      args =
        SamgitaProvider.Codex.build_args("test",
          system_prompt: "Be concise",
          working_directory: "/tmp/project"
        )

      assert args == [
               "exec",
               "--full-auto",
               "--writable-root",
               "/tmp/project",
               "Be concise\n\ntest"
             ]
    end
  end

  describe "Codex.effort_for_model/1" do
    test "maps opus to xhigh" do
      assert SamgitaProvider.Codex.effort_for_model("opus") == "xhigh"
    end

    test "maps sonnet to high" do
      assert SamgitaProvider.Codex.effort_for_model("sonnet") == "high"
    end

    test "maps haiku to low" do
      assert SamgitaProvider.Codex.effort_for_model("haiku") == "low"
    end

    test "defaults to high for unknown models" do
      assert SamgitaProvider.Codex.effort_for_model("gpt-4") == "high"
    end

    test "handles atom input" do
      assert SamgitaProvider.Codex.effort_for_model(:opus) == "xhigh"
    end
  end
end
