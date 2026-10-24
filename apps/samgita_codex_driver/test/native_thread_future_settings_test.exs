defmodule SamgitaCodexDriver.NativeThreadFutureSettingsTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture, TurnFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  import TurnFixture,
    only: [call: 3, upstream_error: 4, thread: 3, start_turn: 3, finish_turn: 3, notification: 2]

  @moduletag :real_codex
  @moduletag timeout: 60_000
  @binary_sha256 "399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215"
  @script Path.expand("../../../scripts/codex/active_turn_settings_fixture.py", __DIR__)
  @model_a "step-settings-a"
  @model_b "step-settings-b"
  @lookup %{
    "type" => "function",
    "name" => "fixture_lookup",
    "description" => "Synthetic lookup that waits for an explicit test response",
    "inputSchema" => %{
      "type" => "object",
      "properties" => %{"key" => %{"type" => "string"}},
      "required" => ["key"],
      "additionalProperties" => false
    }
  }

  setup tags do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: immutable CODEX_BINARY required"

    assert Base.encode16(:crypto.hash(:sha256, File.read!(binary)), case: :lower) ==
             @binary_sha256

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-future-settings-#{Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    previous = System.get_env("CODEX_MODEL_FIXTURE_SCRIPT")
    System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", @script)

    fixture =
      try do
        ModelFixture.start(root, tags[:scenario] || "active")
      after
        if previous,
          do: System.put_env("CODEX_MODEL_FIXTURE_SCRIPT", previous),
          else: System.delete_env("CODEX_MODEL_FIXTURE_SCRIPT")
      end

    on_exit(fn -> assert :ok = ModelFixture.close(fixture) end)
    File.write!(fixture.requests, "[]")
    next_cwd = Path.join(root, "future-workspace")
    Enum.each([next_cwd, Path.join(root, "tmp")], &File.mkdir!/1)
    %{binary: binary, root: root, fixture: fixture, next_cwd: next_cwd}
  end

  @tag scenario: "assistant"
  test "turn cwd overrides persist through omitted and null input without changing a sibling",
       ctx do
    pid = start(ctx)
    selected = thread(ctx, pid, %{"model" => @model_a})
    sibling = thread(ctx, pid, %{"model" => @model_a})
    refute selected == sibling
    config = Path.join(ctx.fixture.codex_home, "config.toml")
    config_before = File.read!(config)

    cases = [
      {selected, %{}, ctx.fixture.workspace},
      {selected, %{"cwd" => ctx.next_cwd}, ctx.next_cwd},
      {selected, %{}, ctx.next_cwd},
      {selected, %{"cwd" => nil}, ctx.next_cwd},
      {sibling, %{}, ctx.fixture.workspace}
    ]

    for {{id, overrides, expected_cwd}, index} <- Enum.with_index(cases, 1) do
      turn =
        TurnFixture.start_turn(pid, id, text("Owned turn cwd selection #{index}: λ🙂"), overrides)

      finish_turn(pid, id, turn)
      requests = ModelFixture.requests(ctx.fixture)
      assert length(requests) == index
      request = List.last(requests)
      assert_initial(request)
      assert_environment(List.last(environment_texts(request)), expected_cwd)
      assert_idle(pid)
      assert Session.interaction_outcomes(pid) == []
      assert Session.uncertain_operations(pid) == []
    end

    assert length(ModelFixture.requests(ctx.fixture)) == 5
    assert File.read!(config) == config_before
    assert :ok = Session.close(pid)
  end

  test "thread publication changes future capture while the active turn retains its settings and environment",
       ctx do
    {pid, id, turn, tool, events} = active(ctx)

    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "model" => @model_b,
             "effort" => "high",
             "summary" => "detailed",
             "cwd" => ctx.next_cwd
           }) == %{}

    # The response acknowledges queueing. Only the matching applied snapshot is
    # the barrier before dependent requests or assertions about future defaults.
    events = await_settings(pid, id, ctx.next_cwd, events, deadline())
    assert_pending(ctx, pid, id, turn, tool)

    assert call(pid, "thread/settings/update", %{"threadId" => id}) == %{}

    assert call(pid, "thread/settings/update", %{
             "threadId" => id,
             "model" => nil,
             "effort" => nil,
             "summary" => nil,
             "cwd" => nil
           }) == %{}

    # Both requests are no-ops; do not wait for notifications they need not emit.
    assert_pending(ctx, pid, id, turn, tool)
    finish_active(ctx, pid, id, turn, tool, events)
    future = start_turn(pid, id, text("Use the future synthetic settings"))
    finish_turn(pid, id, future)

    assert [first, continued, next] = ModelFixture.requests(ctx.fixture)
    assert_initial(first)
    assert_initial(continued)
    assert environment_texts(continued) == environment_texts(first)
    assert_environment(List.last(environment_texts(first)), ctx.fixture.workspace)
    assert next["model"] == @model_b
    assert next["reasoning"] == %{"effort" => "high", "summary" => "detailed"}
    assert_environment(List.last(environment_texts(next)), ctx.next_cwd)
    assert_idle(pid)
  end

  test "native malformed settings and unknown targets preserve the pending tool and future defaults",
       ctx do
    {pid, id, turn, tool, events} = active(ctx)

    for invalid <- [
          %{},
          %{"threadId" => nil},
          %{"threadId" => 17},
          %{"threadId" => id, "model" => 17},
          %{"threadId" => id, "effort" => 17},
          %{"threadId" => id, "summary" => 17},
          %{"threadId" => id, "summary" => "unsupported"},
          %{"threadId" => id, "cwd" => 17}
        ] do
      error = upstream_error(pid, "thread/settings/update", invalid, validation: :wire)
      assert error["code"] == -32_600
      assert String.starts_with?(error["message"], "Invalid request:")
      assert_pending(ctx, pid, id, turn, tool)
    end

    malformed =
      upstream_error(pid, "thread/settings/update", %{"threadId" => "invalid-thread"},
        validation: :wire
      )

    assert malformed["code"] == -32_600
    assert String.starts_with?(malformed["message"], "invalid thread id:")

    missing = "00000000-0000-4000-8000-000000000001"

    assert upstream_error(pid, "thread/settings/update", %{"threadId" => missing},
             validation: :wire
           ) == %{
             "code" => -32_600,
             "message" => "thread not found: #{missing}"
           }

    assert_pending(ctx, pid, id, turn, tool)
    finish_active(ctx, pid, id, turn, tool, events)
    future = start_turn(pid, id, text("Use the unchanged synthetic defaults"))
    finish_turn(pid, id, future)
    assert [first, continued, next] = ModelFixture.requests(ctx.fixture)
    Enum.each([first, continued, next], &assert_initial/1)
    assert environment_texts(continued) == environment_texts(first)
    assert_environment(List.last(environment_texts(next)), ctx.fixture.workspace)
    assert_idle(pid)
  end

  @tag scenario: "assistant"
  test "idle settings retain granular defaults reviewer alias and saved personality without execution",
       ctx do
    {pid, id} = idle_thread(ctx)

    granular = %{
      "granular" => %{
        "sandbox_approval" => false,
        "rules" => false,
        "mcp_elicitations" => false
      }
    }

    expected_policy = %{
      "granular" =>
        Map.merge(granular["granular"], %{
          "skill_approval" => false,
          "request_permissions" => false
        })
    }

    settings =
      idle_update(
        ctx,
        pid,
        id,
        %{
          "approvalPolicy" => granular,
          "approvalsReviewer" => "guardian_subagent",
          "personality" => "friendly",
          "summary" => "detailed"
        },
        %{
          "approvalPolicy" => expected_policy,
          "approvalsReviewer" => "auto_review",
          "personality" => "friendly",
          "summary" => "detailed"
        }
      )

    # Saved settings only: no turn or automatic reviewer is launched.
    settings =
      Enum.reduce(
        [
          %{"approvalsReviewer" => "unknown-reviewer"},
          %{"approvalPolicy" => %{"granular" => %{"sandbox_approval" => false, "rules" => false}}}
        ],
        settings,
        fn invalid, previous ->
          error =
            upstream_error(pid, "thread/settings/update", Map.put(invalid, "threadId", id),
              validation: :wire
            )

          assert error["code"] == -32_600
          assert String.starts_with?(error["message"], "Invalid request:")
          idle_preserved(ctx, pid, id, previous)
        end
      )

    changed =
      idle_update(
        ctx,
        pid,
        id,
        %{
          "approvalsReviewer" => "user",
          "personality" => "pragmatic",
          "summary" => "auto"
        },
        %{
          "approvalPolicy" => expected_policy,
          "approvalsReviewer" => "user",
          "personality" => "pragmatic",
          "summary" => "auto"
        }
      )

    assert Map.drop(changed, ["summary", "personality", "approvalsReviewer"]) ==
             Map.drop(settings, ["summary", "personality", "approvalsReviewer"])

    finish_idle(ctx, pid)
  end

  @tag scenario: "assistant"
  test "idle collaboration wins over model effort and null instructions select the pinned builtin",
       ctx do
    {pid, id} = idle_thread(ctx)

    custom = %{
      "mode" => "plan",
      "settings" => %{
        "model" => @model_b,
        "reasoning_effort" => "high",
        "developer_instructions" => "Synthetic idle collaboration instructions only."
      }
    }

    settings =
      idle_update(
        ctx,
        pid,
        id,
        %{
          "model" => @model_a,
          "effort" => "low",
          "collaborationMode" => custom,
          "summary" => "detailed"
        },
        %{
          "model" => @model_b,
          "effort" => "high",
          "collaborationMode" => custom,
          "summary" => "detailed"
        }
      )

    error =
      upstream_error(
        pid,
        "thread/settings/update",
        %{
          "threadId" => id,
          "collaborationMode" => %{"mode" => "unsupported", "settings" => custom["settings"]}
        },
        validation: :wire
      )

    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "Invalid request:")
    settings = idle_preserved(ctx, pid, id, settings)

    builtin =
      idle_update(
        ctx,
        pid,
        id,
        %{
          "collaborationMode" => %{
            "mode" => "default",
            "settings" => %{
              "model" => @model_a,
              "reasoning_effort" => nil,
              "developer_instructions" => nil
            }
          },
          "summary" => "auto"
        },
        %{"model" => @model_a, "effort" => nil, "summary" => "auto"}
      )

    assert %{
             "mode" => "default",
             "settings" => %{
               "model" => @model_a,
               "reasoning_effort" => nil,
               "developer_instructions" => instructions
             }
           } = builtin["collaborationMode"]

    assert is_binary(instructions)
    # Exact include_str! bytes from immutable 83086188.
    # codex-rs/collaboration-mode-templates/templates/default.md
    assert Base.encode16(:crypto.hash(:sha256, instructions), case: :lower) ==
             "1042cc643eb0147ca1039b19287c7462ceb297502f7f310d9664ac323a12feca"

    assert Map.drop(builtin, ["summary", "model", "effort", "collaborationMode"]) ==
             Map.drop(settings, ["summary", "model", "effort", "collaborationMode"])

    finish_idle(ctx, pid)
  end

  @tag scenario: "assistant"
  test "idle deprecated multi agent inputs are ignored and root nulls preserve saved settings",
       ctx do
    {pid, id} = idle_thread(ctx)

    collaboration = %{
      "mode" => "plan",
      "settings" => %{
        "model" => @model_b,
        "reasoning_effort" => "high",
        "developer_instructions" => "Synthetic preserved idle settings."
      }
    }

    settings =
      idle_update(
        ctx,
        pid,
        id,
        %{
          "approvalPolicy" => "on-request",
          "approvalsReviewer" => "user",
          "permissions" => ":read-only",
          "personality" => "friendly",
          "collaborationMode" => collaboration,
          "summary" => "detailed"
        },
        %{
          "approvalPolicy" => "on-request",
          "approvalsReviewer" => "user",
          "personality" => "friendly",
          "collaborationMode" => collaboration,
          "model" => @model_b,
          "effort" => "high",
          "summary" => "detailed",
          "multiAgentMode" => "explicitRequestOnly"
        }
      )

    assert settings["activePermissionProfile"]["id"] == ":read-only"

    # Pin the native no-op; accepting this deprecated field does not implement
    # proactive/custom delegation. A changed summary is the applied barrier.
    settings =
      Enum.reduce(
        [
          {"proactive", "concise"},
          {%{"custom" => "Synthetic ignored delegation hint."}, "auto"}
        ],
        settings,
        fn {mode, marker}, previous ->
          current =
            idle_update(ctx, pid, id, %{"multiAgentMode" => mode, "summary" => marker}, %{
              "multiAgentMode" => "explicitRequestOnly",
              "summary" => marker
            })

          assert Map.delete(current, "summary") == Map.delete(previous, "summary")
          current
        end
      )

    nulls =
      Map.new(
        ~w(approvalPolicy approvalsReviewer collaborationMode multiAgentMode
      personality permissions sandboxPolicy),
        &{&1, nil}
      )

    preserved =
      idle_update(ctx, pid, id, Map.put(nulls, "summary", "detailed"), %{
        "summary" => "detailed",
        "multiAgentMode" => "explicitRequestOnly"
      })

    assert Map.delete(preserved, "summary") == Map.delete(settings, "summary")
    finish_idle(ctx, pid)
  end

  @tag scenario: "assistant"
  test "idle named read only permissions and legacy sandbox preserve errors and profile provenance",
       ctx do
    config = Path.join(ctx.fixture.codex_home, "config.toml")
    File.write!(config, "\n[permissions.audit]\nextends = ':read-only'\n", [:append])
    {pid, id} = idle_thread(ctx)

    settings =
      idle_update(ctx, pid, id, %{"permissions" => "audit", "summary" => "detailed"}, %{
        "summary" => "detailed",
        "activePermissionProfile" => %{"id" => "audit", "extends" => ":read-only"},
        "sandboxPolicy" => %{"type" => "readOnly", "networkAccess" => false}
      })

    assert upstream_error(
             pid,
             "thread/settings/update",
             %{
               "threadId" => id,
               "permissions" => "audit",
               "sandboxPolicy" => %{"type" => "readOnly"}
             },
             validation: :wire
           ) == %{
             "code" => -32_600,
             "message" => "`permissions` cannot be combined with `sandboxPolicy`"
           }

    settings = idle_preserved(ctx, pid, id, settings)

    error =
      upstream_error(
        pid,
        "thread/settings/update",
        %{
          "threadId" => id,
          "sandboxPolicy" => %{"type" => "readOnly", "networkAccess" => "no"}
        },
        validation: :wire
      )

    assert error["code"] == -32_600
    assert String.starts_with?(error["message"], "Invalid request:")
    settings = idle_preserved(ctx, pid, id, settings)

    legacy =
      idle_update(
        ctx,
        pid,
        id,
        %{"sandboxPolicy" => %{"type" => "readOnly"}, "summary" => "auto"},
        %{
          "summary" => "auto",
          "activePermissionProfile" => nil,
          "sandboxPolicy" => %{"type" => "readOnly", "networkAccess" => false}
        }
      )

    assert Map.drop(legacy, ["summary", "activePermissionProfile"]) ==
             Map.drop(settings, ["summary", "activePermissionProfile"])

    finish_idle(ctx, pid)
  end

  test "paginated active turn rejects inclusive fork while exclusive child leaves the exact callback pending",
       ctx do
    sentinel = Path.join(ctx.fixture.workspace, "owned-active-fork-canary.txt")
    canary = "OWNED_ACTIVE_FORK_UNCHANGED\n"
    File.write!(sentinel, canary, [:exclusive])
    {pid, id, turn, tool, events} = active(ctx, %{"historyMode" => "paginated"})
    assert [first] = ModelFixture.requests(ctx.fixture)
    assert Session.interaction_outcomes(pid) == []
    loaded = call(pid, "thread/loaded/list", %{})
    assert loaded["data"] == [id]

    # prepare_fork persists the live writer before selecting a boundary. The
    # actual callback, rather than a fabricated rollout, keeps this turn active.
    assert upstream_error(
             pid,
             "thread/fork",
             %{
               "threadId" => id,
               "lastTurnId" => turn,
               "ephemeral" => false,
               "excludeTurns" => true
             },
             []
           ) == %{
             "code" => -32_600,
             "message" => "lastTurnId '#{turn}' identifies an in-progress turn"
           }

    assert call(pid, "thread/loaded/list", %{}) === loaded
    assert_pending(ctx, pid, id, turn, tool)
    assert ModelFixture.requests(ctx.fixture) === [first]
    assert Session.interaction_outcomes(pid) == []

    forked =
      call(pid, "thread/fork", %{
        "threadId" => id,
        "beforeTurnId" => turn,
        "ephemeral" => false,
        "excludeTurns" => true
      })

    child = forked["thread"]
    child_id = child["id"]
    assert is_binary(child_id) and child_id != id
    assert child["forkedFromId"] == id
    assert child["historyMode"] == "paginated"
    assert child["ephemeral"] == false
    assert child["status"] == %{"type" => "idle"}
    assert child["turns"] == []
    assert forked["model"] == @model_a
    assert forked["modelProvider"] == "fixture"
    assert forked["cwd"] == ctx.fixture.workspace
    assert is_binary(child["path"]) and Path.type(child["path"]) == :absolute

    assert String.starts_with?(
             Path.expand(child["path"]),
             Path.expand(ctx.fixture.codex_home) <> "/"
           )

    assert File.regular?(child["path"])
    assert Enum.sort(call(pid, "thread/loaded/list", %{})["data"]) == Enum.sort([id, child_id])
    events = await_active_fork_started(pid, child, events, deadline())
    assert_pending(ctx, pid, id, turn, tool)
    assert_empty_active_fork(pid, child_id, turn)
    assert_pending(ctx, pid, id, turn, tool)
    assert ModelFixture.requests(ctx.fixture) === [first]
    assert Session.interaction_outcomes(pid) == []

    assert [%{"id" => ^turn, "status" => "inProgress", "items" => pending_items}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    expected_waiting = %{
      "type" => "dynamicToolCall",
      "id" => "fixture-call-1",
      "namespace" => nil,
      "tool" => "fixture_lookup",
      "arguments" => %{"key" => "synthetic"},
      "status" => "inProgress",
      "contentItems" => nil,
      "success" => nil,
      "durationMs" => nil
    }

    # ItemStarted is transient in the pin; assert its full live payload instead
    # of inventing an in-progress paginated-history row.
    events = drain(pid, events)

    assert [started] =
             for(
               event <- events,
               event.wire["method"] == "item/started",
               event.wire["params"]["item"]["type"] == "dynamicToolCall",
               do: event.wire["params"]
             )

    started_at_ms = Map.fetch!(started, "startedAtMs")
    assert is_integer(started_at_ms) and started_at_ms > 0
    assert started_at_ms <= System.system_time(:millisecond)

    assert started === %{
             "threadId" => id,
             "turnId" => turn,
             "item" => expected_waiting,
             "startedAtMs" => started_at_ms
           }

    refute Enum.any?(events, fn event ->
             event.wire["method"] == "item/completed" and
               event.wire["params"]["item"]["type"] == "dynamicToolCall"
           end)

    assert [user_completed] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "userMessage",
               do: event.wire["params"]
             )

    assert user_completed["threadId"] == id and user_completed["turnId"] == turn
    user_id = Map.fetch!(user_completed["item"], "id")

    assert Regex.match?(
             ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
             user_id
           )

    expected_user = %{
      "type" => "userMessage",
      "id" => user_id,
      "clientId" => nil,
      "content" => [
        %{
          "type" => "text",
          "text" => "Initial synthetic future-settings input",
          "text_elements" => []
        }
      ]
    }

    assert user_completed["item"] === expected_user
    # Canonical ItemCompleted(userMessage) is durable already. The pending
    # dynamic start and raw function_call do not project into paginated items.
    assert pending_items === [expected_user]

    assert call(pid, "thread/items/read", %{
             "threadId" => id,
             "turnId" => turn,
             "itemIds" => ["fixture-call-1"]
           }) === %{"data" => []}

    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))
    refute notification(events, "turn/completed")
    assert_pending(ctx, pid, id, turn, tool)
    assert File.ls!(ctx.fixture.workspace) == ["owned-active-fork-canary.txt"]
    assert File.read!(sentinel) === canary

    # Explicitly decline this exact still-pending original callback. No lookup
    # implementation or child turn runs, and no approval receives an answer.
    declined = "Owned lookup declined after active-boundary fork; no action performed"

    assert :ok =
             Session.respond(pid, tool.handle, {
               :ok,
               %{
                 "success" => false,
                 "contentItems" => [%{"type" => "inputText", "text" => declined}]
               }
             })

    events = events ++ finish_turn(pid, id, turn)
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))

    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == id and params["turn"]["id"] == turn
    end

    assert [completed] =
             for(
               event <- events,
               event.wire["method"] == "item/completed",
               event.wire["params"]["item"]["type"] == "dynamicToolCall",
               do: event.wire["params"]
             )

    assert completed["threadId"] == id and completed["turnId"] == turn
    duration = completed["item"]["durationMs"]
    assert is_integer(duration) and duration >= 0

    expected_declined =
      Map.merge(expected_waiting, %{
        "status" => "failed",
        "contentItems" => [%{"type" => "inputText", "text" => declined}],
        "success" => false,
        "durationMs" => duration
      })

    assert completed["item"] === expected_declined
    assert [^first, continued] = requests = ModelFixture.requests(ctx.fixture)
    assert_initial(continued)
    assert environment_texts(continued) === environment_texts(first)
    assert [call] = Enum.filter(continued["input"], &(&1["type"] == "function_call"))
    assert call["call_id"] == "fixture-call-1" and call["name"] == "fixture_lookup"
    assert JSON.decode!(call["arguments"]) === %{"key" => "synthetic"}
    assert [output] = Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "fixture-call-1" and output["output"] === declined

    assert [%{"id" => ^turn, "status" => "completed", "items" => items}] =
             call(pid, "thread/read", %{"threadId" => id, "includeTurns" => true})["thread"][
               "turns"
             ]

    assert Enum.map(items, & &1["type"]) == ["userMessage", "dynamicToolCall", "agentMessage"]
    assert hd(items) === expected_user
    assert Enum.find(items, &(&1["type"] == "dynamicToolCall")) === expected_declined
    assert List.last(items)["text"] == "Deterministic local fixture answer"
    assert_empty_active_fork(pid, child_id, turn)
    assert ModelFixture.requests(ctx.fixture) === requests
    events = drain(pid, events)

    # The child may emit thread/started and status metadata, but no child
    # turn/item lifecycle or callback is permitted by these history-only calls.
    assert [^tool] = Enum.filter(events, &(&1.kind == :server_request))

    for event <- events,
        method = event.wire["method"] || "",
        String.starts_with?(method, "turn/") or String.starts_with?(method, "item/") do
      assert event.wire["params"]["threadId"] == id
    end

    assert [outcome] = Session.interaction_outcomes(pid)
    assert outcome.handle === tool.handle and outcome.thread_id == id
    assert outcome.method == "item/tool/call"
    assert outcome.status in [:sent_unconfirmed, :resolution_observed]
    # Matching native failed item plus provider output is the evidence before
    # acknowledging this local delivery record; a transport send alone is not.
    assert :ok = Session.acknowledge_interaction_outcome(pid, tool.handle)
    assert Session.interaction_outcomes(pid) == []
    assert Session.uncertain_operations(pid) == []
    assert_idle(pid)
    assert File.ls!(ctx.fixture.workspace) == ["owned-active-fork-canary.txt"]
    assert File.read!(sentinel) === canary
    %{connection: connection} = :sys.get_state(pid)
    monitor = Process.monitor(pid)
    assert :ok = StdioSessionFixture.close(pid, connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 5_000
    assert ModelFixture.requests(ctx.fixture) === requests
    assert File.read!(sentinel) === canary
  end

  defp await_active_fork_started(pid, child, events, until) do
    events = drain(pid, events)
    assert [tool] = Enum.filter(events, &(&1.kind == :server_request))
    assert tool.wire["params"]["threadId"] == child["forkedFromId"]
    refute notification(events, "turn/completed")

    matches =
      Enum.filter(events, fn event ->
        event.wire["method"] == "thread/started" and
          event.wire["params"]["thread"]["id"] == child["id"]
      end)

    case matches do
      [event] ->
        assert event.wire["params"] === %{"thread" => child}
        events

      [] ->
        wait(pid, until, fn -> await_active_fork_started(pid, child, events, until) end)

      _ ->
        flunk("Duplicate native active-boundary fork notification")
    end
  end

  defp assert_empty_active_fork(pid, child, excluded_turn) do
    thread = call(pid, "thread/read", %{"threadId" => child, "includeTurns" => true})["thread"]
    assert thread["id"] == child and thread["historyMode"] == "paginated"
    assert thread["status"] == %{"type" => "idle"}
    assert thread["turns"] == []
    empty = %{"data" => [], "nextCursor" => nil, "backwardsCursor" => nil}

    assert call(pid, "thread/turns/list", %{"threadId" => child, "itemsView" => "full"}) === empty
    assert call(pid, "thread/items/list", %{"threadId" => child}) === empty

    assert call(pid, "thread/items/read", %{
             "threadId" => child,
             "turnId" => excluded_turn,
             "itemIds" => ["fixture-call-1"]
           }) === %{"data" => []}
  end

  defp idle_thread(ctx) do
    pid = start(ctx)
    id = thread(ctx, pid, %{"model" => @model_a})
    assert_idle(pid)
    assert ModelFixture.requests(ctx.fixture) == []
    {pid, id}
  end

  defp idle_update(ctx, pid, id, overrides, expected) do
    assert Map.has_key?(expected, "summary")
    assert call(pid, "thread/settings/update", Map.put(overrides, "threadId", id)) == %{}
    # ACK only queues the update. Match the applied marker before another edit.
    idle_snapshot(ctx, pid, id, expected, [], deadline())
  end

  defp idle_snapshot(ctx, pid, id, expected, events, until) do
    events = drain(pid, events)
    assert_no_idle_effects(ctx, pid, events)

    matching =
      Enum.filter(events, fn event ->
        event.wire["method"] == "thread/settings/updated" and
          event.wire["params"]["threadId"] == id and
          event.wire["params"]["threadSettings"]["summary"] == expected["summary"]
      end)

    case matching do
      [event] ->
        settings = event.wire["params"]["threadSettings"]
        for {key, value} <- expected, do: assert(Map.fetch!(settings, key) == value)
        assert settings["modelProvider"] == "fixture"
        assert settings["cwd"] == ctx.fixture.workspace
        settings

      [] ->
        wait(pid, until, fn -> idle_snapshot(ctx, pid, id, expected, events, until) end)

      _ ->
        flunk("Duplicate applied idle settings snapshot")
    end
  end

  defp idle_preserved(ctx, pid, id, previous) do
    marker = if previous["summary"] == "concise", do: "detailed", else: "concise"
    current = idle_update(ctx, pid, id, %{"summary" => marker}, %{"summary" => marker})
    assert Map.delete(current, "summary") == Map.delete(previous, "summary")
    current
  end

  defp assert_no_idle_effects(ctx, pid, events) do
    assert ModelFixture.requests(ctx.fixture) == []
    assert_idle(pid)

    refute Enum.any?(events, fn event ->
             method = event.wire["method"] || ""

             event.kind == :server_request or String.starts_with?(method, "turn/") or
               String.starts_with?(method, "item/")
           end)
  end

  defp finish_idle(ctx, pid) do
    assert_no_idle_effects(ctx, pid, drain(pid, []))
    # Explicit shutdown plus the existing owner-scoped on_exit cleanup.
    assert :ok = Session.close(pid)
  end

  defp active(ctx, extra \\ %{}) do
    pid = start(ctx)
    id = thread(ctx, pid, Map.merge(%{"model" => @model_a, "dynamicTools" => [@lookup]}, extra))
    turn = start_turn(pid, id, text("Initial synthetic future-settings input"))
    {tool, events} = await_tool(pid, [], deadline())
    assert_pending(ctx, pid, id, turn, tool)
    assert [first] = ModelFixture.requests(ctx.fixture)
    assert_initial(first)
    {pid, id, turn, tool, events}
  end

  defp await_tool(pid, events, until) do
    events = drain(pid, events)
    refute notification(events, "turn/completed")

    case Enum.filter(events, &(&1.kind == :server_request)) do
      [tool] -> {tool, events}
      [] -> wait(pid, until, fn -> await_tool(pid, events, until) end)
      _ -> flunk("Unexpected additional native interaction")
    end
  end

  defp await_settings(pid, id, cwd, events, until) do
    events = drain(pid, events)
    refute notification(events, "turn/completed")

    matching =
      Enum.filter(events, fn event ->
        event.wire["method"] == "thread/settings/updated" and
          event.wire["params"]["threadId"] == id and
          event.wire["params"]["threadSettings"]["model"] == @model_b
      end)

    case matching do
      [event] ->
        settings = event.wire["params"]["threadSettings"]
        assert settings["modelProvider"] == "fixture"
        assert settings["effort"] == "high"
        assert settings["summary"] == "detailed"
        assert settings["cwd"] == cwd
        events

      [] ->
        wait(pid, until, fn -> await_settings(pid, id, cwd, events, until) end)

      _ ->
        flunk("Unexpected duplicate applied settings snapshot")
    end
  end

  defp drain(pid, events) do
    assert {:ok, incoming} = Session.drain(pid)
    events ++ incoming
  end

  defp wait(pid, until, next) do
    remaining = max(until - System.monotonic_time(:millisecond), 0)

    receive do
      {:codex_driver, ^pid, :events_available} ->
        next.()

      {:codex_driver, ^pid, {:gap, _}} ->
        flunk("Unexpected event gap awaiting native settings evidence")
    after
      remaining -> flunk("Native settings evidence deadline")
    end
  end

  defp assert_pending(ctx, pid, id, turn, tool) do
    assert [_] = ModelFixture.requests(ctx.fixture)
    assert %{phase: :ready, interactions: 1, pending: 0, uncertain: 0} = Session.status(pid)
    assert tool.kind == :server_request
    assert tool.wire["method"] == "item/tool/call"
    assert is_integer(tool.wire["id"]) or is_binary(tool.wire["id"])
    assert tool.handle.id == tool.wire["id"]
    assert tool.handle.generation == Session.status(pid).generation
    assert is_reference(tool.handle.reference)

    assert tool.wire["params"] == %{
             "threadId" => id,
             "turnId" => turn,
             "callId" => "fixture-call-1",
             "namespace" => nil,
             "tool" => "fixture_lookup",
             "arguments" => %{"key" => "synthetic"}
           }
  end

  defp finish_active(ctx, pid, id, turn, tool, events) do
    assert_pending(ctx, pid, id, turn, tool)

    assert :ok =
             Session.respond(
               pid,
               tool.handle,
               {:ok,
                %{
                  "contentItems" => [
                    %{"type" => "inputText", "text" => "Synthetic lookup completed"}
                  ],
                  "success" => true
                }}
             )

    events = events ++ finish_turn(pid, id, turn)

    for method <- ["turn/started", "turn/completed"] do
      assert [params] =
               for(event <- events, event.wire["method"] == method, do: event.wire["params"])

      assert params["threadId"] == id
      assert params["turn"]["id"] == turn
    end

    assert [_, continued] = ModelFixture.requests(ctx.fixture)
    assert [output] = Enum.filter(continued["input"], &(&1["type"] == "function_call_output"))
    assert output["call_id"] == "fixture-call-1"
    assert output["output"] == "Synthetic lookup completed"
    assert_idle(pid)
  end

  defp environment_texts(request) do
    for item <- request["input"],
        item["role"] == "user",
        content <- Map.get(item, "content", []),
        value = content["text"],
        is_binary(value),
        String.starts_with?(value, "<environment_context>"),
        do: value
  end

  defp assert_environment(value, cwd) do
    assert is_binary(value)
    assert value =~ "<cwd>#{cwd}</cwd>"
    assert value =~ "<workspace_roots><root>#{cwd}</root></workspace_roots>"
  end

  defp assert_initial(request) do
    assert request["model"] == @model_a
    assert request["reasoning"] == %{"effort" => "low", "summary" => "concise"}
    refute Map.has_key?(request, "service_tier")
  end

  defp assert_idle(pid),
    do: assert(%{phase: :ready, interactions: 0, pending: 0, uncertain: 0} = Session.status(pid))

  defp deadline, do: System.monotonic_time(:millisecond) + 10_000
  defp text(value), do: [%{"type" => "text", "text" => value}]

  defp start(ctx) do
    f = ctx.fixture

    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: Path.expand(ctx.binary),
             args:
               SamgitaCodexDriver.NativeLaunchFixture.ordinary_args([
                 "app-server",
                 "--listen",
                 "stdio://"
               ]),
             cwd: f.workspace,
             inherit_env: [],
             env: %{
               "HOME" => f.home,
               "CODEX_HOME" => f.codex_home,
               "TMPDIR" => Path.join(ctx.root, "tmp"),
               "PATH" => f.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
               "SHELL" => Path.join(f.bin, "sh"),
               "CODEX_DISABLE_REMOTE_CONTROL" => "1",
               "NO_COLOR" => "1",
               "RUST_LOG" => "off"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)

    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(
               pid,
               %{"name" => "samgita_future_settings", "version" => "0.1.0"},
               %{"experimentalApi" => true}
             )

    pid
  end
end
