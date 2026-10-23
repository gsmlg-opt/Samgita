defmodule SamgitaCodexDriver.ScriptedTransport do
  @moduledoc false
  import Kernel, except: [send: 2]
  @behaviour SamgitaCodexDriver.Transport
  alias SamgitaProtocolCodex.Error

  @impl true
  def open(opts) do
    Kernel.send(Keyword.fetch!(opts, :observer), {:transport_opened, self()})
    {:ok, Map.new(opts)}
  end

  @impl true
  def send(state, body) do
    wire = JSON.decode!(body)
    Kernel.send(state.observer, {:sent, self(), wire})

    if (is_binary(state[:fail_method]) and state[:fail_method] == wire["method"]) or
         (state[:fail_response] == true and Map.has_key?(wire, "result")),
       do: {:error, Error.new(:send_failed), state},
       else: {:ok, state}
  end

  @impl true
  def handle_info({:incoming, wire}, state) do
    {:ok, [{:message, JSON.encode!(wire)}], state}
  end

  def handle_info(:drop_connection, state), do: {:ok, [{:closed, %{}}], state}
  def handle_info(_, _), do: :unknown

  @impl true
  def close(state) do
    Kernel.send(state.observer, {:transport_closed, self()})
    if state[:fail_close], do: raise(Error.new(:owned_process_shutdown_unconfirmed))
    :ok
  end

  @impl true
  def metadata(_state), do: %{transport: :scripted, connected: true}
end
