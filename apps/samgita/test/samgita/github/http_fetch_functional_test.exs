defmodule Samgita.GitHub.HTTPFetchFunctionalTest do
  use ExUnit.Case, async: true
  alias Samgita.GitHub.HTTP

  test "streamed response preserves status, duplicate headers and complete body" do
    {url, destination, server} =
      server(fn socket ->
        :gen_tcp.send(socket, [
          "HTTP/1.1 206 Partial Content\r\n",
          "content-length: 11\r\nx-page: first\r\nx-page: second\r\n\r\nhello "
        ])

        :gen_tcp.send(socket, "world")
      end)

    assert {:ok, %{status: 206, headers: headers, body: "hello world"}} =
             HTTP.request(:get, url, [], nil, destination: destination)

    assert Enum.filter(headers, &(elem(&1, 0) == "x-page")) ==
             [{"x-page", "first"}, {"x-page", "second"}]

    assert :ok = Task.await(server)
  end

  test "chunked response stops at the body limit and closes the request" do
    {url, destination, server} =
      server(fn socket ->
        :ok = :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\n\r\n")

        Enum.reduce_while(1..33, :ok, fn _, _ ->
          case :gen_tcp.send(socket, ["10000\r\n", String.duplicate("x", 65_536), "\r\n"]) do
            :ok -> {:cont, :ok}
            {:error, :closed} -> {:halt, :ok}
          end
        end)

        # No terminal chunk: the byte ceiling, rather than EOF, must end the request.
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
      end)

    assert {:error, :response_too_large} =
             HTTP.request(:get, url, [], nil, destination: destination)

    assert :ok = Task.await(server)
  end

  test "an incomplete response body is returned as a transport failure" do
    {url, destination, server} =
      server(fn socket ->
        :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\ncontent-length: 20\r\n\r\npartial")
      end)

    assert {:error, :transport_unavailable} =
             HTTP.request(:get, url, [], nil, destination: destination)

    assert :ok = Task.await(server)
  end

  defp server(reply) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {address, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)

        try do
          read_request(socket, "")
          reply.(socket)
          :ok
        after
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server.pid), do: Task.shutdown(server, :brutal_kill)
    end)

    {base <> "/facts", %{uri: URI.parse(base), address: address}, server}
  end

  defp read_request(socket, buffer) do
    if String.contains?(buffer, "\r\n\r\n") do
      :ok
    else
      {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
      read_request(socket, buffer <> bytes)
    end
  end
end
