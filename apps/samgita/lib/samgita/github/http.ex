defmodule Samgita.GitHub.HTTP do
  @moduledoc """
  Bounded, nonredirecting HTTP with approved DNS answers and a pinned Mint socket.

  `:github_hosts` maps registered host names to `%{api_url: base, addresses: [ip]}`.
  GitHub.com always uses `https://api.github.com`; even that default needs operator
  supplied pins and fails closed without them. Enterprise bases may include `/api/v3`.
  Plain HTTP requires `allow_insecure: true` and exclusively loopback addresses.
  The original hostname remains the HTTP Host and TLS SNI/verification name.
  """
  alias Samgita.GitHub.Failure
  @max_bytes 2_097_152
  @timeout 10_000

  def resolve(host) when is_binary(host) do
    with %{api_url: base, addresses: approved} = approval <-
           Application.get_env(:samgita, :github_hosts, %{})[host],
         true <- host != "github.com" || base == "https://api.github.com",
         true <- is_list(approved) && approved != [] && Enum.all?(approved, &valid_ip?/1),
         {:ok, uri} <- base_uri(base),
         {:ok, addresses} <- addresses(uri.host),
         true <- Enum.all?(addresses, &(&1 in approved)),
         true <-
           uri.scheme == "https" ||
             (approval[:allow_insecure] == true && Enum.all?(addresses, &loopback?/1)) do
      {:ok, %{api_url: String.trim_trailing(base, "/"), address: hd(addresses), uri: uri}}
    else
      {:error, %Failure{}} = error -> error
      _ -> {:error, Failure.new(:permanent, :unapproved_destination)}
    end
  rescue
    _ -> {:error, Failure.new(:permanent, :unapproved_destination)}
  end

  def resolve(_), do: {:error, Failure.new(:permanent, :unapproved_destination)}

  @doc "The injectable transport contract; opts contain an already resolved :destination."
  def request(method, url, headers, body, opts) do
    # The task owns its socket, so timeout shutdown also closes outstanding I/O.
    task = Task.async(fn -> safe_request(method, url, headers, body, opts) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :timeout}
    end
  end

  defp safe_request(method, url, headers, body, opts) do
    destination = Keyword.fetch!(opts, :destination)
    uri = URI.parse(url)

    with true <- read_only_method?(method, uri, destination),
         true <- approved_url?(uri, destination),
         {:ok, conn} <- connect(destination) do
      try do
        path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

        case Mint.HTTP1.request(
               conn,
               method |> Atom.to_string() |> String.upcase(),
               path,
               headers,
               body
             ) do
          {:ok, conn, ref} ->
            receive_response(conn, ref, %{status: nil, headers: [], body: []}, 0)

          {:error, conn, _reason} ->
            Mint.HTTP1.close(conn)
            {:error, :transport_unavailable}
        end
      after
        Mint.HTTP1.close(conn)
      end
    else
      _ -> {:error, :transport_unavailable}
    end
  rescue
    _ -> {:error, :transport_unavailable}
  catch
    _, _ -> {:error, :transport_unavailable}
  end

  defp connect(%{uri: uri, address: address}) do
    scheme = if uri.scheme == "https", do: :https, else: :http
    transport = [timeout: 3_000]

    transport =
      if scheme == :https,
        do: Keyword.put(transport, :cacerts, :public_key.cacerts_get()),
        else: transport

    Mint.HTTP1.connect(scheme, address, uri.port,
      hostname: uri.host,
      mode: :passive,
      log: false,
      max_header_list_size: 32_768,
      transport_opts: transport
    )
  end

  defp receive_response(conn, ref, result, size) do
    case Mint.HTTP1.recv(conn, 0, @timeout) do
      {:ok, conn, responses} ->
        case consume(responses, ref, result, size) do
          {:more, result, size} ->
            receive_response(conn, ref, result, size)

          {:done, result} ->
            {:ok, %{result | body: result.body |> Enum.reverse() |> IO.iodata_to_binary()}}

          {:error, _} = error ->
            error
        end

      {:error, _conn, _reason, _responses} ->
        {:error, :transport_unavailable}
    end
  end

  defp consume([], _ref, result, size), do: {:more, result, size}

  defp consume([{:status, ref, status} | rest], ref, result, size),
    do: consume(rest, ref, %{result | status: status}, size)

  defp consume([{:headers, ref, headers} | rest], ref, result, size),
    do: consume(rest, ref, %{result | headers: result.headers ++ headers}, size)

  defp consume([{:data, ref, data} | rest], ref, result, size) do
    if size + byte_size(data) <= @max_bytes,
      do: consume(rest, ref, %{result | body: [data | result.body]}, size + byte_size(data)),
      else: {:error, :response_too_large}
  end

  defp consume([{:done, ref} | _], ref, result, _size), do: {:done, result}
  defp consume(_, _, _, _), do: {:error, :invalid_response}

  defp approved_url?(uri, %{uri: base}) do
    uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port &&
      is_nil(uri.userinfo) && is_nil(uri.fragment) && is_binary(uri.path) &&
      String.starts_with?(uri.path, String.trim_trailing(base.path || "", "/") <> "/")
  end

  defp read_only_method?(:get, _, _), do: true

  defp read_only_method?(:post, uri, %{uri: base}) do
    prefix = String.trim_trailing(base.path || "", "/")
    path = String.replace_prefix(uri.path || "", prefix, "")

    is_nil(uri.query) &&
      Regex.match?(~r/\A\/app\/installations\/[1-9][0-9]*\/access_tokens\z/, path)
  end

  defp read_only_method?(_, _, _), do: false

  defp base_uri(base) when is_binary(base) do
    uri = URI.parse(base)

    if uri.scheme in ["http", "https"] && is_binary(uri.host) && uri.host != "" &&
         safe_base_location?(uri),
       do: {:ok, uri},
       else: {:error, Failure.new(:permanent, :unapproved_destination)}
  end

  defp base_uri(_), do: {:error, Failure.new(:permanent, :unapproved_destination)}

  defp safe_base_location?(uri) do
    is_integer(uri.port) && uri.port in 1..65_535 && is_nil(uri.userinfo) &&
      is_nil(uri.query) && is_nil(uri.fragment) &&
      uri.path in [nil, "", "/", "/api/v3", "/api/v3/"]
  end

  defp addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, address} -> {:ok, [address]}
      _ -> dns_addresses(host)
    end
  end

  defp dns_addresses(host) do
    results =
      for family <- [:inet, :inet6], do: :inet.getaddrs(String.to_charlist(host), family, 1_000)

    # A failed family must not hide an unapproved address behind a resolver failure.
    if Enum.all?(results, &(match?({:ok, _}, &1) or &1 == {:error, :nxdomain})) do
      resolved_addresses(results)
    else
      {:error, Failure.new(:retryable, :dns_unavailable)}
    end
  end

  defp resolved_addresses(results) do
    case results |> Enum.flat_map(&address_values/1) |> Enum.uniq() |> Enum.sort() do
      [] -> {:error, Failure.new(:retryable, :dns_unavailable)}
      values -> {:ok, values}
    end
  end

  defp address_values({:ok, values}), do: values
  defp address_values(_), do: []

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback?(_), do: false

  defp valid_ip?(ip) when is_tuple(ip) and tuple_size(ip) == 4,
    do: ip |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) && &1 in 0..255))

  defp valid_ip?(ip) when is_tuple(ip) and tuple_size(ip) == 8,
    do: ip |> Tuple.to_list() |> Enum.all?(&(is_integer(&1) && &1 in 0..65_535))

  defp valid_ip?(_), do: false
end
