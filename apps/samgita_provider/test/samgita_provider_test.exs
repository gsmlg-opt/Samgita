defmodule SamgitaProviderTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  describe "query/2" do
    test "delegates to the configured provider" do
      expect(SamgitaProvider.MockProvider, :query, fn "hello", [] -> {:ok, "delegated"} end)
      assert {:ok, "delegated"} = SamgitaProvider.query("hello")
    end

    test "passes opts through to the provider" do
      expect(SamgitaProvider.MockProvider, :query, fn "test", [model: "opus"] ->
        {:ok, "opus response"}
      end)

      assert {:ok, "opus response"} = SamgitaProvider.query("test", model: "opus")
    end

    test "returns provider errors" do
      expect(SamgitaProvider.MockProvider, :query, fn _, _ -> {:error, :rate_limit} end)
      assert {:error, :rate_limit} = SamgitaProvider.query("hello")
    end

    test "passes max_turns opt through to the provider" do
      expect(SamgitaProvider.MockProvider, :query, fn "test", [max_turns: 5] ->
        {:ok, "bounded response"}
      end)

      assert {:ok, "bounded response"} = SamgitaProvider.query("test", max_turns: 5)
    end
  end

  describe "provider/0" do
    test "returns the configured provider module" do
      # In test env, config/test.exs sets provider: SamgitaProvider.MockProvider
      assert SamgitaProvider.provider() == SamgitaProvider.MockProvider
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
