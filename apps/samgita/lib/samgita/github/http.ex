defmodule Samgita.GitHub.HTTP do
  @moduledoc """
  Bounded, nonredirecting HTTP with approved DNS answers and a pinned Fetch socket.

  `:github_hosts` maps registered host names to `%{api_url: base, addresses: [ip]}`.
  GitHub.com always uses `https://api.github.com`; even that default needs operator
  supplied pins and fails closed without them. Enterprise bases may include `/api/v3`.
  Plain HTTP requires `allow_insecure: true` and exclusively loopback addresses.
  The original hostname remains the HTTP Host and TLS SNI/verification name.
  """
  alias Samgita.GitHub.Failure
  @max_bytes 2_097_152
  @timeout 10_000
  @cleanup_timeout 1_000

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
    safe_request(method, url, headers, body, opts)
  end

  defp safe_request(method, url, headers, body, opts) do
    destination = Keyword.fetch!(opts, :destination)
    uri = URI.parse(url)

    with true <- read_only_method?(method, uri, destination),
         true <- approved_url?(uri, destination) do
      fetch(method, url, headers, body, destination)
    else
      _ -> {:error, :transport_unavailable}
    end
  rescue
    _ -> {:error, :transport_unavailable}
  catch
    _, _ -> {:error, :transport_unavailable}
  end

  defp fetch(method, url, headers, body, destination) do
    # Reserve the final second for the request's explicit cleanup barrier. Killing
    # a caller task alone does not establish that Fetch's socket owner has stopped.
    deadline = System.monotonic_time(:millisecond) + @timeout - @cleanup_timeout

    promise =
      HTTP.fetch(url,
        method: method,
        headers: headers,
        body: body,
        connect_address: destination.address,
        connect_timeout: 3_000,
        timeout: remaining(deadline),
        http_version: :http1,
        tls_backend: :ex_ssl,
        http1_reuse: false,
        redirect: :manual,
        decode_body: false,
        stream_response: true,
        response_header_limits: [max_head_bytes: 32_768],
        telemetry: false
      )

    completion = HTTP.Promise.completion(promise)

    result =
      try do
        case HTTP.Promise.await(promise, remaining(deadline)) do
          %HTTP.Response{} = response -> receive_response(response, deadline)
          {:error, _} -> {:error, :transport_unavailable}
        end
      rescue
        _ -> {:error, :transport_unavailable}
      catch
        :exit, _ -> {:error, :timeout}
      end

    case HTTP.RequestCompletion.abort_and_await(completion, @cleanup_timeout) do
      :ok -> result
      {:error, _} -> {:error, :transport_cleanup_unconfirmed}
    end
  end

  defp receive_response(response, deadline) do
    with {:ok, body} <- receive_body(response, deadline) do
      {:ok, %{status: response.status, headers: response.headers.headers, body: body}}
    end
  end

  defp receive_body(response, deadline) do
    case HTTP.Response.stream_pid(response) do
      stream when is_pid(stream) ->
        monitor = Process.monitor(stream)

        try do
          send(stream, {:read_chunk, self(), :ack})
          collect_body(stream, monitor, deadline, [], 0)
        after
          Process.demonitor(monitor, [:flush])
        end

      nil ->
        body = response.body || ""
        if byte_size(body) <= @max_bytes, do: {:ok, body}, else: {:error, :response_too_large}
    end
  end

  defp collect_body(stream, monitor, deadline, chunks, size) do
    receive do
      {:stream_chunk, ^stream, chunk, ack} ->
        if size + byte_size(chunk) <= @max_bytes do
          send(stream, {:stream_chunk_ack, ack})
          collect_body(stream, monitor, deadline, [chunk | chunks], size + byte_size(chunk))
        else
          {:error, :response_too_large}
        end

      {:stream_end, ^stream} ->
        {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}

      {:stream_trailers, ^stream, _headers} ->
        collect_body(stream, monitor, deadline, chunks, size)

      {:stream_error, ^stream, _reason} ->
        {:error, :transport_unavailable}

      {:DOWN, ^monitor, :process, ^stream, _reason} ->
        {:error, :transport_unavailable}
    after
      remaining(deadline) -> {:error, :timeout}
    end
  end

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

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
