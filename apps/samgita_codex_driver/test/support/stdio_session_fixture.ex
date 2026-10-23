defmodule SamgitaCodexDriver.StdioSessionFixture do
  @moduledoc false
  import ExUnit.Assertions
  import ExUnit.Callbacks

  alias SamgitaCodexDriver.Session
  alias SamgitaCodexDriver.Transport.Stdio

  def register_cleanup(pid) do
    %{transport: Stdio, connection: connection} = :sys.get_state(pid)
    on_exit(fn -> close(pid, connection) end)
  end

  def close(pid, connection) do
    try do
      if Process.alive?(pid), do: assert(:ok = Session.close(pid))
      :ok
    catch
      :exit, {reason, {GenServer, :call, [^pid, :close, :infinity]}}
      when reason in [:noproc, :normal, :shutdown] ->
        :ok
    after
      assert :ok = Stdio.close(connection)
    end
  end
end
