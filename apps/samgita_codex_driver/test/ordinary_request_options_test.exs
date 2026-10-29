defmodule SamgitaCodexDriver.OrdinaryRequestOptionsTest do
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  @info %{"name" => "ordinary_options", "version" => "0.1.0"}

  setup do
    pid =
      start_supervised!(
        {Session, owner: self(), transport: {ScriptedTransport, observer: self()}}
      )

    assert_receive {:transport_opened, ^pid}
    %{pid: pid}
  end

  test "invalid initialization options preserve the same connection for a later handshake", %{
    pid: pid
  } do
    for opts <- invalid_options() do
      assert {:error, %Error{code: :invalid_options, uncertain: false}} =
               Session.initialize(pid, @info, %{}, opts)

      assert_new(pid)
    end

    refute_receive {:sent, ^pid, _}
    initialize(pid)
    assert_ready(pid)
  end

  test "invalid native initialization options do not consume its request identity", %{pid: pid} do
    wire = %{
      "id" => "initialize-options",
      "method" => "initialize",
      "params" => %{"clientInfo" => @info}
    }

    for opts <- invalid_options() do
      assert {:error, %Error{code: :invalid_options, uncertain: false}} =
               Session.request_native(pid, wire, opts)

      assert_new(pid)
    end

    refute_receive {:sent, ^pid, _}
    initialize(pid, wire)
    assert_ready(pid)
  end

  test "invalid read options preserve an already pending request and permit later correlation", %{
    pid: pid
  } do
    initialize(pid)
    held = Task.async(fn -> Session.request(pid, "thread/list", %{}, id: "held-read") end)
    assert_receive {:sent, ^pid, %{"id" => "held-read", "method" => "thread/list"}}, 2_000
    wire = %{"id" => "options-read", "method" => "thread/list", "params" => %{}}

    for opts <- invalid_options() do
      assert {:error, %Error{code: :invalid_options, uncertain: false}} =
               Session.request(pid, "thread/list", %{}, opts)

      assert {:error, %Error{code: :invalid_options, uncertain: false}} =
               Session.request_native(pid, wire, opts)

      assert %{phase: :ready, generation: 1, pending: 1, uncertain: 0, gap: nil} =
               Session.status(pid)
    end

    refute_receive {:sent, ^pid, _}
    reply = %{"id" => "held-read", "result" => %{"data" => []}}
    send(pid, {:incoming, reply})
    assert {:ok, ^reply} = Task.await(held)
    assert_ready(pid)

    next = Task.async(fn -> Session.request_native(pid, wire) end)
    assert_receive {:sent, ^pid, ^wire}, 2_000
    next_reply = %{"id" => "options-read", "result" => %{"data" => []}}
    send(pid, {:incoming, next_reply})
    assert {:ok, ^next_reply} = Task.await(next)
    assert_ready(pid)
    assert {:ok, []} = Session.drain(pid)
    refute_receive {:sent, ^pid, _}
  end

  defp invalid_options,
    do: [[{:effect}], [{:timeout_ms}], [:not_a_keyword], [{"id", "unused"}], %{}]

  defp initialize(pid, wire \\ nil) do
    task =
      Task.async(fn ->
        if wire,
          do: Session.request_native(pid, wire),
          else: Session.initialize(pid, @info)
      end)

    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/isolated",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    reply = %{"id" => id, "result" => result}
    send(pid, {:incoming, reply})
    assert {:ok, ^reply} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
    assert_ready(pid)
  end

  defp assert_new(pid) do
    assert %{phase: :new, generation: 1, pending: 0, uncertain: 0, gap: nil} = Session.status(pid)
  end

  defp assert_ready(pid) do
    assert %{phase: :ready, generation: 1, pending: 0, interactions: 0, uncertain: 0, gap: nil} =
             Session.status(pid)

    assert Session.uncertain_operations(pid) == []
  end
end
