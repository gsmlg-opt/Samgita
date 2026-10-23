defmodule SamgitaCodexDriver.StdioSessionFixtureTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  test "cleanup waits for the owned stdio guardian after the linked Session dies" do
    with_session(fn session, connection, owner ->
      guardian = connection.owner.pid
      session_monitor = Process.monitor(session)
      assert :ok = :sys.suspend(guardian)

      send(owner, :shutdown)
      assert_receive {:DOWN, ^session_monitor, :process, ^session, :shutdown}, 5_000
      assert :atomics.get(connection.owner.completion, 1) == 0

      parent = self()

      {closer, closer_monitor} =
        spawn_monitor(fn ->
          receive do
            :close ->
              assert :ok = StdioSessionFixture.close(session, connection)
              send(parent, {:cleanup_finished, self()})
          end
        end)

      :erlang.trace(closer, true, [:send])
      send(closer, :close)

      receive do
        {:trace, ^closer, :send, {:"$gen_call", _from, :close}, ^guardian} ->
          assert :atomics.get(connection.owner.completion, 1) == 0

        {:cleanup_finished, ^closer} ->
          flunk("fixture cleanup completed before awaiting the owned stdio guardian")
      after
        5_000 -> flunk("fixture cleanup did not request owned stdio shutdown")
      end

      assert :ok = :sys.resume(guardian)
      assert_receive {:cleanup_finished, ^closer}, 5_000
      assert_receive {:DOWN, ^closer_monitor, :process, ^closer, :normal}, 5_000
      assert :atomics.get(connection.owner.completion, 1) == 1
    end)
  end

  test "cleanup closes a live Session and tolerates an existing explicit close" do
    for scenario <- [:live, :explicitly_closed] do
      with_session(fn session, connection, _owner ->
        session_monitor = Process.monitor(session)
        if scenario == :explicitly_closed, do: assert(:ok = Session.close(session))

        assert :ok = StdioSessionFixture.close(session, connection)
        assert_receive {:DOWN, ^session_monitor, :process, ^session, :normal}, 5_000
        assert :atomics.get(connection.owner.completion, 1) == 1
        assert :ok = StdioSessionFixture.close(session, connection)
      end)
    end
  end

  test "cleanup tolerates owner shutdown after requesting a live Session close" do
    with_session(fn session, connection, owner ->
      parent = self()
      session_monitor = Process.monitor(session)
      assert :ok = :sys.suspend(session)

      try do
        {closer, closer_monitor} =
          spawn_monitor(fn ->
            receive do
              :close ->
                assert :ok = StdioSessionFixture.close(session, connection)
                send(parent, {:cleanup_finished, self()})
            end
          end)

        :erlang.trace(closer, true, [:send])
        send(closer, :close)

        assert_receive {:trace, ^closer, :send, {:"$gen_call", _from, :close}, ^session}, 5_000

        send(owner, :shutdown)
        assert_receive {:DOWN, ^session_monitor, :process, ^session, :shutdown}, 5_000

        receive do
          {:cleanup_finished, ^closer} ->
            assert :atomics.get(connection.owner.completion, 1) == 1

          {:DOWN, ^closer_monitor, :process, ^closer, reason} ->
            flunk("fixture cleanup exited during Session shutdown: #{inspect(reason)}")
        after
          5_000 -> flunk("fixture cleanup did not finish after Session shutdown")
        end

        assert_receive {:DOWN, ^closer_monitor, :process, ^closer, :normal}, 5_000
      after
        if Process.alive?(session), do: assert(:ok = :sys.resume(session))
      end
    end)
  end

  defp with_session(fun) do
    parent = self()

    root =
      Path.join(
        System.tmp_dir!(),
        "samgita-codex-fixture-cleanup-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(root)

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        parent_monitor = Process.monitor(parent)

        {:ok, session} =
          Session.start_link(
            transport:
              {Stdio,
               [
                 executable: "python3",
                 args: ["-u", "-c", "import sys;sys.stdin.buffer.read()"],
                 env: %{"HOME" => root, "CODEX_HOME" => root}
               ]}
          )

        connection = :sys.get_state(session).connection
        send(parent, {:owned_session, self(), session, connection})

        receive do
          :shutdown -> exit(:shutdown)
          {:DOWN, ^parent_monitor, :process, ^parent, _reason} -> exit(:shutdown)
        end
      end)

    {session, connection} =
      receive do
        {:owned_session, ^owner, session, connection} ->
          {session, connection}

        {:DOWN, ^owner_monitor, :process, ^owner, reason} ->
          flunk("owned Session startup failed: #{inspect(reason)}; scratch retained at #{root}")
      after
        5_000 ->
          Process.exit(owner, :shutdown)
          flunk("owned Session startup timed out; scratch retained at #{root}")
      end

    try do
      fun.(session, connection, owner)
    after
      if :atomics.get(connection.owner.completion, 1) == 0 and
           Process.alive?(connection.owner.pid),
         do: assert(:ok = :sys.resume(connection.owner.pid))

      if Process.alive?(owner), do: Process.exit(owner, :shutdown)
      assert :ok = Stdio.close(connection)
      File.rm_rf!(root)
    end
  end
end
