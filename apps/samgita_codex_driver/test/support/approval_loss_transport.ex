defmodule SamgitaCodexDriver.ApprovalLossTransport do
  @moduledoc false
  @behaviour SamgitaCodexDriver.Transport

  alias SamgitaCodexDriver.Transport.WebSocket

  # Test-only loss at the client transport boundary. Every delivered app-server
  # frame is unchanged native output. This wrapper never generates wire frames.
  @impl true
  def open(opts) do
    control = Keyword.fetch!(opts, :control)
    opts = Keyword.delete(opts, :control)

    with {:ok, socket} <- WebSocket.open(opts) do
      Agent.update(control, &%{&1 | opens: &1.opens + 1, blackhole: false})
      {:ok, %{socket: socket, control: control}}
    end
  end

  @impl true
  def send(state, encoded) do
    wire = JSON.decode!(encoded)

    disposition =
      Agent.get_and_update(state.control, fn control ->
        reply = Map.has_key?(wire, "id") and not Map.has_key?(wire, "method")
        targeted = reply and wire["id"] == control.target

        {disposition, control} =
          case {targeted, control.mode} do
            {true, :drop_reply_once} ->
              {:dropped, %{control | mode: :normal}}

            {true, :suppress_notifications_after_reply} ->
              {:forwarded, %{control | mode: :normal, blackhole: true}}

            _ ->
              {:forwarded, control}
          end

        entry = %{
          generation: control.opens,
          kind: if(reply, do: :reply, else: :method),
          id: wire["id"],
          method: wire["method"],
          digest: :crypto.hash(:sha256, encoded),
          disposition: disposition
        }

        true = length(control.outbound) < 128
        {disposition, %{control | outbound: control.outbound ++ [entry]}}
      end)

    case disposition do
      # A successful local send followed by loss before peer receipt is one
      # possible network outcome. It does not establish remote acceptance.
      :dropped -> {:ok, state}
      :forwarded -> wrap(WebSocket.send(state.socket, encoded), state)
    end
  end

  @impl true
  def handle_info(message, state) do
    case WebSocket.handle_info(message, state.socket) do
      {:ok, events, socket} ->
        events = Enum.reject(events, &discard?(&1, state.control))
        {:ok, events, %{state | socket: socket}}

      other ->
        wrap(other, state)
    end
  end

  defp discard?({:message, encoded}, control) do
    wire = JSON.decode!(encoded)

    Agent.get_and_update(control, fn state ->
      if state.blackhole and Map.has_key?(wire, "method") and not Map.has_key?(wire, "id") do
        params = wire["params"] || %{}

        entry = %{
          generation: state.opens,
          method: wire["method"],
          thread_id: params["threadId"],
          request_id: params["requestId"],
          turn_id: get_in(params, ["turn", "id"]),
          turn_status: get_in(params, ["turn", "status"]),
          digest: :crypto.hash(:sha256, encoded)
        }

        true = length(state.discarded) < 256
        {true, %{state | discarded: state.discarded ++ [entry]}}
      else
        {false, state}
      end
    end)
  end

  defp discard?(_event, _control), do: false

  defp wrap({:ok, socket}, state), do: {:ok, %{state | socket: socket}}
  defp wrap({:error, error, socket}, state), do: {:error, error, %{state | socket: socket}}
  defp wrap(:unknown, _state), do: :unknown

  @impl true
  def close(state), do: WebSocket.close(state.socket)

  @impl true
  def metadata(state),
    do: Map.put(WebSocket.metadata(state.socket), "test_fault_injection", true)
end
