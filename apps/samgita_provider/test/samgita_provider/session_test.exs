defmodule SamgitaProvider.SessionTest do
  use ExUnit.Case, async: true

  alias SamgitaProvider.Session

  describe "new/3" do
    test "creates a session with a UUID id" do
      session = Session.new(SamgitaProvider.ClaudeCode, "You are helpful.")
      assert is_binary(session.id)
      assert byte_size(session.id) == 36
      assert String.match?(session.id, ~r/^[0-9a-f-]{36}$/)
    end

    test "sets the provider field correctly" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.provider == SamgitaProvider.ClaudeCode
    end

    test "sets the system_prompt field correctly" do
      session = Session.new(SamgitaProvider.ClaudeCode, "Be concise.")
      assert session.system_prompt == "Be concise."
    end

    test "sets model from opts" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt", model: "opus")
      assert session.model == "opus"
    end

    test "defaults model to \"sonnet\" when not in opts" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.model == "sonnet"
    end

    test "sets message_count to 0" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.message_count == 0
    end

    test "sets total_tokens to 0" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.total_tokens == 0
    end

    test "sets started_at to a DateTime" do
      before = DateTime.utc_now()
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      after_dt = DateTime.utc_now()

      assert %DateTime{} = session.started_at
      assert DateTime.compare(session.started_at, before) in [:gt, :eq]
      assert DateTime.compare(session.started_at, after_dt) in [:lt, :eq]
    end
  end

  describe "increment_message_count/1" do
    test "increments message_count by 1" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.message_count == 0

      updated = Session.increment_message_count(session)
      assert updated.message_count == 1

      updated2 = Session.increment_message_count(updated)
      assert updated2.message_count == 2
    end
  end

  describe "add_tokens/2" do
    test "adds the given count to total_tokens" do
      session = Session.new(SamgitaProvider.ClaudeCode, "prompt")
      assert session.total_tokens == 0

      updated = Session.add_tokens(session, 150)
      assert updated.total_tokens == 150

      updated2 = Session.add_tokens(updated, 300)
      assert updated2.total_tokens == 450
    end
  end
end
