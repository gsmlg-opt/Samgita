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
  end
end
