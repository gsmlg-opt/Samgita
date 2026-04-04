defmodule Samgita.Agent.ContextAssemblerTest do
  use Samgita.DataCase, async: true

  alias Samgita.Agent.ContextAssembler

  describe "build_continuity_content/1" do
    test "produces markdown with all sections populated" do
      context = %{
        agent_type: "eng-backend",
        task_count: 3,
        retry_count: 1,
        current_task_description: "implement user auth",
        memory_context: %{
          episodic: [
            %{content: "deployed v1"},
            %{content: "fixed auth bug"}
          ],
          semantic: [
            %{content: "Elixir uses BEAM VM"}
          ]
        },
        learnings: ["retry on timeout", "check logs first"]
      }

      content = ContextAssembler.build_continuity_content(context)

      assert content =~ "# Samgita Continuity"
      assert content =~ "Agent: eng-backend"
      assert content =~ "Task Count: 3"
      assert content =~ "Retries: 1"
      assert content =~ "Current Task: implement user auth"
      assert content =~ "## Episodic Memory"
      assert content =~ "- deployed v1"
      assert content =~ "- fixed auth bug"
      assert content =~ "## Semantic Knowledge"
      assert content =~ "- Elixir uses BEAM VM"
      assert content =~ "## Session Learnings"
      assert content =~ "- retry on timeout"
      assert content =~ "- check logs first"
    end

    test "handles empty context without crashing" do
      content = ContextAssembler.build_continuity_content(%{})

      assert content =~ "# Samgita Continuity"
      assert content =~ "Agent: unknown"
      assert content =~ "Task Count: 0"
      assert content =~ "Retries: 0"
      assert content =~ "Current Task: unknown"
      assert content =~ "(none)"
    end

    test "handles nil memory_context gracefully" do
      context = %{
        agent_type: "eng-frontend",
        task_count: 0,
        memory_context: nil,
        learnings: []
      }

      content = ContextAssembler.build_continuity_content(context)

      assert content =~ "## Episodic Memory\n(none)"
      assert content =~ "## Semantic Knowledge\n(none)"
      assert content =~ "## Session Learnings\n(none)"
    end

    test "truncates episodic and semantic to 5 entries" do
      memories = for i <- 1..8, do: %{content: "memory #{i}"}

      context = %{
        memory_context: %{episodic: memories, semantic: memories},
        learnings: for(i <- 1..8, do: "learning #{i}")
      }

      content = ContextAssembler.build_continuity_content(context)

      assert content =~ "- memory 5"
      refute content =~ "- memory 6"
      assert content =~ "- learning 5"
      refute content =~ "- learning 6"
    end
  end

  describe "filter_memory_learnings/1" do
    test "includes semantic and procedural entries" do
      memory = %{
        procedural: [%{content: "run mix test"}, %{content: "use iex"}],
        semantic: [%{content: "BEAM is concurrent"}],
        episodic: [%{content: "deployed yesterday"}]
      }

      result = ContextAssembler.filter_memory_learnings(memory)

      assert "Procedure: run mix test" in result
      assert "Procedure: use iex" in result
      assert "Knowledge: BEAM is concurrent" in result
      # episodic should not be included
      refute Enum.any?(result, &String.contains?(&1, "deployed yesterday"))
    end

    test "caps combined list at 5 entries" do
      memory = %{
        procedural: for(i <- 1..4, do: %{content: "proc #{i}"}),
        semantic: for(i <- 1..4, do: %{content: "sem #{i}"})
      }

      result = ContextAssembler.filter_memory_learnings(memory)

      assert length(result) == 5
    end

    test "returns empty list for nil input" do
      assert ContextAssembler.filter_memory_learnings(nil) == []
    end

    test "returns empty list for map missing expected keys" do
      assert ContextAssembler.filter_memory_learnings(%{foo: :bar}) == []
    end
  end

  describe "format_received_messages/1" do
    test "returns nil for empty list" do
      assert ContextAssembler.format_received_messages([]) == nil
    end

    test "formats messages with sender, type, and content" do
      messages = [
        %{sender_agent_id: "eng-backend", message_type: "request", content: "Need API schema"},
        %{sender_agent_id: "eng-frontend", message_type: "notify", content: "UI ready"}
      ]

      result = ContextAssembler.format_received_messages(messages)

      assert result =~ "- [request] from eng-backend: Need API schema"
      assert result =~ "- [notify] from eng-frontend: UI ready"
    end

    test "defaults missing fields to unknown/notify/empty" do
      messages = [%{}]
      result = ContextAssembler.format_received_messages(messages)

      assert result == "- [notify] from unknown: "
    end

    test "truncates to 10 messages" do
      messages = for i <- 1..15, do: %{sender_agent_id: "agent-#{i}", content: "msg #{i}"}
      result = ContextAssembler.format_received_messages(messages)

      assert result =~ "agent-10"
      refute result =~ "agent-11"
    end
  end

  describe "assemble/1" do
    test "returns map with all expected keys for non-existent project" do
      fake_id = Ecto.UUID.generate()

      result =
        ContextAssembler.assemble(%{
          project_id: fake_id,
          agent_type: "eng-backend",
          task_count: 2,
          learnings: ["learned something"]
        })

      assert is_map(result)
      assert Map.has_key?(result, :learnings)
      assert Map.has_key?(result, :agent_type)
      assert Map.has_key?(result, :task_count)
      assert Map.has_key?(result, :project_info)
      assert Map.has_key?(result, :prd_context)
      assert Map.has_key?(result, :memory_learnings)
      assert Map.has_key?(result, :memory_context)

      assert result.learnings == ["learned something"]
      assert result.agent_type == "eng-backend"
      assert result.task_count == 2
      # Non-existent project yields empty strings
      assert result.project_info == ""
      assert result.prd_context == ""
      assert result.received_messages == []
    end

    test "returns map with all expected keys when data has nil values" do
      result = ContextAssembler.assemble(%{project_id: nil})

      assert result.learnings == []
      assert result.agent_type == nil
      assert result.task_count == 0
      assert result.project_info == ""
      assert result.prd_context == ""
      assert result.memory_learnings == []
      assert result.received_messages == []
    end

    test "passes through received_messages from input data" do
      fake_id = Ecto.UUID.generate()
      messages = [%{sender_agent_id: "eng-qa", message_type: "notify", content: "tests pass"}]

      result =
        ContextAssembler.assemble(%{
          project_id: fake_id,
          agent_type: "eng-backend",
          task_count: 0,
          learnings: [],
          received_messages: messages
        })

      assert result.received_messages == messages
    end
  end

  describe "write_continuity_file/2" do
    test "writes CONTINUITY.md to working path" do
      tmp_dir = System.tmp_dir!()

      working_path =
        Path.join(tmp_dir, "context_assembler_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(working_path)

      on_exit(fn -> File.rm_rf!(working_path) end)

      context = %{
        agent_type: "eng-backend",
        task_count: 1,
        retry_count: 0,
        current_task_description: "write tests",
        memory_context: %{episodic: [], semantic: []},
        learnings: ["always test"]
      }

      assert :ok = ContextAssembler.write_continuity_file(working_path, context)

      continuity_path = Path.join([working_path, ".samgita", "CONTINUITY.md"])
      assert File.exists?(continuity_path)

      content = File.read!(continuity_path)
      assert content =~ "# Samgita Continuity"
      assert content =~ "Agent: eng-backend"
      assert content =~ "- always test"
    end
  end
end
