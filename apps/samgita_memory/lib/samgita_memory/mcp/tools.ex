defmodule SamgitaMemory.MCP.Tools do
  @moduledoc """
  MCP tool definitions for the Samgita Memory System.

  Each tool maps to a SamgitaMemory public API function. The MCP transport
  layer (samgita_mcp app) calls these functions to handle tool invocations.

  Tools:
  - recall       → SamgitaMemory.retrieve/2
  - remember     → SamgitaMemory.store/2
  - forget       → SamgitaMemory.forget/1
  - prd_context  → SamgitaMemory.get_prd_context/2
  - prd_event    → SamgitaMemory.append_prd_event/2
  - prd_decision → SamgitaMemory.record_prd_decision/2
  - think        → SamgitaMemory.add_thought/2
  - start_thinking  → SamgitaMemory.start_chain/2
  - finish_thinking → SamgitaMemory.complete_chain/1
  - recall_reasoning → SamgitaMemory.recall_reasoning/2
  """

  @default_token_budget 4000

  @doc "List all available MCP tool definitions."
  def definitions do
    [
      recall_tool(),
      remember_tool(),
      forget_tool(),
      prd_context_tool(),
      prd_event_tool(),
      prd_decision_tool(),
      think_tool(),
      start_thinking_tool(),
      finish_thinking_tool(),
      recall_reasoning_tool()
    ]
  end

  @doc "Execute a tool by name with the given arguments."
  def execute(tool_name, args, opts \\ []) do
    token_budget = Keyword.get(opts, :token_budget, @default_token_budget)

    result = dispatch(tool_name, args)

    case result do
      {:ok, data} -> {:ok, truncate_to_budget(data, token_budget)}
      {:error, _} = err -> err
    end
  end

  # --- Tool Dispatch ---

  defp dispatch("recall", %{"query" => query} = args) do
    opts = build_retrieve_opts(args)
    memories = SamgitaMemory.retrieve(query, opts)

    formatted =
      Enum.map(memories, fn m ->
        %{
          id: m.id,
          content: m.content,
          type: to_string(m.memory_type),
          scope: "#{m.scope_type}:#{m.scope_id}",
          confidence: m.confidence,
          tags: m.tags,
          created_at: to_string(m.inserted_at)
        }
      end)

    {:ok, %{memories: formatted, total: length(formatted)}}
  end

  defp dispatch("remember", %{"content" => content} = args) do
    opts =
      []
      |> maybe_add_source(args)
      |> maybe_add_scope(args)
      |> maybe_add_type(args)
      |> maybe_add_tags(args)
      |> maybe_add_metadata(args)

    case SamgitaMemory.store(content, opts) do
      {:ok, memory} ->
        {:ok, %{id: memory.id, status: "stored"}}

      {:error, changeset} ->
        {:error, format_errors(changeset)}
    end
  end

  defp dispatch("forget", %{"memory_id" => memory_id}) do
    case SamgitaMemory.forget(memory_id) do
      :ok -> {:ok, %{status: "forgotten"}}
      {:error, :not_found} -> {:error, "Memory not found"}
    end
  end

  defp dispatch("prd_context", %{"prd_id" => prd_id} = args) do
    opts = []
    opts = if args["event_limit"], do: [{:event_limit, args["event_limit"]} | opts], else: opts

    case SamgitaMemory.get_prd_context(prd_id, opts) do
      {:ok, context} ->
        {:ok, format_prd_context(context)}

      {:error, :not_found} ->
        {:error, "PRD execution not found"}
    end
  end

  defp dispatch("prd_event", %{"prd_id" => prd_id} = args) do
    event_attrs = %{
      type: String.to_existing_atom(args["type"]),
      summary: args["summary"],
      requirement_id: args["requirement_id"],
      detail: args["detail"] || %{},
      agent_id: args["agent_id"]
    }

    case SamgitaMemory.append_prd_event(prd_id, event_attrs) do
      {:ok, event} -> {:ok, %{id: event.id, status: "recorded"}}
      {:error, changeset} -> {:error, format_errors(changeset)}
    end
  end

  defp dispatch("prd_decision", %{"prd_id" => prd_id} = args) do
    decision_attrs = %{
      requirement_id: args["requirement_id"],
      decision: args["decision"],
      reason: args["reason"],
      alternatives: args["alternatives"] || [],
      agent_id: args["agent_id"]
    }

    case SamgitaMemory.record_prd_decision(prd_id, decision_attrs) do
      {:ok, decision} -> {:ok, %{id: decision.id, status: "recorded"}}
      {:error, changeset} -> {:error, format_errors(changeset)}
    end
  end

  defp dispatch("think", %{"chain_id" => chain_id, "content" => content} = args) do
    thought = %{
      content: content,
      is_revision: args["is_revision"] || false,
      revises: args["revises"]
    }

    case SamgitaMemory.add_thought(chain_id, thought) do
      {:ok, chain} ->
        {:ok, %{chain_id: chain.id, thought_count: length(chain.thoughts)}}

      {:error, :not_found} ->
        {:error, "Thinking chain not found"}
    end
  end

  defp dispatch("start_thinking", %{"query" => query} = args) do
    opts =
      []
      |> maybe_add_scope_type(args)
      |> maybe_add_scope_id(args)

    case SamgitaMemory.start_chain(query, opts) do
      {:ok, chain} -> {:ok, %{chain_id: chain.id, status: "active"}}
      {:error, changeset} -> {:error, format_errors(changeset)}
    end
  end

  defp dispatch("finish_thinking", %{"chain_id" => chain_id}) do
    case SamgitaMemory.complete_chain(chain_id) do
      {:ok, chain} ->
        {:ok, %{chain_id: chain.id, status: "completed"}}

      {:error, :not_found} ->
        {:error, "Thinking chain not found"}
    end
  end

  defp dispatch("recall_reasoning", %{"query" => query} = args) do
    opts =
      []
      |> maybe_add_scope_type(args)
      |> maybe_add_scope_id(args)
      |> maybe_add_limit(args)

    chains = SamgitaMemory.recall_reasoning(query, opts)

    formatted =
      Enum.map(chains, fn c ->
        %{
          id: c.id,
          query: c.query,
          summary: c.summary,
          thought_count: length(c.thoughts || []),
          scope: "#{c.scope_type}:#{c.scope_id}",
          created_at: to_string(c.inserted_at)
        }
      end)

    {:ok, %{chains: formatted, total: length(formatted)}}
  end

  defp dispatch(tool_name, _args) do
    {:error, "Unknown tool: #{tool_name}"}
  end

  # --- Tool Definitions ---

  defp recall_tool do
    %{
      name: "recall",
      description: "Retrieve relevant memories for a query",
      inputSchema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "What to search for"},
          scope_type: %{type: "string", enum: ["global", "project", "agent"]},
          scope_id: %{type: "string"},
          tags: %{type: "array", items: %{type: "string"}},
          limit: %{type: "integer", default: 10},
          min_confidence: %{type: "number", default: 0.3}
        },
        required: ["query"]
      }
    }
  end

  defp remember_tool do
    %{
      name: "remember",
      description: "Store a memory for future retrieval",
      inputSchema: %{
        type: "object",
        properties: %{
          content: %{type: "string", description: "The fact or knowledge to remember"},
          source_type: %{type: "string", enum: ["conversation", "observation", "user_edit"]},
          source_id: %{type: "string"},
          scope_type: %{type: "string", enum: ["global", "project", "agent"]},
          scope_id: %{type: "string"},
          memory_type: %{type: "string", enum: ["episodic", "semantic", "procedural"]},
          tags: %{type: "array", items: %{type: "string"}},
          metadata: %{type: "object"}
        },
        required: ["content"]
      }
    }
  end

  defp forget_tool do
    %{
      name: "forget",
      description: "Remove a specific memory",
      inputSchema: %{
        type: "object",
        properties: %{
          memory_id: %{type: "string", description: "The memory ID to forget"}
        },
        required: ["memory_id"]
      }
    }
  end

  defp prd_context_tool do
    %{
      name: "prd_context",
      description: "Get full PRD execution state for resume",
      inputSchema: %{
        type: "object",
        properties: %{
          prd_id: %{type: "string", description: "The PRD execution ID"},
          event_limit: %{type: "integer", default: 50}
        },
        required: ["prd_id"]
      }
    }
  end

  defp prd_event_tool do
    %{
      name: "prd_event",
      description: "Log an event during PRD execution",
      inputSchema: %{
        type: "object",
        properties: %{
          prd_id: %{type: "string"},
          type: %{
            type: "string",
            enum: [
              "requirement_started",
              "requirement_completed",
              "decision_made",
              "blocker_hit",
              "blocker_resolved",
              "test_passed",
              "test_failed",
              "revision",
              "review_feedback",
              "agent_handoff",
              "error_encountered",
              "rollback"
            ]
          },
          summary: %{type: "string"},
          requirement_id: %{type: "string"},
          detail: %{type: "object"},
          agent_id: %{type: "string"}
        },
        required: ["prd_id", "type", "summary"]
      }
    }
  end

  defp prd_decision_tool do
    %{
      name: "prd_decision",
      description: "Record a decision made during PRD execution",
      inputSchema: %{
        type: "object",
        properties: %{
          prd_id: %{type: "string"},
          requirement_id: %{type: "string"},
          decision: %{type: "string"},
          reason: %{type: "string"},
          alternatives: %{type: "array", items: %{type: "string"}},
          agent_id: %{type: "string"}
        },
        required: ["prd_id", "decision"]
      }
    }
  end

  defp think_tool do
    %{
      name: "think",
      description: "Add a thought to an active thinking chain",
      inputSchema: %{
        type: "object",
        properties: %{
          chain_id: %{type: "string"},
          content: %{type: "string"},
          is_revision: %{type: "boolean", default: false},
          revises: %{type: "integer", description: "Thought number being revised"}
        },
        required: ["chain_id", "content"]
      }
    }
  end

  defp start_thinking_tool do
    %{
      name: "start_thinking",
      description: "Begin a new reasoning chain",
      inputSchema: %{
        type: "object",
        properties: %{
          query: %{type: "string", description: "What to reason about"},
          scope_type: %{type: "string", enum: ["global", "project", "agent"]},
          scope_id: %{type: "string"}
        },
        required: ["query"]
      }
    }
  end

  defp finish_thinking_tool do
    %{
      name: "finish_thinking",
      description: "Complete a thinking chain, triggering summarization",
      inputSchema: %{
        type: "object",
        properties: %{
          chain_id: %{type: "string"}
        },
        required: ["chain_id"]
      }
    }
  end

  defp recall_reasoning_tool do
    %{
      name: "recall_reasoning",
      description: "Find similar past reasoning chains",
      inputSchema: %{
        type: "object",
        properties: %{
          query: %{type: "string"},
          scope_type: %{type: "string", enum: ["global", "project", "agent"]},
          scope_id: %{type: "string"},
          limit: %{type: "integer", default: 5}
        },
        required: ["query"]
      }
    }
  end

  # --- Helpers ---

  defp build_retrieve_opts(args) do
    opts = []

    opts =
      if args["scope_type"] do
        scope_type = String.to_existing_atom(args["scope_type"])
        [{:scope, {scope_type, args["scope_id"]}} | opts]
      else
        opts
      end

    opts = if args["tags"], do: [{:tags, args["tags"]} | opts], else: opts
    opts = if args["limit"], do: [{:limit, args["limit"]} | opts], else: opts

    opts =
      if args["min_confidence"],
        do: [{:min_confidence, args["min_confidence"]} | opts],
        else: opts

    opts
  end

  defp maybe_add_source(opts, %{"source_type" => st, "source_id" => sid}),
    do: [{:source, {String.to_existing_atom(st), sid}} | opts]

  defp maybe_add_source(opts, %{"source_type" => st}),
    do: [{:source, {String.to_existing_atom(st), nil}} | opts]

  defp maybe_add_source(opts, _), do: opts

  defp maybe_add_scope(opts, %{"scope_type" => st, "scope_id" => sid}),
    do: [{:scope, {String.to_existing_atom(st), sid}} | opts]

  defp maybe_add_scope(opts, %{"scope_type" => st}),
    do: [{:scope, {String.to_existing_atom(st), nil}} | opts]

  defp maybe_add_scope(opts, _), do: opts

  defp maybe_add_type(opts, %{"memory_type" => t}),
    do: [{:type, String.to_existing_atom(t)} | opts]

  defp maybe_add_type(opts, _), do: opts

  defp maybe_add_tags(opts, %{"tags" => tags}), do: [{:tags, tags} | opts]
  defp maybe_add_tags(opts, _), do: opts

  defp maybe_add_metadata(opts, %{"metadata" => m}), do: [{:metadata, m} | opts]
  defp maybe_add_metadata(opts, _), do: opts

  defp maybe_add_scope_type(opts, %{"scope_type" => st}),
    do: [{:scope_type, String.to_existing_atom(st)} | opts]

  defp maybe_add_scope_type(opts, _), do: opts

  defp maybe_add_scope_id(opts, %{"scope_id" => sid}), do: [{:scope_id, sid} | opts]
  defp maybe_add_scope_id(opts, _), do: opts

  defp maybe_add_limit(opts, %{"limit" => l}), do: [{:limit, l} | opts]
  defp maybe_add_limit(opts, _), do: opts

  defp format_prd_context(context) do
    %{
      execution: %{
        id: context.execution.id,
        prd_ref: context.execution.prd_ref,
        title: context.execution.title,
        status: to_string(context.execution.status)
      },
      recent_events:
        Enum.map(context.recent_events, fn e ->
          %{
            id: e.id,
            type: to_string(e.type),
            summary: e.summary,
            requirement_id: e.requirement_id,
            created_at: to_string(e.inserted_at)
          }
        end),
      decisions:
        Enum.map(context.decisions, fn d ->
          %{
            id: d.id,
            decision: d.decision,
            reason: d.reason,
            requirement_id: d.requirement_id
          }
        end)
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> inspect()
  end

  defp format_errors(error), do: inspect(error)

  # Token budget truncation
  defp truncate_to_budget(data, budget) when is_map(data) do
    json = Jason.encode!(data)
    # Rough token estimate: ~4 chars per token
    estimated_tokens = div(byte_size(json), 4)

    if estimated_tokens <= budget do
      data
    else
      truncate_map_to_budget(data, budget)
    end
  end

  defp truncate_to_budget(data, _budget), do: data

  defp truncate_map_to_budget(data, budget) do
    # For lists of items (memories, events, etc.), drop items from the end
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      truncated =
        case value do
          items when is_list(items) ->
            # Keep taking items until we approach budget
            take_within_budget(items, budget)

          _ ->
            value
        end

      Map.put(acc, key, truncated)
    end)
  end

  defp take_within_budget(items, budget) do
    {taken, _remaining_budget} =
      Enum.reduce_while(items, {[], budget}, fn item, {acc, remaining} ->
        item_size = div(byte_size(Jason.encode!(item)), 4)

        if remaining - item_size > 0 do
          {:cont, {[item | acc], remaining - item_size}}
        else
          {:halt, {acc, 0}}
        end
      end)

    result = Enum.reverse(taken)

    if length(result) < length(items) do
      result ++ [%{truncated: true, total: length(items), shown: length(result)}]
    else
      result
    end
  end
end
