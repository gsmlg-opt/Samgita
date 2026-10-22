defmodule Samgita.GitHub.HTTPTest do
  use ExUnit.Case, async: false
  alias Samgita.GitHub.{Client, Failure, HTTP}
  @permissions Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})

  setup do
    previous =
      Map.new([:github_hosts, :github_secrets], &{&1, Application.fetch_env(:samgita, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:samgita, key, value)
          :error -> Application.delete_env(:samgita, key)
        end
      end
    end)

    :ok
  end

  test "real pinned HTTP socket verifies installation and reads current facts without repository writes" do
    now = System.system_time(:second)
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    Application.put_env(:samgita, :github_secrets, %{"local-key-v1" => pem})

    {base, server} =
      server([
        json(%{"id" => 20, "app_id" => 10, "suspended_at" => nil, "permissions" => @permissions}),
        json(%{
          "token" => "local-ephemeral-token",
          "permissions" => @permissions,
          "expires_at" => DateTime.from_unix!(now + 3600) |> DateTime.to_iso8601(),
          "repositories" => [%{"id" => 30}]
        }),
        json(%{"id" => 30, "full_name" => "owner/repo", "default_branch" => "main"}),
        json([
          %{"id" => 300, "number" => 3, "state" => "open", "updated_at" => "2026-10-22T00:00:00Z"}
        ])
      ])

    approve(base)

    connection = %{
      host: "loopback-fixture",
      app_id: "10",
      installation_id: "20",
      private_key_ref: "local-key-v1"
    }

    repository = %{external_id: "30", full_name: "owner/repo", default_branch: "main"}

    assert {:ok, %{items: [%{"number" => 3}], next_page: nil}} =
             Client.fetch(connection, repository, %{kind: :issues, page: 1, since: nil}, now: now)

    assert :ok == Task.await(server, 5000)
    assert_receive {:wire_request, "GET", "/app/installations/20", headers, ""}
    assert headers["x-github-api-version"] == "2022-11-28"

    assert headers["host"] ==
             URI.parse(base).host <> ":" <> Integer.to_string(URI.parse(base).port)

    assert_receive {:wire_request, "POST", "/app/installations/20/access_tokens", _, body}
    assert Jason.decode!(body) == %{"repository_ids" => [30], "permissions" => @permissions}
    assert_receive {:wire_request, "GET", "/repositories/30", headers, ""}
    assert headers["authorization"] == "Bearer local-ephemeral-token"
    assert_receive {:wire_request, "GET", path, _, ""}
    assert path =~ "/repos/owner/repo/issues?"
    refute_receive {:wire_request, _, _, _, _}
  end

  test "HTTP refuses repository writes and never follows redirects" do
    {base, server} = server([{302, [{"location", "http://unapproved.invalid/credentials"}], ""}])
    approve(base)
    assert {:ok, destination} = HTTP.resolve("loopback-fixture")

    assert {:error, :transport_unavailable} =
             HTTP.request(:post, base <> "/repos/owner/repo/issues", [], "{}",
               destination: destination
             )

    assert {:ok, %{status: 302}} =
             HTTP.request(:get, base <> "/redirect", [], nil, destination: destination)

    assert :ok == Task.await(server, 5000)
    assert_receive {:wire_request, "GET", "/redirect", _, _}
    refute_receive {:wire_request, "POST", _, _, _}
  end

  test "response buffering is bounded and wrong destination approval fails closed" do
    {base, server} = server([{200, [], String.duplicate("x", 2_097_153)}])
    approve(base)
    assert {:ok, destination} = HTTP.resolve("loopback-fixture")

    assert {:error, :response_too_large} =
             HTTP.request(:get, base <> "/large", [], nil, destination: destination)

    assert :ok == Task.await(server, 5000)

    Application.put_env(:samgita, :github_hosts, %{
      "loopback-fixture" => %{api_url: base, addresses: [{127, 0, 0, 2}], allow_insecure: true}
    })

    assert {:error, %Failure{code: :unapproved_destination}} = HTTP.resolve("loopback-fixture")
  end

  defp approve(base),
    do:
      Application.put_env(:samgita, :github_hosts, %{
        "loopback-fixture" => %{api_url: base, addresses: [{127, 0, 0, 1}], allow_insecure: true}
      })

  defp json(body), do: {200, [{"content-type", "application/json"}], Jason.encode!(body)}

  defp server(responses) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listener)
    caller = self()
    on_exit(fn -> :gen_tcp.close(listener) end)

    task =
      Task.async(fn ->
        for {status, headers, body} <- responses do
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {method, path, request_headers, request_body} = read_request(socket)
          send(caller, {:wire_request, method, path, request_headers, request_body})

          :gen_tcp.send(socket, [
            "HTTP/1.1 ",
            Integer.to_string(status),
            " fixture\r\n",
            Enum.map(headers, fn {k, v} -> [k, ": ", v, "\r\n"] end),
            "content-length: ",
            Integer.to_string(byte_size(body)),
            "\r\nconnection: close\r\n\r\n",
            body
          ])

          :gen_tcp.close(socket)
        end

        :gen_tcp.close(listener)
        :ok
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp read_request(socket, acc \\ "") do
    case String.split(acc, "\r\n\r\n", parts: 2) do
      [head, body] ->
        [line | headers] = String.split(head, "\r\n")
        [method, path, _] = String.split(line, " ")

        headers =
          Map.new(headers, fn header ->
            [key, value] = String.split(header, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        size = String.to_integer(headers["content-length"] || "0")

        body =
          if byte_size(body) < size do
            {:ok, rest} = :gen_tcp.recv(socket, size - byte_size(body), 5000)
            body <> rest
          else
            body
          end

        {method, path, headers, body}

      _ ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 5000)
        read_request(socket, acc <> data)
    end
  end
end
