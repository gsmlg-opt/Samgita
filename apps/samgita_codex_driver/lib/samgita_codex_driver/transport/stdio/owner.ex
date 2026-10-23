defmodule SamgitaCodexDriver.Transport.Stdio.Owner do
  @moduledoc false
  use GenServer
  alias SamgitaProtocolCodex.Error

  def open(python, opts) do
    completion = :atomics.new(1, [])

    with {:ok, pid} <- GenServer.start(__MODULE__, {self(), python, opts, completion}) do
      {:ok, %{pid: pid, completion: completion}, GenServer.call(pid, :port)}
    end
  end

  def close(%{pid: pid, completion: completion}) do
    case :atomics.get(completion, 1) do
      1 -> :ok
      2 -> raise Error.new(:owned_process_shutdown_unconfirmed)
      0 -> close_current(pid, completion)
    end
  end

  defp close_current(pid, completion) do
    case GenServer.call(pid, :close, 6_000) do
      :ok -> :ok
      {:error, code} -> raise Error.new(code)
    end
  catch
    :exit, _ ->
      if :atomics.get(completion, 1) == 1,
        do: :ok,
        else: raise(Error.new(:owned_process_shutdown_unconfirmed))
  end

  @impl true
  def init({owner, python, opts, completion}) do
    Process.flag(:trap_exit, true)
    monitor = Process.monitor(owner)
    port = Port.open({:spawn_executable, python}, opts)
    {:ok, %{owner: owner, monitor: monitor, port: port, completion: completion, reaped: false}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  def handle_call(:close, _from, state) do
    result = shutdown(state)
    record_completion(state, result)
    {:stop, :normal, result, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state) do
    result = shutdown(state)
    record_completion(state, result)
    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, _}} = message, %{port: port} = state) do
    record_completion(state, cleanup_result(state.reaped))
    send(state.owner, message)
    {:stop, :normal, state}
  end

  def handle_info({port, {:data, bytes}}, %{port: port} = state) do
    {bytes, reaped} = cleanup_ack(bytes, state.reaped)
    if bytes != <<>>, do: send(state.owner, {port, {:data, bytes}})
    {:noreply, %{state | reaped: reaped}}
  end

  def handle_info({:EXIT, port, :normal}, %{port: port} = state), do: {:noreply, state}

  defp shutdown(%{port: port, reaped: reaped}) do
    # Raw NUL is an internal helper control byte, impossible in valid JSONL.
    deadline = System.monotonic_time(:millisecond) + 5_000

    request_shutdown(port, deadline)

    await_exit(port, deadline, reaped)
  end

  defp await_exit(port, deadline, reaped) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:exit_status, _}} -> cleanup_result(reaped)
      {^port, {:data, bytes}} -> await_exit(port, deadline, elem(cleanup_ack(bytes, reaped), 1))
      {:EXIT, ^port, :normal} -> await_exit(port, deadline, reaped)
    after
      remaining ->
        close_port(port)
        {:error, :owned_process_shutdown_timeout}
    end
  end

  defp request_shutdown(port, deadline) do
    cond do
      is_nil(Port.info(port)) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        close_port(port)

      Port.command(port, <<0>>, [:nosuspend]) ->
        :ok

      true ->
        # `false` means no control byte was queued. Wait for port capacity;
        # never resend native data or close the cleanup-ACK channel early.
        receive do
        after
          1 -> request_shutdown(port, deadline)
        end
    end
  rescue
    ArgumentError -> :ok
  end

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp cleanup_ack(bytes, reaped),
    do:
      {:binary.replace(bytes, <<0>>, <<>>, [:global]),
       reaped or :binary.match(bytes, <<0>>) != :nomatch}

  defp cleanup_result(true), do: :ok
  defp cleanup_result(false), do: {:error, :owned_process_shutdown_unconfirmed}

  defp record_completion(state, result),
    do: :atomics.put(state.completion, 1, if(result == :ok, do: 1, else: 2))
end
