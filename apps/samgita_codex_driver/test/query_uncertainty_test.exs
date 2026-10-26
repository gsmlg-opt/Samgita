defmodule SamgitaCodexDriver.QueryUncertaintyTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias SamgitaCodexDriver.{ScriptedTransport, Session}
  alias SamgitaProtocolCodex.Error

  @queries [
    {"server/diagnostics", %{}},
    {"thread/search", %{"searchTerm" => "owned query"}},
    {"thread/searchOccurrences", %{"threadId" => "owned-thread", "searchTerm" => "owned"}},
    {"thread/timeline/list", %{"threadId" => "owned-thread"}},
    {"thread/items/list", %{"threadId" => "owned-thread"}},
    {"thread/items/read",
     %{"threadId" => "owned-thread", "turnId" => "owned-turn", "itemIds" => ["owned-item"]}}
  ]

  for {method, params} <- @queries do
    @method method
    @params params

    test "#{method} deadline does not retain execution uncertainty or retry" do
      pid = ready()
      {task, wire} = pending(pid, @method, @params, timeout_ms: 30)

      assert {:error, %Error{code: :deadline_exceeded, uncertain: false}} = Task.await(task)
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
      refute_receive {:sent, ^pid, ^wire}

      late = %{"id" => wire["id"], "result" => %{}}
      send(pid, {:incoming, late})
      assert_receive {:codex_driver, ^pid, :events_available}, 2_000
      assert {:ok, [%{kind: :late_response, wire: ^late}]} = Session.drain(pid)
      assert Session.uncertain_operations(pid) == []
      assert_next_mutation(pid)
    end

    test "#{method} disconnect does not become uncertain work or replay on reconnect" do
      pid = ready()
      {task, wire} = pending(pid, @method, @params)
      send(pid, :drop_connection)

      assert {:error, %Error{uncertain: false}} = Task.await(task)
      assert %{phase: :disconnected, pending: 0, uncertain: 0, gap: %{}} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
      assert :ok = Session.reconnect(pid)
      assert_receive {:transport_opened, ^pid}
      initialize(pid)
      refute_receive {:sent, ^pid, ^wire}
      assert %{generation: 2, pending: 0, uncertain: 0} = Session.status(pid)
      assert_next_mutation(pid)
    end

    test "#{method} failed send releases the query without execution uncertainty" do
      pid = ready(fail_method: @method)
      wire = %{"id" => "owned-query", "method" => @method, "params" => @params}

      assert {:error, %Error{uncertain: false}} = Session.request_native(pid, wire)
      assert_receive {:sent, ^pid, ^wire}
      assert %{phase: :disconnected, pending: 0, uncertain: 0} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
      assert :ok = Session.reconnect(pid)
      assert_receive {:transport_opened, ^pid}
      initialize(pid)
      refute_receive {:sent, ^pid, ^wire}
      assert_next_mutation(pid)
    end

    test "#{method} local abandonment ends only the wait without uncertain execution" do
      pid = ready()
      {task, wire} = pending(pid, @method, @params)
      assert :ok = Session.abandon(pid, wire["id"])

      assert {:error, %Error{code: :locally_abandoned, uncertain: false}} = Task.await(task)
      assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
      assert Session.uncertain_operations(pid) == []
      refute_receive {:sent, ^pid, _}
      assert_next_mutation(pid)
    end
  end

  test "an in-flight known query does not reserve mutation uncertainty capacity" do
    pid = ready()
    {query, query_wire} = pending(pid, "thread/list", %{})
    assert %{pending: 1, uncertain: 0} = Session.status(pid)
    assert_next_mutation(pid)
    reply(pid, query, query_wire, %{"data" => [], "nextCursor" => nil})
    assert %{pending: 0, uncertain: 0} = Session.status(pid)
  end

  test "pending mutations still reserve capacity while queries may proceed" do
    pid = ready()
    {mutation, mutation_wire} = pending(pid, "thread/archive", %{"threadId" => "owned-thread"})

    assert {:error, %Error{code: :reconciliation_required, uncertain: false}} =
             Session.request(pid, "thread/archive", %{"threadId" => "other-thread"},
               id: "blocked"
             )

    refute_receive {:sent, ^pid, %{"id" => "blocked"}}
    {query, query_wire} = pending(pid, "thread/list", %{})
    reply(pid, query, query_wire, %{"data" => [], "nextCursor" => nil})
    assert %{pending: 1, uncertain: 0} = Session.status(pid)
    reply(pid, mutation, mutation_wire, %{})
    assert Session.uncertain_operations(pid) == []
  end

  test "lost mutation responses retain uncertainty and are never retried" do
    pid = ready()
    {mutation, wire} = pending(pid, "thread/archive", %{"threadId" => "owned-thread"})
    assert :ok = Session.abandon(pid, wire["id"])
    assert {:error, %Error{code: :locally_abandoned, uncertain: true}} = Task.await(mutation)
    id = wire["id"]
    assert [%{id: ^id, method: "thread/archive"}] = Session.uncertain_operations(pid)

    assert {:error, %Error{code: :reconciliation_required}} =
             Session.request(pid, "thread/archive", %{"threadId" => "other-thread"})

    refute_receive {:sent, ^pid, _}
    {query, query_wire} = pending(pid, "thread/list", %{})
    reply(pid, query, query_wire, %{"data" => [], "nextCursor" => nil})
    assert %{pending: 0, uncertain: 1} = Session.status(pid)
  end

  test "unclassified extensions remain potentially mutating" do
    pid = ready()
    {task, wire} = pending(pid, "future/operation", %{}, validation: :wire)
    send(pid, :drop_connection)
    assert {:error, %Error{uncertain: true}} = Task.await(task)
    id = wire["id"]
    assert [%{id: ^id, method: "future/operation"}] = Session.uncertain_operations(pid)
    refute_receive {:sent, ^pid, ^wire}
  end

  test "pending queries still obey the independent max_pending bound" do
    pid = ready()
    {one, one_wire} = pending(pid, "thread/list", %{})
    {two, two_wire} = pending(pid, "thread/list", %{})

    assert {:error, %Error{code: :too_many_requests, uncertain: false}} =
             Session.request(pid, "thread/list", %{}, id: "over-bound")

    refute_receive {:sent, ^pid, %{"id" => "over-bound"}}

    for {task, wire} <- [{one, one_wire}, {two, two_wire}],
        do: reply(pid, task, wire, %{"data" => [], "nextCursor" => nil})

    assert %{pending: 0, uncertain: 0} = Session.status(pid)
  end

  defp assert_next_mutation(pid) do
    {task, wire} = pending(pid, "thread/archive", %{"threadId" => "owned-thread"})
    reply(pid, task, wire, %{})
  end

  defp pending(pid, method, params, opts \\ []) do
    id = "owned-query-#{System.unique_integer([:positive, :monotonic])}"
    wire = %{"id" => id, "method" => method, "params" => params}
    task = Task.async(fn -> Session.request_native(pid, wire, opts) end)
    assert_receive {:sent, ^pid, ^wire}, 2_000
    {task, wire}
  end

  defp reply(pid, task, wire, result) do
    response = %{"id" => wire["id"], "result" => result}
    send(pid, {:incoming, response})
    assert {:ok, ^response} = Task.await(task)
  end

  defp ready(transport_opts \\ []) do
    pid =
      start_supervised!(
        {Session,
         transport: {ScriptedTransport, Keyword.put(transport_opts, :observer, self())},
         owner: self(),
         max_uncertain: 1,
         max_pending: 2},
        id: make_ref()
      )

    assert_receive {:transport_opened, ^pid}
    initialize(pid)
    pid
  end

  defp initialize(pid) do
    info = %{"name" => "query_uncertainty", "version" => "0.1.0"}
    task = Task.async(fn -> Session.initialize(pid, info, %{"experimentalApi" => true}) end)
    assert_receive {:sent, ^pid, %{"id" => id, "method" => "initialize"}}, 2_000

    result = %{
      "userAgent" => "codex/0.163.0",
      "codexHome" => "/owned-query-fixture",
      "platformFamily" => "unix",
      "platformOs" => "linux"
    }

    send(pid, {:incoming, %{"id" => id, "result" => result}})
    assert {:ok, %{"result" => ^result}} = Task.await(task)
    assert_receive {:sent, ^pid, %{"method" => "initialized"}}, 2_000
  end
end
