defmodule SamgitaProvider.SynapsisTest do
  use ExUnit.Case, async: true

  alias SamgitaProvider.Synapsis

  describe "capabilities/0" do
    test "returns full capabilities" do
      caps = Synapsis.capabilities()
      assert caps.supports_streaming == true
      assert caps.supports_tools == true
      assert caps.supports_multi_turn == true
      assert is_integer(caps.max_context_tokens)
      assert is_list(caps.available_models)
    end
  end

  describe "close_session/1" do
    test "returns :ok even when endpoint unreachable" do
      session = SamgitaProvider.Session.new(Synapsis, "test", endpoint: "http://localhost:1")

      session = %{
        session
        | state: %{endpoint: "http://localhost:1", remote_session_id: "fake", api_key: "key"}
      }

      assert :ok = Synapsis.close_session(session)
    end
  end
end
