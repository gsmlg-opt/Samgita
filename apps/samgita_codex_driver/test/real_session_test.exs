defmodule SamgitaCodexDriver.RealSessionTest do
  use ExUnit.Case, async: false
  alias SamgitaCodexDriver.{ModelFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.{Stdio, WebSocket}
  alias SamgitaProtocolCodex.Error
  @moduletag :real_codex
  @moduletag timeout: 60_000
  @pixel "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC"

  setup do
    binary = System.get_env("CODEX_BINARY")

    assert is_binary(binary) and File.regular?(binary),
           "BLOCKED_ENV: CODEX_BINARY must point to the immutable pinned Codex executable"

    root =
      Path.join(System.tmp_dir!(), "samgita-codex-session-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{binary: binary, root: root}
  end

  defp fixture(root, scenario) do
    fixture = ModelFixture.start(root, scenario)
    on_exit(fn -> ModelFixture.close(fixture) end)
    fixture
  end

  defp process_opts(binary, fixture, listen \\ "stdio://") do
    [
      executable: binary,
      args: ["app-server", "--listen", listen],
      cwd: fixture.workspace,
      env: %{
        "HOME" => fixture.home,
        "CODEX_HOME" => fixture.codex_home,
        "PATH" => fixture.bin <> ":" <> System.get_env("PATH", "/usr/bin:/bin"),
        "NO_COLOR" => "1",
        "RUST_LOG" => "off"
      }
    ]
  end

  defp session(binary, fixture, experimental \\ false) do
    {:ok, pid} = Session.start_link(transport: {Stdio, process_opts(binary, fixture)})
    StdioSessionFixture.register_cleanup(pid)
    initialize(pid, experimental)
    pid
  end

  defp close_session(pid) do
    if Process.alive?(pid), do: Session.close(pid)
  catch
    :exit, _ -> :ok
  end

  defp initialize(pid, experimental) do
    assert {:ok, %{"result" => %{"platformOs" => "linux"}}} =
             Session.initialize(pid, %{"name" => "samgita_real_session", "version" => "0.1.0"}, %{
               "experimentalApi" => experimental
             })
  end

  defp start_thread(pid, fixture, extra \\ %{}) do
    params =
      Map.merge(
        %{
          "model" => "mock-model",
          "modelProvider" => "fixture",
          "cwd" => fixture.workspace,
          "sandbox" => "read-only",
          "approvalPolicy" => "on-request",
          "ephemeral" => true,
          "config" => %{"web_search" => "disabled"}
        },
        extra
      )

    assert {:ok, %{"result" => result}} = Session.request(pid, "thread/start", params)
    assert result["cwd"] == fixture.workspace
    assert result["modelProvider"] == "fixture"
    result["thread"]["id"]
  end

  defp start_turn(pid, thread, extra \\ %{}) do
    params =
      Map.merge(
        %{
          "threadId" => thread,
          "input" => [
            %{"type" => "text", "text" => "Synthetic local fixture input", "text_elements" => []}
          ]
        },
        extra
      )

    assert {:ok, %{"result" => %{"turn" => turn}}} = Session.request(pid, "turn/start", params)
    turn["id"]
  end

  defp turn_events(
         pid,
         turn,
         interaction \\ fn event -> flunk("Unexpected interaction #{event.wire["method"]}") end
       ) do
    collect(
      pid,
      fn events ->
        Enum.any?(
          events,
          &(get_in(&1, [:wire, "method"]) == "turn/completed" and
              get_in(&1, [:wire, "params", "turn", "id"]) == turn)
        )
      end,
      interaction,
      [],
      System.monotonic_time(:millisecond) + 25_000
    )
  end

  defp collect(pid, predicate, interaction, acc, deadline) do
    assert {:ok, events} = Session.drain(pid)

    Enum.each(events, fn
      %{kind: :server_request} = event -> interaction.(event)
      _ -> :ok
    end)

    acc = acc ++ events

    cond do
      predicate.(acc) ->
        acc

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("Real Session event deadline; status #{inspect(Session.status(pid))}")

      Session.status(pid).phase == :disconnected ->
        flunk("Real Session disconnected: #{inspect(Session.status(pid))}")

      true ->
        receive do
          {:codex_driver, ^pid, :events_available} ->
            :ok

          {:codex_driver, ^pid, {:gap, gap}} ->
            flunk("Unexpected real Session gap #{inspect(gap)}")
        after
          20 -> :ok
        end

        collect(pid, predicate, interaction, acc, deadline)
    end
  end

  defp methods(events), do: Enum.map(events, &get_in(&1, [:wire, "method"]))

  defp completed(events),
    do:
      Enum.find(events, &(get_in(&1, [:wire, "method"]) == "turn/completed")).wire["params"][
        "turn"
      ]

  test "stable and experimental Sessions drive real full configured text lifecycle", %{
    binary: binary,
    root: root
  } do
    for experimental <- [false, true] do
      fixture = fixture(Path.join(root, to_string(experimental)), "assistant")
      pid = session(binary, fixture, experimental)
      thread = start_thread(pid, fixture)
      turn = start_turn(pid, thread)
      events = turn_events(pid, turn)
      assert completed(events)["status"] == "completed"
      assert "item/started" in methods(events)
      assert "item/completed" in methods(events)
      assert "turn/started" in methods(events)

      item =
        events
        |> Enum.filter(&(get_in(&1, [:wire, "method"]) == "item/completed"))
        |> Enum.map(&get_in(&1, [:wire, "params", "item"]))
        |> Enum.find(&(&1["type"] == "agentMessage"))

      assert item["text"] == "Deterministic local fixture answer"
      assert item["id"] != ""
      assert length(ModelFixture.requests(fixture)) == 1
      assert %{pending: 0, interactions: 0, phase: :ready} = Session.status(pid)
      close_session(pid)
    end
  end

  test "native structured server errors retain the full wire without logging it", %{
    binary: binary,
    root: root
  } do
    fixture = fixture(root, "assistant")
    pid = session(binary, fixture)

    assert {:error, %Error{code: :upstream_error, wire: wire} = failure} =
             Session.request(pid, "thread/read", %{"threadId" => 42},
               validation: :wire,
               effect: :read
             )

    assert is_integer(wire["error"]["code"])
    assert is_binary(wire["error"]["message"])
    assert Map.has_key?(wire, "id")
    refute inspect(failure) =~ wire["error"]["message"]
    assert Session.status(pid).phase == :ready
  end

  test "real image input reaches the local provider with native modality intact", %{
    binary: binary,
    root: root
  } do
    fixture = fixture(root, "assistant")
    pid = session(binary, fixture)
    thread = start_thread(pid, fixture)

    turn =
      start_turn(pid, thread, %{
        "input" => [
          %{"type" => "text", "text" => "Describe synthetic pixel"},
          %{"type" => "image", "url" => @pixel, "detail" => "auto"}
        ]
      })

    events = turn_events(pid, turn)
    assert completed(events)["status"] == "completed"
    request = hd(ModelFixture.requests(fixture))

    image =
      request["input"]
      |> Enum.flat_map(&Map.get(&1, "content", []))
      |> Enum.find(&(&1["type"] == "input_image"))

    assert image["image_url"] == @pixel
  end

  test "real command approvals decline, cancel or explicitly allow only the exact fixture action",
       %{binary: binary, root: root} do
    for decision <- ["decline", "cancel", "accept"] do
      fixture = fixture(Path.join(root, decision), "command")
      expected_command = Path.join(fixture.bin, "sh") <> " -c 'printf samgita_fixture'"
      pid = session(binary, fixture, true)
      thread = start_thread(pid, fixture)
      turn = start_turn(pid, thread)

      events =
        turn_events(pid, turn, fn event ->
          assert event.wire["method"] == "item/commandExecution/requestApproval"
          params = event.wire["params"]
          assert params["threadId"] == thread
          assert params["turnId"] == turn
          assert params["cwd"] == fixture.workspace

          assert params["command"] == expected_command

          assert :ok = Session.respond(pid, event.handle, {:ok, %{"decision" => decision}})
        end)

      approval = Enum.find(events, &(&1.kind == :server_request))
      assert approval

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(pid, approval.handle, {:ok, %{"decision" => "accept"}})

      assert completed(events)["status"] ==
               if(decision == "cancel", do: "interrupted", else: "completed")

      commands =
        events
        |> Enum.filter(&(get_in(&1, [:wire, "method"]) == "item/completed"))
        |> Enum.map(&get_in(&1, [:wire, "params", "item"]))
        |> Enum.filter(&(&1["type"] == "commandExecution"))

      assert length(commands) == 1
      command = hd(commands)

      if decision == "accept" do
        assert command["exitCode"] == 0
        assert command["aggregatedOutput"] =~ "samgita_fixture"
      else
        refute command["aggregatedOutput"] == "samgita_fixture"
      end

      close_session(pid)
    end
  end

  test "real dynamic tool request and full structured content reply complete the item", %{
    binary: binary,
    root: root
  } do
    fixture = fixture(root, "dynamic_tool")
    pid = session(binary, fixture, true)

    tool = %{
      "type" => "function",
      "name" => "fixture_lookup",
      "description" => "Synthetic lookup only",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{"key" => %{"type" => "string"}},
        "required" => ["key"],
        "additionalProperties" => false
      }
    }

    thread = start_thread(pid, fixture, %{"dynamicTools" => [tool]})
    turn = start_turn(pid, thread)

    content = [
      %{
        "type" => "inputText",
        "text" =>
          JSON.encode!(%{
            "found" => true,
            "nested" => %{"value" => nil},
            "values" => [1, "synthetic"]
          })
      },
      %{"type" => "inputImage", "imageUrl" => @pixel}
    ]

    events =
      turn_events(pid, turn, fn event ->
        assert event.wire["method"] == "item/tool/call"

        assert %{
                 "threadId" => ^thread,
                 "turnId" => ^turn,
                 "callId" => "fixture-call-1",
                 "tool" => "fixture_lookup",
                 "arguments" => %{"key" => "synthetic"}
               } = event.wire["params"]

        assert :ok =
                 Session.respond(
                   pid,
                   event.handle,
                   {:ok, %{"contentItems" => content, "success" => true}}
                 )
      end)

    assert completed(events)["status"] == "completed"

    item =
      events
      |> Enum.filter(&(get_in(&1, [:wire, "method"]) == "item/completed"))
      |> Enum.map(&get_in(&1, [:wire, "params", "item"]))
      |> Enum.find(&(&1["type"] == "dynamicToolCall"))

    assert item["contentItems"] == content
    assert item["success"] == true
    assert length(ModelFixture.requests(fixture)) == 2
    assert JSON.encode!(ModelFixture.requests(fixture)) =~ "function_call_output"
  end

  test "real plan-mode user input request receives exact answers and resolves", %{
    binary: binary,
    root: root
  } do
    fixture = fixture(root, "user_input")
    pid = session(binary, fixture, true)
    thread = start_thread(pid, fixture)

    mode = %{
      "mode" => "plan",
      "settings" => %{
        "model" => "mock-model",
        "reasoning_effort" => "medium",
        "developer_instructions" => nil
      }
    }

    turn = start_turn(pid, thread, %{"collaborationMode" => mode})

    events =
      turn_events(pid, turn, fn event ->
        assert event.wire["method"] == "item/tool/requestUserInput"

        assert %{
                 "questions" => [%{"id" => "fixture", "question" => "Choose fixture input"}],
                 "isBlocking" => true
               } = event.wire["params"]

        assert :ok =
                 Session.respond(
                   pid,
                   event.handle,
                   {:ok, %{"answers" => %{"fixture" => %{"answers" => ["One"]}}}}
                 )
      end)

    assert completed(events)["status"] == "completed"
    assert "serverRequest/resolved" in methods(events)
    assert Session.status(pid).interactions == 0
    assert length(ModelFixture.requests(fixture)) == 2
    assert JSON.encode!(ModelFixture.requests(fixture)) =~ "One"
  end

  test "real borrowed WebSocket reconnect reinitializes and explicitly resumes without duplicate execution",
       %{binary: binary, root: root} do
    fixture = fixture(root, "assistant")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_, port}} = :inet.sockname(listener)
    :gen_tcp.close(listener)
    {:ok, owner} = Stdio.open(process_opts(binary, fixture, "ws://127.0.0.1:#{port}"))
    on_exit(fn -> Stdio.close(owner) end)
    wait_listener(port)

    {:ok, pid} =
      Session.start_link(transport: {WebSocket, [url: "ws://127.0.0.1:#{port}/app-server"]})

    on_exit(fn -> close_session(pid) end)
    initialize(pid, false)
    thread = start_thread(pid, fixture, %{"ephemeral" => false})
    turn = start_turn(pid, thread)
    assert completed(turn_events(pid, turn))["status"] == "completed"
    assert length(ModelFixture.requests(fixture)) == 1
    assert :ok = Session.reconnect(pid)
    assert Session.status(pid).phase == :new
    assert Session.status(pid).generation == 2
    assert Session.status(pid).gap.reason == :explicit_reconnect
    assert {:error, %Error{code: :not_initialized}} = Session.request(pid, "thread/list")
    initialize(pid, false)

    assert {:ok, %{"result" => %{"thread" => %{"id" => ^thread}}}} =
             Session.request(pid, "thread/resume", %{"threadId" => thread})

    assert length(ModelFixture.requests(fixture)) == 1

    assert {:ok, %{"result" => %{"thread" => %{"turns" => turns}}}} =
             Session.request(pid, "thread/read", %{"threadId" => thread, "includeTurns" => true},
               effect: :read
             )

    assert Enum.count(turns, &(&1["id"] == turn)) == 1
    assert Session.status(pid).pending == 0
  end

  defp wait_listener(port, tries \\ 200)
  defp wait_listener(_port, 0), do: flunk("real Codex WebSocket listener deadline")

  defp wait_listener(port, tries) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 50) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      _ ->
        Process.sleep(25)
        wait_listener(port, tries - 1)
    end
  end
end
