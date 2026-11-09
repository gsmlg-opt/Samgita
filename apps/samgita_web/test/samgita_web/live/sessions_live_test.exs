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
          "turn/interrupt" => %{}
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

  test "a new session starts in the project folder and streams Codex's reply", %{
    conn: conn,
    server: server,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/new?cwd=/work/app")
    assert has_element?(view, "#session-title", "app")

    view |> form("#session-composer", %{"message" => "Fix the build"}) |> render_submit()

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
    assert has_element?(view, "#session-running")

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

    await(fn -> has_element?(view, "#item-a2", "Working on it.") end)

    notify(server, "turn/completed", %{
      "threadId" => @thread_id,
      "turn" => %{"id" => @turn_id, "items" => [], "status" => "completed"}
    })

    await(fn -> not has_element?(view, "#session-running") end)
  end

  test "an existing session shows its history and answers an approval request", %{
    conn: conn,
    server: server,
    host: host
  } do
    {:ok, view, _} = live(conn, ~p"/sessions/#{host["id"]}/#{@thread_id}")
    assert_receive {:fake_codex, :params, "thread/resume", %{"threadId" => @thread_id}}, 3_000
    await(fn -> has_element?(view, "#item-a1", "The build is fixed.") end)
    assert has_element?(view, "#item-u1", "Fix the build")

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

    await(fn -> has_element?(view, "[id^=request-]", "mix deps.get") end)
    view |> element("[id^=request-] [phx-value-decision=acceptForSession]") |> render_click()

    assert_receive {:fake_codex, :response, 900, %{"decision" => "acceptForSession"}}, 3_000
    refute has_element?(view, "[id^=request-]")
  end
end
