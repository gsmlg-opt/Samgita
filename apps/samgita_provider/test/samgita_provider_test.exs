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

  # -- Fallback behaviour tests -----------------------------------------------
  #
  # SamgitaProvider.QueryOnlyProvider implements only `query/2`, so
  # `function_exported?/3` returns false for all optional callbacks.
  # We build Session structs with that provider to exercise the fallback paths.

  describe "start_session/2 fallback" do
    test "creates a Session struct when provider lacks start_session" do
      session = build_fallback_session("You are helpful")

      assert %SamgitaProvider.Session{} = session
      assert session.provider == SamgitaProvider.QueryOnlyProvider
      assert session.system_prompt == "You are helpful"
      assert session.model == "sonnet"
      assert session.message_count == 0
      assert session.total_tokens == 0
    end

    test "passes model option through to the Session" do
      session = build_fallback_session("Be concise", model: "opus")

      assert session.model == "opus"
      assert session.system_prompt == "Be concise"
    end

    test "passes additional options through to the Session" do
      session = build_fallback_session("prompt", model: "haiku", max_turns: 5)

      assert session.model == "haiku"
      assert session.opts == [max_turns: 5]
    end
  end

  describe "send_message/2 fallback" do
    test "falls back to query/2 with session context" do
      session = build_fallback_session("You are helpful")

      assert {:ok, "query_only response", updated_session} =
               SamgitaProvider.send_message(session, "Hello")

      assert updated_session.message_count == 1
    end

    test "preserves session opts in the fallback query call" do
      session = build_fallback_session("prompt", model: "opus", max_turns: 3)

      assert {:ok, "query_only response", updated} =
               SamgitaProvider.send_message(session, "test")

      assert updated.message_count == 1
      assert updated.model == "opus"
    end
  end

  describe "stream_message/3 fallback" do
    test "falls back to send_message and delivers chunks to subscriber" do
      session = build_fallback_session("system")

      assert {:ok, ref, updated_session} =
               SamgitaProvider.stream_message(session, "Hello", self())

      assert is_reference(ref)
      assert updated_session.message_count == 1

      assert_received {:stream_chunk, ^ref, "query_only response"}
      assert_received {:stream_done, ^ref}
    end
  end

  describe "close_session/1 fallback" do
    test "returns :ok when provider lacks close_session" do
      session = build_fallback_session("system")

      assert :ok = SamgitaProvider.close_session(session)
    end
  end

  describe "capabilities/0 fallback" do
    test "returns default capabilities when provider lacks capabilities callback" do
      # Temporarily override the configured provider to the query-only one
      original = Application.get_env(:samgita_provider, :provider)
      Application.put_env(:samgita_provider, :provider, SamgitaProvider.QueryOnlyProvider)

      try do
        caps = SamgitaProvider.capabilities()

        assert caps == %{
                 supports_streaming: false,
                 supports_tools: false,
                 supports_multi_turn: false,
                 max_context_tokens: 200_000,
                 available_models: ["sonnet"]
               }
      after
        Application.put_env(:samgita_provider, :provider, original)
      end
    end
  end

  describe "health_check/0 fallback" do
    test "returns :ok when provider lacks health_check callback" do
      original = Application.get_env(:samgita_provider, :provider)
      Application.put_env(:samgita_provider, :provider, SamgitaProvider.QueryOnlyProvider)

      try do
        assert :ok = SamgitaProvider.health_check()
      after
        Application.put_env(:samgita_provider, :provider, original)
      end
    end
  end

  # -- Delegation tests --------------------------------------------------------
  #
  # When the provider implements the optional callbacks, SamgitaProvider should
  # delegate directly.  The Mox mock defines all callbacks from the behaviour.

  describe "start_session/2 delegation" do
    test "delegates to provider when start_session is implemented" do
      expected_session = build_mock_session("system")

      expect(SamgitaProvider.MockProvider, :start_session, fn "system", [] ->
        {:ok, expected_session}
      end)

      assert {:ok, ^expected_session} = SamgitaProvider.start_session("system")
    end

    test "passes opts through to the provider" do
      expected_session = build_mock_session("system", model: "opus")

      expect(SamgitaProvider.MockProvider, :start_session, fn "system", [model: "opus"] ->
        {:ok, expected_session}
      end)

      assert {:ok, ^expected_session} = SamgitaProvider.start_session("system", model: "opus")
    end
  end

  describe "send_message/2 delegation" do
    test "delegates to provider when send_message is implemented" do
      session = build_mock_session("system")
      updated = %{session | message_count: 1}

      expect(SamgitaProvider.MockProvider, :send_message, fn ^session, "Hello" ->
        {:ok, "Hi!", updated}
      end)

      assert {:ok, "Hi!", ^updated} = SamgitaProvider.send_message(session, "Hello")
    end
  end

  describe "stream_message/3 delegation" do
    test "delegates to provider when stream_message is implemented" do
      session = build_mock_session("system")
      ref = make_ref()
      updated = %{session | message_count: 1}

      expect(SamgitaProvider.MockProvider, :stream_message, fn ^session, "Hello", subscriber ->
        send(subscriber, {:stream_chunk, ref, "chunk1"})
        send(subscriber, {:stream_done, ref})
        {:ok, ref, updated}
      end)

      assert {:ok, ^ref, ^updated} = SamgitaProvider.stream_message(session, "Hello", self())

      assert_received {:stream_chunk, ^ref, "chunk1"}
      assert_received {:stream_done, ^ref}
    end
  end

  describe "close_session/1 delegation" do
    test "delegates to provider when close_session is implemented" do
      session = build_mock_session("system")

      expect(SamgitaProvider.MockProvider, :close_session, fn ^session -> :ok end)

      assert :ok = SamgitaProvider.close_session(session)
    end
  end

  describe "capabilities/0 delegation" do
    test "delegates to provider when capabilities is implemented" do
      custom_caps = %{
        supports_streaming: true,
        supports_tools: true,
        supports_multi_turn: true,
        max_context_tokens: 1_000_000,
        available_models: ["sonnet", "opus"]
      }

      expect(SamgitaProvider.MockProvider, :capabilities, fn -> custom_caps end)

      assert SamgitaProvider.capabilities() == custom_caps
    end
  end

  describe "health_check/0 delegation" do
    test "returns :ok when provider health check succeeds" do
      expect(SamgitaProvider.MockProvider, :health_check, fn -> :ok end)

      assert :ok = SamgitaProvider.health_check()
    end

    test "returns error when provider health check fails" do
      expect(SamgitaProvider.MockProvider, :health_check, fn -> {:error, :connection_refused} end)

      assert {:error, :connection_refused} = SamgitaProvider.health_check()
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

  # Builds a session for the QueryOnlyProvider (fallback tests).
  defp build_fallback_session(system_prompt, opts \\ []) do
    SamgitaProvider.Session.new(SamgitaProvider.QueryOnlyProvider, system_prompt, opts)
  end

  # Builds a session for the MockProvider (delegation tests).
  defp build_mock_session(system_prompt, opts \\ []) do
    SamgitaProvider.Session.new(SamgitaProvider.MockProvider, system_prompt, opts)
  end
end
