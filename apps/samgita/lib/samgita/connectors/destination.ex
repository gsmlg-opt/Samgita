defmodule Samgita.Connectors.Destination do
  @moduledoc """
  Resolves one explicitly approved registered destination and pins its socket address.

  Approval binds Agent ID, exact URL and an operator-supplied set of IP addresses. All addresses
  returned by DNS must still be approved. The selected tuple is passed directly to the transport,
  with the original hostname retained for HTTP Host and TLS verification/SNI. No redirects or
  URL-provided credentials are supported. Loopback plaintext requires explicit approval.
  """
  alias Samgita.Connector.Failure

  def resolve(%{agent_id: agent_id, endpoint_metadata: %{"url" => url} = endpoint}) do
    approvals = Application.get_env(:samgita, :event_destinations, %{})

    with true <- endpoint["transport"] == "websocket",
         %{url: ^url, addresses: approved} = approval <- approvals[agent_id],
         true <- is_list(approved) && approved != [] && Enum.all?(approved, &valid_ip?/1),
         {:ok, uri} <- uri(url),
         {:ok, addresses} <- addresses(uri.host),
         :ok <- unchanged(addresses, approved),
         :ok <- secure(uri, addresses, approval) do
      {:ok, %{url: url, address: hd(addresses)}}
    else
      {:error, %Failure{}} = failure -> failure
      _ -> {:error, Failure.new(:permanent, :destination_not_approved)}
    end
  end

  def resolve(_), do: {:error, Failure.new(:permanent, :destination_not_approved)}

  defp uri(url) when is_binary(url) do
    uri = URI.parse(url)

    if uri.scheme in ~w(ws wss) && is_binary(uri.host) && uri.host != "" &&
         is_integer(uri.port) && uri.port in 1..65535 && uri.path == "/app-server" &&
         is_nil(uri.userinfo) && is_nil(uri.query) && is_nil(uri.fragment),
       do: {:ok, uri},
       else: {:error, Failure.new(:permanent, :destination_not_approved)}
  rescue
    ArgumentError -> {:error, Failure.new(:permanent, :destination_not_approved)}
  end

  defp uri(_), do: {:error, Failure.new(:permanent, :destination_not_approved)}

  defp addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} ->
        {:ok, [address]}

      {:error, :einval} ->
        addresses =
          for family <- [:inet, :inet6],
              {:ok, addresses} <- [:inet.getaddrs(String.to_charlist(host), family, 1_000)],
              address <- addresses,
              do: address

        case Enum.uniq(addresses) |> Enum.sort() do
          [] -> {:error, Failure.new(:retryable, :dns_unavailable)}
          addresses -> {:ok, addresses}
        end
    end
  end

  defp unchanged(addresses, approved) do
    if Enum.all?(addresses, &(&1 in approved)),
      do: :ok,
      else: {:error, Failure.new(:permanent, :destination_address_changed)}
  end

  defp secure(%URI{scheme: "wss"}, _addresses, _approval), do: :ok

  defp secure(%URI{scheme: "ws"}, addresses, approval) do
    if approval[:allow_insecure] == true && Enum.all?(addresses, &loopback?/1),
      do: :ok,
      else: {:error, Failure.new(:permanent, :insecure_destination)}
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp valid_ip?(address) when is_tuple(address) and tuple_size(address) == 4,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) && &1 in 0..255))

  defp valid_ip?(address) when is_tuple(address) and tuple_size(address) == 8,
    do: address |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) && &1 in 0..65535))

  defp valid_ip?(_), do: false
end
