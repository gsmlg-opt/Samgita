defmodule SamgitaCodexDriver.SessionToolRetirementTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  test "matching terminal dynamic item retires the unanswered handle without replying" do
    pid = ready()
    handle = interaction(pid, dynamic("request"))
    assert [_] = incoming(pid, completed_item())
    assert Session.status(pid).interactions == 0
    assert Session.interaction_outcomes(pid) == []
    assert {:error, %Error{code: :stale_interaction}} = Session.respond(pid, handle, result())
    refute_receive {:sent, ^pid, %{"id" => "request"}}
  end

  test "dynamic retirement requires matching thread, turn, item, type and terminal status" do
    pid = ready()
    handle = interaction(pid, dynamic("request"))

    for event <- [
          put_in(completed_item(), ["params", "threadId"], "other"),
          put_in(completed_item(), ["params", "turnId"], "other"),
          put_in(completed_item(), ["params", "item", "id"], "other"),
          put_in(completed_item(), ["params", "item", "status"], "inProgress"),
          %{
            "method" => "item/completed",
            "params" => %{
              "completedAtMs" => 1,
              "threadId" => "thread",
              "turnId" => "turn",
              "item" => %{
                "id" => "call",
                "type" => "agentMessage",
                "text" => "completed",
                "phase" => nil,
                "memoryCitation" => nil
              }
            }
          }
        ] do
      assert [_] = incoming(pid, event)
      assert Session.status(pid).phase == :ready
      assert Session.status(pid).interactions == 1
      assert Session.interaction_outcomes(pid) == []
    end

    assert :ok = Session.respond(pid, handle, result())
    assert_receive {:sent, ^pid, %{"id" => "request", "result" => _}}
  end

  test "terminal turn retires only matching unanswered dynamic requests" do
    for status <- ["completed", "interrupted", "failed"] do
      pid = ready()
      dynamic_handle = interaction(pid, dynamic("dynamic"))
      input_handle = interaction(pid, user_input("input"))

      for event <- [
            put_in(completed_turn(status), ["params", "threadId"], "other"),
            put_in(completed_turn(status), ["params", "turn", "id"], "other"),
            completed_turn("inProgress")
          ] do
        assert [_] = incoming(pid, event)
        assert Session.status(pid).interactions == 2
      end

      assert [_] = incoming(pid, completed_turn(status))
      assert Session.status(pid).interactions == 1

      assert {:error, %Error{code: :stale_interaction}} =
               Session.respond(pid, dynamic_handle, result())

      assert Session.interaction_outcomes(pid) == []
      assert :ok = Session.respond(pid, input_handle, {:ok, %{"answers" => %{}}})
      assert_receive {:sent, ^pid, %{"id" => "input", "result" => %{"answers" => %{}}}}
      refute_receive {:sent, ^pid, %{"id" => "dynamic"}}
    end
  end

  test "terminal evidence preserves sent_unconfirmed outcomes rather than fabricating ACKs" do
    pid = ready()
    handle = interaction(pid, dynamic("request"))
    assert :ok = Session.respond(pid, handle, result())
    assert_receive {:sent, ^pid, %{"id" => "request", "result" => _}}

    assert [%{handle: ^handle, status: :sent_unconfirmed} = before] =
             Session.interaction_outcomes(pid)

    assert [_] = incoming(pid, completed_item())
    assert [_] = incoming(pid, completed_turn("completed"))
    assert Session.interaction_outcomes(pid) == [before]
    assert Session.status(pid).interactions == 0
    refute_receive {:sent, ^pid, %{"id" => "request"}}
  end

  test "reconnect invalidates old handles and terminal events retire a fresh matching interaction" do
    pid = ready()
    old = interaction(pid, dynamic("reused-native-id"))
    assert :ok = Session.reconnect(pid)
    initialize(pid)
    fresh = interaction(pid, dynamic("reused-native-id"))
    assert fresh.generation == old.generation + 1
    assert {:error, %Error{code: :stale_interaction}} = Session.respond(pid, old, result())
    assert Session.status(pid).interactions == 1
    assert [_] = incoming(pid, completed_item())
    assert {:error, %Error{code: :stale_interaction}} = Session.respond(pid, fresh, result())
    assert Session.interaction_outcomes(pid) == []
    refute_receive {:sent, ^pid, %{"id" => "reused-native-id"}}
  end

  defp ready do
    {:ok, pid} = Session.start_link(transport: {ScriptedTransport, [observer: self()]})
    assert_receive {:transport_opened, ^pid}
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid, :normal) end)
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    task =
      Task.async(fn ->
        Session.initialize(pid, %{"name" => "retirement", "version" => "0.1.0"}, %{
          "experimentalApi" => true
        })
      end)

    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    send(
      pid,
      {:incoming,
       %{
         "id" => id,
         "result" => %{
           "userAgent" => "codex/0.163.0",
           "codexHome" => "/isolated",
           "platformFamily" => "unix",
           "platformOs" => "linux"
         }
       }}
    )

    assert {:ok, _} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
  end

  defp incoming(pid, event) do
    send(pid, {:incoming, event})
    assert {:ok, events} = Session.drain(pid)
    events
  end

  defp interaction(pid, wire) do
    assert [%{kind: :server_request, handle: handle}] = incoming(pid, wire)
    handle
  end

  defp dynamic(id),
    do: %{
      "id" => id,
      "method" => "item/tool/call",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "callId" => "call",
        "namespace" => nil,
        "tool" => "fixture",
        "arguments" => %{}
      }
    }

  defp user_input(id),
    do: %{
      "id" => id,
      "method" => "item/tool/requestUserInput",
      "params" => %{
        "threadId" => "thread",
        "turnId" => "turn",
        "itemId" => "question",
        "questions" => [],
        "isBlocking" => true,
        "autoResolutionMs" => nil
      }
    }

  defp completed_item,
    do: %{
      "method" => "item/completed",
      "params" => %{
        "completedAtMs" => 1,
        "threadId" => "thread",
        "turnId" => "turn",
        "item" => %{
          "id" => "call",
          "type" => "dynamicToolCall",
          "namespace" => nil,
          "tool" => "fixture",
          "arguments" => %{},
          "status" => "failed",
          "contentItems" => [],
          "success" => false,
          "durationMs" => 1
        }
      }
    }

  defp completed_turn(status),
    do: %{
      "method" => "turn/completed",
      "params" => %{
        "threadId" => "thread",
        "turn" => %{"id" => "turn", "status" => status, "items" => [], "error" => nil}
      }
    }

  defp result, do: {:ok, %{"success" => true, "contentItems" => []}}
end
