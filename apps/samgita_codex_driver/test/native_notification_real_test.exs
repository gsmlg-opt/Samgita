defmodule SamgitaCodexDriver.NativeNotificationRealTest do
  use ExUnit.Case, async: false

  alias SamgitaCodexDriver.{InitializedFixture, Session, StdioSessionFixture}
  alias SamgitaCodexDriver.Transport.Stdio

  @moduletag :real_codex
  @moduletag timeout: 60_000

  setup {InitializedFixture, :setup}

  for transport <- [:stdio, :websocket, :unix_socket] do
    @tag transport: transport
    test "Session native notifications remain unconfirmed and preserve readiness over #{transport}",
         context do
      {pid, borrowed} = session(context)
      assert %{phase: :new, pending: 0} = Session.status(pid)

      assert {:ok, %{outcome: :sent_unconfirmed}} =
               Session.notify_native(pid, %{"method" => "initialized"})

      assert %{phase: :new, pending: 0} = Session.status(pid)

      assert {:ok,
              %{
                "result" => %{"platformOs" => "linux", "codexHome" => codex_home}
              }} =
               Session.initialize(pid, %{
                 "name" => "samgita_native_notification_probe",
                 "version" => "0.1.0"
               })

      assert codex_home == context.codex_home
      assert %{phase: :ready, pending: 0} = Session.status(pid)

      for wire <- [
            %{"method" => "initialized"},
            %{"method" => "initialized", "params" => nil},
            %{"method" => "initialized", "params" => %{}},
            %{"method" => "initialized", "params" => []},
            %{"method" => "initialized", "params" => "é🙂"},
            %{"method" => "initialized", "params" => 42},
            %{"method" => "initialized", "params" => false},
            %{
              "method" => "initialized",
              "params" => %{"nested" => [nil, %{"text" => "é🙂"}]},
              "future" => %{"preserved" => [true, nil]}
            },
            %{"method" => "initialized"}
          ] do
        before = Session.status(pid)
        assert {:ok, %{outcome: :sent_unconfirmed}} = Session.notify_native(pid, wire)

        # Independent server notifications may arrive during the local send.
        assert Map.drop(Session.status(pid), [:buffered_events, :buffered_bytes]) ==
                 Map.drop(before, [:buffered_events, :buffered_bytes])

        assert {:ok, %{"result" => %{"data" => data}}} =
                 Session.request(pid, "thread/list", %{})

        assert is_list(data)
        assert %{phase: :ready, pending: 0, uncertain: 0} = Session.status(pid)
        assert {:ok, events} = Session.drain(pid)
        assert Enum.all?(events, &(&1.kind == :notification))
        refute Enum.any?(events, &(&1.wire["method"] == "initialized"))
      end

      assert :ok = Session.close(pid)

      if borrowed do
        InitializedFixture.assert_borrowed_survival(borrowed, :absent)
        InitializedFixture.close_owner(borrowed)
      end
    end
  end

  defp session(%{transport: :stdio} = context) do
    {:ok, pid} =
      Session.start_link(
        transport:
          {Stdio,
           [
             executable: context.binary,
             args: ["app-server", "--listen", "stdio://"],
             cwd: context.workspace,
             env: %{
               "HOME" => context.home,
               "CODEX_HOME" => context.codex_home,
               "CODEX_DISABLE_REMOTE_CONTROL" => "1"
             }
           ]}
      )

    StdioSessionFixture.register_cleanup(pid)
    {pid, nil}
  end

  defp session(context) do
    borrowed = InitializedFixture.open(context, context.transport)
    assert :ok = borrowed.module.close(borrowed.state)
    {:ok, pid} = Session.start_link(transport: {borrowed.module, borrowed.client_opts})
    %{connection: connection} = :sys.get_state(pid)

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: assert(:ok = Session.close(pid))
      catch
        :exit, {reason, {GenServer, :call, [^pid, :close, :infinity]}}
        when reason in [:noproc, :normal, :shutdown] ->
          :ok
      after
        assert :ok = borrowed.module.close(connection)
      end
    end)

    {pid, borrowed}
  end
end
