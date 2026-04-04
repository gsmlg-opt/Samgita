defmodule SamgitaProvider.ClaudeAPITest do
  use ExUnit.Case, async: true

  alias SamgitaProvider.ClaudeAPI
  alias SamgitaProvider.Session

  describe "start_session/2" do
    test "returns session with empty messages" do
      {:ok, session} = ClaudeAPI.start_session("You are helpful")
      assert %Session{} = session
      assert session.provider == ClaudeAPI
      assert session.system_prompt == "You are helpful"
      assert session.state.messages == []
      assert session.message_count == 0
    end

    test "stores model from opts" do
      {:ok, session} = ClaudeAPI.start_session("test", model: "opus")
      assert session.model == "opus"
    end
  end

  describe "close_session/1" do
    test "returns :ok" do
      {:ok, session} = ClaudeAPI.start_session("test")
      assert :ok = ClaudeAPI.close_session(session)
    end
  end

  describe "capabilities/0" do
    test "returns expected capabilities" do
      caps = ClaudeAPI.capabilities()
      assert caps.supports_streaming == true
      assert caps.supports_tools == true
      assert caps.supports_multi_turn == true
      assert is_integer(caps.max_context_tokens)
      assert is_list(caps.available_models)
    end
  end
end
