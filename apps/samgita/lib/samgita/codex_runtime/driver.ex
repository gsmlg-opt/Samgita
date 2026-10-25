defmodule Samgita.CodexRuntime.Driver do
  @moduledoc """
  Explicit bridge for an Agent-owned, already started native driver.

  Dispatch intent and its one-use ticket commit before network I/O. This module
  starts no process, retries no operation and never reports Task completion.
  A caller crash after dispatch leaves an in-flight intent requiring assessment.
  Consumers journal drained notifications separately with their original sequence.
  """
  alias Samgita.{CodexRuntime, Error}
  alias SamgitaCodexDriver.Session

  def execute(session, principal, project_id, runtime_id, operation_id, attrs, opts \\ []) do
    with {:ok, runtime} <- CodexRuntime.get(principal, project_id, runtime_id),
         :ok <- generation(session, runtime),
         {:ok, ticket} <-
           CodexRuntime.dispatch(principal, project_id, runtime_id, operation_id, attrs) do
      outcome = send_native(session, ticket, opts)

      settlement =
        Map.merge(outcome, %{
          "command_id" => Ecto.UUID.generate(),
          "expected_version" => ticket["version"],
          "dispatch_token" => ticket["dispatch_token"]
        })

      CodexRuntime.settle(principal, project_id, runtime_id, operation_id, settlement)
    end
  end

  defp generation(session, runtime) do
    if same_instance?(Session.status(session), runtime),
      do: :ok,
      else: {:error, Error.new(:ownership_lost)}
  catch
    :exit, _ -> {:error, Error.new(:ownership_lost)}
  end

  defp send_native(session, ticket, opts) do
    wire = ticket["native"]

    {:ok, deadline, _} = DateTime.from_iso8601(ticket["dispatch_expires_at"])

    if Samgita.Commands.expired?(deadline) || !same_instance?(Session.status(session), ticket) do
      %{"delivery_outcome" => "uncertain"}
    else
      send_current(session, ticket, wire, opts)
    end
  catch
    :exit, _ -> %{"delivery_outcome" => "uncertain"}
  end

  defp same_instance?(%{instance_id: instance_id, generation: generation}, binding),
    do:
      instance_id == binding["instance_id"] &&
        generation == binding["driver_generation"]

  defp same_instance?(_, _), do: false

  defp send_current(session, %{"direction" => "client_request"} = ticket, wire, _opts) do
    {:ok, deadline, _} = DateTime.from_iso8601(ticket["dispatch_expires_at"])
    timeout = max(1, DateTime.diff(deadline, DateTime.utc_now(), :millisecond))

    case Session.request_native(session, wire, [{:timeout_ms, timeout} | dispatch_guards(ticket)]) do
      {:ok, response} -> %{"native" => response}
      {:error, %SamgitaProtocolCodex.Error{wire: %{} = response}} -> %{"native" => response}
      {:error, _} -> %{"delivery_outcome" => "uncertain"}
    end
  end

  defp send_current(session, %{"direction" => "client_notification"} = ticket, wire, _opts) do
    case Session.notify_native(session, wire, dispatch_guards(ticket)) do
      {:ok, %{outcome: :sent_unconfirmed}} -> %{"delivery_outcome" => "sent_unconfirmed"}
      {:error, _} -> %{"delivery_outcome" => "uncertain"}
    end
  end

  defp send_current(session, %{"direction" => "client_response"} = ticket, wire, opts) do
    handle = Keyword.get(opts, :interaction_handle)

    if is_map(handle) && handle[:id] == wire["id"] &&
         handle[:generation] == ticket["driver_generation"] do
      value =
        if Map.has_key?(wire, "result"), do: {:ok, wire["result"]}, else: {:error, wire["error"]}

      case Session.respond(session, handle, value, dispatch_guards(ticket)) do
        :ok -> %{"delivery_outcome" => "sent_unconfirmed"}
        {:error, _} -> %{"delivery_outcome" => "uncertain"}
      end
    else
      %{"delivery_outcome" => "uncertain"}
    end
  end

  defp dispatch_guards(ticket) do
    {:ok, deadline, _} = DateTime.from_iso8601(ticket["dispatch_expires_at"])

    [
      expected_instance_id: ticket["instance_id"],
      expected_generation: ticket["driver_generation"],
      dispatch_deadline_ms: DateTime.to_unix(deadline, :millisecond)
    ]
  end
end
