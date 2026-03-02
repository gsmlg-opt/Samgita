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

    test "ignores opts" do
      assert SamgitaProvider.Codex.build_args("test", model: "opus", system_prompt: "x") ==
               ["exec", "--full-auto", "test"]
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
