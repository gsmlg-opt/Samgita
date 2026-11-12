defmodule SamgitaWeb.SessionsLiveTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  alias Samgita.{CodexHosts, FakeCodexServer, Principal, Repo}
  alias Samgita.Domain.CodexHost

  @thread_id "01a1c18b-2abb-7932-a6bd-c8c4a523143f"
  @turn_id "01a1c18b-0000-7000-8000-000000000001"

  defp thread(turns),
    do: %{
      "id" => @thread_id,
      "name" => nil,
      "preview" => "Fix the build",
      "cwd" => "/work/app",
      "createdAt" => 1_794_119_000,
      "updatedAt" => 1_794_119_417,
      "status" => %{"type" => "idle"},
      "cliVersion" => "0.167.0",
      "ephemeral" => false,
      "modelProvider" => "openai",
      "projectId" => nil,
      "sessionId" => @thread_id,
      "source" => "appServer",
      "turns" => turns
    }

  defp model(id, default?, efforts),
    do: %{
      "id" => id,
      "model" => id,
      "displayName" => String.upcase(id),
      "description" => "",
      "hidden" => false,
      "isDefault" => default?,
      "defaultReasoningEffort" => hd(efforts),
      "supportedReasoningEfforts" =>
        for(e <- efforts, do: %{"reasoningEffort" => e, "description" => ""})
    }

  defp thread_result(turns),
    do: %{
      "thread" => thread(turns),
      "approvalPolicy" => "on-request",
      "approvalsReviewer" => "user",
      "cwd" => "/work/app",
      "model" => "gpt-test",
      "modelProvider" => "openai",
      "sandbox" => %{"type" => "readOnly"}
    }

  @history [
    %{
      "id" => "01a1c18b-0000-7000-8000-000000000000",
      "status" => "completed",
      "items" => [
        %{
          "type" => "userMessage",
          "id" => "u1",
          "content" => [%{"type" => "text", "text" => "Fix the build"}]
        },
        %{"type" => "agentMessage", "id" => "a1", "text" => "The build is fixed."}
      ]
    }
  ]

  setup do
    server =
      FakeCodexServer.start(
        results: %{
          "thread/start" => thread_result([]),
          "thread/resume" => thread_result(@history),
          "turn/start" => %{
            "turn" => %{"id" => @turn_id, "items" => [], "status" => "inProgress"}
          },
          "turn/steer" => %{"turnId" => @turn_id},
          "model/list" => %{
            "data" => [
              model("gpt-test", true, ["low", "high"]),
              model("gpt-mini", false, ["low"])
            ]
          },
          "turn/interrupt" => %{},
          "plugin/installed" => %{
            "marketplaces" => [
              %{
                "name" => "local",
                "path" => "/home/u/.agents/plugins/marketplace.json",
                "plugins" => [
                  %{
                    "id" => "docs@local",
                    "name" => "docs",
                    "enabled" => true,
                    "installed" => true,
                    "authPolicy" => "ON_USE",
                    "installPolicy" => "AVAILABLE",
                    "source" => %{"type" => "local", "path" => "/home/u/plugins/docs"},
                    "interface" => nil
                  }
                ]
              }
            ]
          },
          "skills/list" => %{
            "data" => [
              %{
                "cwd" => "/work/app",
                "errors" => [],
                "skills" => [
                  %{
                    "name" => "review",
                    "description" => "Review a change",
                    "enabled" => true,
                    "path" => "/work/app/.agents/skills/review/SKILL.md",
                    "scope" => "repo"
                  }
                ]
              }
            ]
          },
          "fs/readDirectory" => %{
            "entries" => [
              %{"fileName" => "README.md", "isDirectory" => false, "isFile" => true},
              %{"fileName" => "lib", "isDirectory" => true, "isFile" => false}
            ]
          },
          "thread/goal/set" => %{
            "goal" => %{
              "threadId" => @thread_id,
              "objective" => "Ship the build",
              "status" => "active",
              "createdAt" => 1_794_119_000,
              "updatedAt" => 1_794_119_000,
              "timeUsedSeconds" => 0,
              "tokensUsed" => 0
            }
          },
          "thread/goal/clear" => %{"cleared" => true}
        }
      )

    previous = Application.get_env(:samgita, :codex_hosts)
    Application.put_env(:samgita, :codex_hosts, Keyword.put(previous, :enabled, true))

    on_exit(fn ->
      for {_, pid, _, _} <-
            DynamicSupervisor.which_children(Samgita.CodexHosts.ConnectionSupervisor),
          do: DynamicSupervisor.terminate_child(Samgita.CodexHosts.ConnectionSupervisor, pid)

      Application.put_env(:samgita, :codex_hosts, previous)
      FakeCodexServer.stop(server)
    end)

    agent = agent_fixture(%{"runtime_driver" => "codex", "runtime_version" => "0.167.0"})

    {:ok, host} =
      CodexHosts.configure(
        Principal.operator(),
        command(%{"agent_id" => agent["id"], "transport" => "websocket", "url" => server.url})
      )

    {:ok, _} =
      CodexHosts.enable(
        Principal.operator(),
        host["id"],
        command(%{"expected_version" => host["version"]})
      )

    await(fn -> Repo.get!(CodexHost, host["id"]).generation == 1 end)
    %{server: server, host: host}
  end

  defp await(fun, attempts \\ 60) do
    if fun.() do
      :ok
    else
      if attempts == 0, do: flunk("condition not reached")
      Process.sleep(50)
      await(fun, attempts - 1)
    end
  end

  defp notify(server, method, params),
    do: FakeCodexServer.push(server, %{"method" => method, "params" => params})

  # The React chat's request bridge: `chat.send` etc. with a reply.
  defp chat(view, event, payload) do
    render_hook(view, event, Map.merge(%{"id" => "session-chat"}, payload))
  end

  test "a new session starts in the project folder and streams Codex's reply", %{
    conn: conn,
    server: server,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/new?cwd=/work/app")
    assert has_element?(view, "#session-title", "app")
    assert has_element?(view, "#session-chat[phx-hook=SessionChat][phx-update=ignore]")

    chat(view, "chat.send", %{"text" => "Fix the build"})
    assert_reply(view, %{status: "ok"})

    assert_receive {:fake_codex, :params, "thread/start", start}, 3_000

    assert start == %{
             "cwd" => "/work/app",
             "approvalPolicy" => "on-request",
             "sandbox" => "workspace-write"
           }

    assert_receive {:fake_codex, :params, "turn/start", turn}, 3_000

    assert turn == %{
             "threadId" => @thread_id,
             "input" => [%{"type" => "text", "text" => "Fix the build"}]
           }

    assert_patch(view, ~p"/sessions/#{host["id"]}/#{@thread_id}")

    # The running turn shows Stop in the chat (runtime.active) and still admits
    # messages, which steer the turn.
    assert_push_event(view, "chat:event", %{
      type: "chat.snapshot",
      id: "session-chat",
      runtime: %{active: true},
      admission: %{allowWhileStreaming: true}
    })

    notify(server, "item/agentMessage/delta", %{
      "threadId" => @thread_id,
      "turnId" => @turn_id,
      "itemId" => "a2",
      "delta" => "Working "
    })

    notify(server, "item/agentMessage/delta", %{
      "threadId" => @thread_id,
      "turnId" => @turn_id,
      "itemId" => "a2",
      "delta" => "on it."
    })

    assert_push_event(view, "chat:event", %{
      type: "chat.message",
      message_id: "a2",
      sequence: 1,
      message: %{"role" => "assistant", "content" => "Working ", "status" => "streaming"}
    })

    assert_push_event(view, "chat:event", %{
      type: "chat.message",
      message_id: "a2",
      sequence: 2,
      message: %{"content" => "Working on it.", "status" => "streaming"}
    })

    # A message sent while Codex works joins the running turn.
    chat(view, "chat.send", %{"text" => "Also run the tests"})
    assert_reply(view, %{status: "ok"})
    assert_receive {:fake_codex, :params, "turn/steer", steer}, 3_000

    assert steer == %{
             "threadId" => @thread_id,
             "expectedTurnId" => @turn_id,
             "input" => [%{"type" => "text", "text" => "Also run the tests"}]
           }

    notify(server, "turn/completed", %{
      "threadId" => @thread_id,
      "turn" => %{"id" => @turn_id, "items" => [], "status" => "completed"}
    })

    assert_push_event(view, "chat:event", %{
      type: "chat.message",
      message_id: "a2",
      sequence: 3,
      message: %{"content" => "Working on it.", "status" => "complete"},
      runtime: %{active: false}
    })
  end

  test "Stop interrupts the running turn", %{conn: conn, host: host} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/new?cwd=/work/app")
    chat(view, "chat.send", %{"text" => "Fix the build"})
    assert_receive {:fake_codex, :params, "turn/start", _}, 3_000

    chat(view, "chat.stop", %{})
    assert_reply(view, %{status: "ok"})

    assert_receive {:fake_codex, :params, "turn/interrupt",
                    %{"threadId" => @thread_id, "turnId" => @turn_id}},
                   3_000
  end

  test "composer settings carry what the DuskMoon settings menus show", %{conn: conn, host: host} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "model/list", _}, 3_000

    assert_push_event(
      view,
      "chat:event",
      %{metadata: %{settings: [_, %{choices: [_ | _]} | _] = settings}},
      3_000
    )

    settings = Map.new(settings, &{&1.id, &1})
    full = Enum.find(settings["access"].choices, &(&1.value == "full"))
    assert %{tone: "warning", description: "Runs any command" <> _} = full
    assert Enum.all?(settings["access"].choices, &is_binary(&1.description))

    # Reasoning effort is an ordered slider whose reset goes to the model's default.
    assert %{ordered: true, defaultValue: "low", value: "low"} = settings["effort"]

    assert [%{value: "low", label: "Low"}, %{value: "high", label: "High"}] =
             settings["effort"].choices
  end

  test "composer choices are checked and apply to the next turn", %{conn: conn, host: host} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "thread/resume", _}, 3_000
    assert_receive {:fake_codex, :params, "model/list", _}, 3_000
    assert_push_event(view, "chat:event", %{type: "chat.snapshot"}, 3_000)

    # Only offered values are accepted.
    chat(view, "chat.setting", %{"settingId" => "model", "value" => "unknown-model"})
    assert_reply(view, %{status: "error"})

    # A model without the current effort falls back to its default effort.
    chat(view, "chat.setting", %{"settingId" => "model", "value" => "gpt-mini"})
    assert_reply(view, %{status: "ok", revision: 1, value: "gpt-mini"})

    chat(view, "chat.setting", %{"settingId" => "access", "value" => "full"})
    assert_reply(view, %{status: "ok", revision: 2})

    assert_push_event(view, "chat:event", %{
      type: "chat.snapshot",
      metadata: %{model: "gpt-mini", effort: "low", access: "full", pending: true}
    })

    chat(view, "chat.send", %{"text" => "Go"})
    assert_reply(view, %{status: "ok"})
    assert_receive {:fake_codex, :params, "turn/start", turn}, 3_000

    assert Map.take(turn, ~w(model effort sandboxPolicy approvalPolicy)) == %{
             "model" => "gpt-mini",
             "effort" => "low",
             "sandboxPolicy" => %{"type" => "dangerFullAccess"},
             "approvalPolicy" => "never"
           }

    # Codex keeps them for later turns; nothing is pending any more.
    assert_push_event(view, "chat:event", %{
      metadata: %{model: "gpt-mini", access: "full", pending: false}
    })
  end

  test "the Add menu attaches plugins and skills, sets plan mode and a goal, and lists files",
       %{conn: conn, host: host} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "thread/resume", _}, 3_000
    assert_receive {:fake_codex, :params, "skills/list", %{"cwds" => ["/work/app"]}}, 3_000
    # The catalog loads in the background after resume.
    assert_push_event(view, "chat:event", %{metadata: %{can_attach: true}}, 3_000)

    chat(view, "chat.catalog", %{})

    assert_reply(view, %{
      "status" => "ok",
      "plugins" => [%{"name" => "docs", "path" => "plugin://docs@local"}],
      "skills" => [%{"name" => "review", "path" => "/work/app/.agents/skills/review/SKILL.md"}]
    })

    chat(view, "chat.files", %{})

    assert_reply(view, %{
      status: "ok",
      path: "/work/app",
      parent: "/work",
      entries: [%{"name" => "lib", "dir" => true}, %{"name" => "README.md", "dir" => false}]
    })

    # Only attachments from the catalog are accepted.
    chat(view, "chat.send", %{
      "text" => "Go",
      "attachments" => [%{"type" => "skill", "path" => "/etc/SKILL.md"}]
    })

    assert_reply(view, %{status: "error"})

    chat(view, "chat.setting", %{"settingId" => "mode", "value" => "plan"})
    assert_reply(view, %{status: "ok"})

    chat(view, "chat.send", %{
      "text" => "Go",
      "attachments" => [
        %{"type" => "mention", "path" => "plugin://docs@local"},
        %{"type" => "skill", "path" => "/work/app/.agents/skills/review/SKILL.md"}
      ]
    })

    assert_reply(view, %{status: "ok"})
    assert_receive {:fake_codex, :params, "turn/start", turn}, 3_000

    assert turn["input"] == [
             %{"type" => "text", "text" => "Go"},
             %{"type" => "mention", "name" => "docs", "path" => "plugin://docs@local"},
             %{
               "type" => "skill",
               "name" => "review",
               "path" => "/work/app/.agents/skills/review/SKILL.md"
             }
           ]

    assert turn["collaborationMode"] == %{
             "mode" => "plan",
             "settings" => %{
               "model" => "gpt-test",
               "reasoning_effort" => "low",
               "developer_instructions" => nil
             }
           }

    chat(view, "chat.goal", %{"objective" => "Ship the build"})
    assert_reply(view, %{status: "ok"})

    assert_receive {:fake_codex, :params, "thread/goal/set",
                    %{
                      "threadId" => @thread_id,
                      "objective" => "Ship the build",
                      "origin" => "user"
                    }},
                   3_000

    assert_push_event(view, "chat:event", %{metadata: %{goal: %{"objective" => "Ship the build"}}})

    chat(view, "chat.goal_clear", %{})
    assert_reply(view, %{status: "ok"})
    assert_receive {:fake_codex, :params, "thread/goal/clear", %{"threadId" => @thread_id}}, 3_000
  end

  test "an existing session resumes with its history as chat messages", %{
    conn: conn,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "thread/resume", %{"threadId" => @thread_id}}, 3_000

    assert_push_event(
      view,
      "chat:event",
      %{
        type: "chat.snapshot",
        messages: [
          %{"id" => "u1", "role" => "user", "content" => "Fix the build"},
          %{"id" => "a1", "role" => "assistant", "content" => "The build is fixed."}
        ],
        sequences: %{"u1" => 1, "a1" => 1},
        runtime: %{active: false},
        # The composer's context: project, where Codex runs, model and access.
        metadata: %{
          project: "app",
          location: "Remote",
          connected: true,
          model: "gpt-test",
          access: "read_only",
          full_access: false,
          pending: false
        }
      },
      3_000
    )

    # After a reconnect the chat asks for the transcript again.
    chat(view, "chat.sync", %{"sequences" => %{}})
    assert_reply(view, %{status: "ok"})
    assert_push_event(view, "chat:event", %{type: "chat.snapshot"})
  end

  test "an existing session shows its history and answers an approval request", %{
    conn: conn,
    server: server,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "thread/resume", %{"threadId" => @thread_id}}, 3_000
    assert_push_event(view, "chat:event", %{type: "chat.snapshot"}, 3_000)

    FakeCodexServer.push(server, %{
      "id" => 900,
      "method" => "item/commandExecution/requestApproval",
      "params" => %{
        "threadId" => @thread_id,
        "turnId" => @turn_id,
        "itemId" => "c1",
        "startedAtMs" => 1_794_119_500_000,
        "command" => "mix deps.get",
        "reason" => "Needs network access"
      }
    })

    # The request is shown in the chat, in the last Codex reply.
    assert_push_event(
      view,
      "chat:event",
      %{
        type: "chat.message",
        message: %{
          "role" => "assistant",
          "requests" => [
            %{
              "key" => key,
              "command" => "mix deps.get",
              "reason" => "Needs network access",
              "answerable" => true
            }
          ]
        }
      },
      3_000
    )

    chat(view, "chat.decide", %{"key" => key, "decision" => "acceptForSession"})
    assert_reply(view, %{status: "ok"})
    assert_receive {:fake_codex, :response, 900, %{"decision" => "acceptForSession"}}, 3_000

    # Answered, it leaves the chat.
    assert_push_event(view, "chat:event", %{type: "chat.message", message: reply}, 3_000)
    refute Map.has_key?(reply, "requests")
  end
end
