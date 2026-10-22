defmodule SamgitaWeb.Plugs.AgentAuth do
  @moduledoc "Authenticates an Agent credential and its explicit current connection."

  import Plug.Conn

  alias Samgita.{Agents, Error}

  def init(opts), do: Keyword.get(opts, :require_connection, true)

  def call(conn, require_connection) do
    with {:ok, principal} <- authenticate(get_req_header(conn, "authorization")),
         {:ok, principal} <-
           connection(principal, get_req_header(conn, "x-agent-connection"), require_connection) do
      assign(conn, :samgita_principal, principal)
    else
      {:error, error} ->
        conn
        |> SamgitaWeb.FallbackController.call({:error, error})
        |> halt()
    end
  end

  defp authenticate([authorization]) do
    case String.split(authorization, " ", parts: 2) do
      [scheme, credential] when byte_size(credential) > 0 ->
        if String.match?(scheme, ~r/\Abearer\z/i),
          do: Agents.authenticate(credential),
          else: {:error, Error.new(:unauthorized)}

      _ ->
        {:error, Error.new(:unauthorized)}
    end
  end

  defp authenticate(_), do: {:error, Error.new(:unauthorized)}

  defp connection(principal, [id], _required), do: Agents.bind_connection(principal, id)
  defp connection(principal, [], false), do: {:ok, principal}
  defp connection(_, _, _), do: {:error, Error.new(:unauthorized)}
end
