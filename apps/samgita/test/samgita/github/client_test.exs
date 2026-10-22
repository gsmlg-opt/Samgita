defmodule Samgita.GitHub.ClientTest do
  use ExUnit.Case, async: false
  alias Samgita.GitHub.{Client, Failure, HTTP, Secrets}
  @now 1_800_000_000
  @permissions Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})

  defmodule FakeHTTP do
    def request(method, url, headers, body, opts) do
      Process.put(
        :github_requests,
        Process.get(:github_requests, []) ++ [{method, url, headers, body, opts}]
      )

      [response | rest] = Process.get(:github_responses, [])
      Process.put(:github_responses, rest)
      response
    end
  end

  setup_all do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])
    public = {:RSAPublicKey, elem(key, 2), elem(key, 3)}
    {:ok, pem: pem, public: public}
  end

  setup %{pem: pem} do
    previous =
      for key <- [:github_hosts, :github_secrets],
          into: %{},
          do: {key, Application.get_env(:samgita, key)}

    Application.put_env(:samgita, :github_hosts, %{
      "fixture" => %{
        api_url: "http://127.0.0.1:43219",
        addresses: [{127, 0, 0, 1}],
        allow_insecure: true
      }
    })

    Application.put_env(:samgita, :github_secrets, %{
      "key-v1" => pem,
      "webhook-v1" => "webhook-fixture"
    })

    Process.put(:github_requests, [])

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:samgita, key),
          else: Application.put_env(:samgita, key, value)
      end)
    end)

    {:ok,
     connection: %{
       id: "connection",
       version: 1,
       host: "fixture",
       app_id: "7",
       installation_id: "9",
       private_key_ref: "key-v1",
       webhook_secret_ref: "webhook-v1"
     },
     repository: %{external_id: "42", full_name: "owner/repo", default_branch: "main"}}
  end

  test "verifies JWT, installation identity and repository with an explicitly read-only scoped token",
       %{connection: connection, public: public} do
    queue(auth_responses())

    assert {:ok,
            %{
              external_id: "42",
              full_name: "owner/repo",
              default_branch: "main",
              permissions: @permissions
            }} = Client.verify(connection, "42", opts())

    [
      {:get, installation_url, headers, nil, _},
      {:post, token_url, _, token_body, _},
      {:get, repo_url, repo_headers, nil, _}
    ] = requests()

    assert installation_url == base() <> "/app/installations/9"
    assert token_url == base() <> "/app/installations/9/access_tokens"
    assert repo_url == base() <> "/repositories/42"
    assert Jason.decode!(token_body) == %{"repository_ids" => [42], "permissions" => @permissions}
    headers = Map.new(headers)
    repo_headers = Map.new(repo_headers)
    assert headers["x-github-api-version"] == "2022-11-28"
    assert headers["accept"] == "application/vnd.github+json"
    "Bearer " <> jwt = headers["authorization"]
    [header, claims, signature] = String.split(jwt, ".")

    assert Jason.decode!(Base.url_decode64!(header, padding: false)) == %{
             "alg" => "RS256",
             "typ" => "JWT"
           }

    assert Jason.decode!(Base.url_decode64!(claims, padding: false)) == %{
             "iss" => "7",
             "iat" => @now - 60,
             "exp" => @now + 540
           }

    assert :public_key.verify(
             header <> "." <> claims,
             :sha256,
             Base.url_decode64!(signature, padding: false),
             public
           )

    assert repo_headers["authorization"] == "Bearer ephemeral-token"
  end

  test "runtime reference rotation is resolved without cached credentials", %{
    connection: connection
  } do
    queue(auth_responses())
    assert {:ok, _} = Client.verify(connection, "42", opts())
    Application.put_env(:samgita, :github_secrets, %{"key-v2" => "invalid-private-secret"})

    assert {:error, %Failure{class: :authentication, code: :secret_unavailable}} =
             Client.verify(connection, "42", opts())

    assert {:error, %Failure{class: :authentication, code: :private_key_invalid}} =
             Client.verify(%{connection | private_key_ref: "key-v2"}, "42", opts())

    assert length(requests()) == 3
    assert {:error, %Failure{code: :secret_unavailable}} = Secrets.resolve("absent")
  end

  test "accepts DateTime clocks for authentication and rate-limit reset calculations", %{
    connection: connection
  } do
    test_opts = Keyword.put(opts(), :now, DateTime.from_unix!(@now))
    queue(auth_responses())
    assert {:ok, _} = Client.verify(connection, "42", test_opts)

    queue([
      response(403, %{}, [
        {"x-ratelimit-remaining", "0"},
        {"x-ratelimit-reset", Integer.to_string(@now + 90)}
      ])
    ])

    assert {:error, %Failure{class: :rate_limited, retry_after: 90}} =
             Client.verify(connection, "42", test_opts)
  end

  test "rejects app mismatch, suspension and missing installation permissions before minting", %{
    connection: connection
  } do
    for {changes, code} <- [
          {%{"app_id" => 8}, :installation_mismatch},
          {%{"id" => 8}, :installation_mismatch},
          {%{"suspended_at" => "2026-01-01T00:00:00Z"}, :installation_suspended},
          {%{"permissions" => Map.delete(@permissions, "checks")}, :permissions_missing}
        ] do
      queue([ok(Map.merge(installation(), changes))])
      assert {:error, %Failure{code: ^code}} = Client.verify(connection, "42", opts())
      assert Process.get(:github_responses) == []
    end

    assert Enum.all?(requests(), fn {method, _, _, _, _} -> method == :get end)
  end

  test "rejects write permissions, extra permissions, expired and overlong tokens and wrong token repository",
       %{connection: connection} do
    for changes <- [
          %{"permissions" => Map.put(@permissions, "issues", "write")},
          %{"permissions" => Map.put(@permissions, "contents", "read")},
          %{"expires_at" => DateTime.from_unix!(@now - 1) |> DateTime.to_iso8601()},
          %{"expires_at" => DateTime.from_unix!(@now + 7200) |> DateTime.to_iso8601()},
          %{"repositories" => [%{"id" => 43}]},
          %{"token" => "injected\r\nsecret"}
        ] do
      queue([ok(installation()), ok(Map.merge(token(), changes))])

      assert {:error, %Failure{code: :unsafe_installation_token}} =
               Client.verify(connection, "42", opts())

      assert Process.get(:github_responses) == []
    end
  end

  test "a mismatched immutable repository ID never verifies", %{connection: connection} do
    queue([
      ok(installation()),
      ok(token()),
      ok(%{"id" => 43, "full_name" => "owner/repo", "default_branch" => "main"})
    ])

    assert {:error, %Failure{code: :repository_mismatch}} =
             Client.verify(connection, "42", opts())
  end

  test "classifies primary and secondary limits with retry and reset metadata", %{
    connection: connection
  } do
    for {status, headers, body, delay} <- [
          {429, [{"retry-after", "12"}], %{}, 12},
          {403,
           [{"x-ratelimit-remaining", "0"}, {"x-ratelimit-reset", Integer.to_string(@now + 90)}],
           %{}, 90},
          {403,
           [
             {"retry-after", "12"},
             {"x-ratelimit-remaining", "0"},
             {"x-ratelimit-reset", Integer.to_string(@now + 90)}
           ], %{}, 90},
          {403, [], %{"message" => "You have exceeded a secondary rate limit."}, 60},
          {429, [{"Retry-After", "Fri, 15 Jan 2027 08:01:00 GMT"}], %{}, 60}
        ] do
      queue([response(status, body, headers)])
      # HTTP-date test uses an independently fixed request clock.
      test_opts =
        if List.keymember?(headers, "Retry-After", 0),
          do: Keyword.put(opts(), :now, DateTime.to_unix(~U[2027-01-15 08:00:00Z])),
          else: opts()

      assert {:error, %Failure{class: :rate_limited, code: :rate_limited, retry_after: ^delay}} =
               Client.verify(connection, "42", test_opts)
    end
  end

  test "errors expose only safe classifications and never provider bodies or credentials", %{
    connection: connection
  } do
    for {status, class, code} <- [
          {401, :authentication, :authentication_failed},
          {403, :permission, :permission_denied},
          {404, :permission, :resource_unavailable},
          {302, :permanent, :redirect_rejected},
          {500, :retryable, :github_unavailable}
        ] do
      queue([
        response(status, %{"message" => "plaintext-credential"}, [
          {"location", "https://attacker.invalid"}
        ])
      ])

      assert {:error, %Failure{class: ^class, code: ^code} = failure} =
               Client.verify(connection, "42", opts())

      refute inspect(failure) =~ "plaintext-credential"
      refute inspect(failure) =~ "ephemeral-token"
    end

    queue([{:error, {:credential, "private-value"}}])

    assert {:error, %Failure{code: :transport_unavailable}} =
             Client.verify(connection, "42", opts())
  end

  test "successful exhausted responses stop before any follow-on HTTP request", %{
    connection: connection,
    repository: repository
  } do
    stages = [
      installation(),
      token(),
      %{"id" => 42, "full_name" => "owner/repo", "default_branch" => "main"},
      []
    ]

    for index <- 0..3 do
      Process.put(:github_requests, [])

      exhausted =
        response(200, Enum.at(stages, index), [
          {"x-ratelimit-remaining", "0"},
          {"x-ratelimit-reset", Integer.to_string(@now + 7200)}
        ])

      queue(
        Enum.take(auth_responses(), index) ++ [exhausted, ok(%{"must_not_be_requested" => true})]
      )

      result =
        if index < 3,
          do: Client.verify(connection, "42", opts()),
          else: Client.fetch(connection, repository, %{kind: :issues}, opts())

      assert {:error, %Failure{class: :rate_limited, code: :rate_limited, retry_after: 7200}} =
               result

      assert length(requests()) == index + 1
      assert length(Process.get(:github_responses)) == 1
    end
  end

  test "preserves provider delays above an hour and chooses the later reset deadline", %{
    connection: connection
  } do
    for {status, headers, class, delay} <- [
          {429, [{"retry-after", "7200"}], :rate_limited, 7200},
          {503, [{"retry-after", "7200"}], :retryable, 7200},
          {200, [{"retry-after", "7200"}], :rate_limited, 7200},
          {200,
           [
             {"retry-after", "7200"},
             {"x-ratelimit-remaining", "0"},
             {"x-ratelimit-reset", Integer.to_string(@now + 9000)}
           ], :rate_limited, 9000},
          {429, [{"retry-after", "604800"}], :rate_limited, 604_800}
        ] do
      queue([response(status, installation(), headers)])

      assert {:error, %Failure{class: ^class, retry_after: ^delay}} =
               Client.verify(connection, "42", opts())
    end
  end

  test "excessive, malformed and unrepresentable provider deadlines require explicit recovery", %{
    connection: connection
  } do
    for {headers, delay} <- [
          {[{"retry-after", "604801"}], 604_801},
          {[{"retry-after", "invalid-provider-deadline"}], nil},
          {[{"retry-after", "999999999999999999999999"}], nil},
          {[{"x-ratelimit-remaining", "0"}, {"x-ratelimit-reset", "invalid-reset"}], nil},
          {[
             {"retry-after", "7200"},
             {"x-ratelimit-remaining", "0"},
             {"x-ratelimit-reset", "invalid-reset"}
           ], nil}
        ] do
      queue([response(429, %{}, headers)])

      assert {:error,
              %Failure{
                class: :permanent,
                code: :rate_limit_recovery_required,
                retry_after: ^delay
              }} = Client.verify(connection, "42", opts())
    end

    queue([
      response(200, installation(), [{"x-ratelimit-remaining", "0"}, {"retry-after", "604801"}])
    ])

    assert {:error,
            %Failure{class: :permanent, code: :rate_limit_recovery_required, retry_after: 604_801}} =
             Client.verify(connection, "42", opts())
  end

  test "bounds response bytes and fails closed without exact approved addresses", %{
    connection: connection
  } do
    queue([{:ok, %{status: 200, headers: [], body: String.duplicate("a", 2_097_153)}}])
    assert {:error, %Failure{code: :response_too_large}} = Client.verify(connection, "42", opts())
    Application.put_env(:samgita, :github_hosts, %{})
    assert {:error, %Failure{code: :unapproved_destination}} = HTTP.resolve("github.com")

    Application.put_env(:samgita, :github_hosts, %{
      "fixture" => %{api_url: base(), addresses: [{127, 0, 0, 2}], allow_insecure: true}
    })

    assert {:error, %Failure{code: :unapproved_destination}} =
             Client.verify(connection, "42", opts())

    Application.put_env(:samgita, :github_hosts, %{
      "fixture" => %{api_url: base(), addresses: [{127, 0, 0, 1}]}
    })

    assert {:error, %Failure{code: :unapproved_destination}} = HTTP.resolve("fixture")

    Application.put_env(:samgita, :github_hosts, %{
      "github.com" => %{api_url: base(), addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    assert {:error, %Failure{code: :unapproved_destination}} = HTTP.resolve("github.com")
  end

  test "issues pagination excludes pull stubs and never follows response URLs", %{
    connection: connection,
    repository: repository
  } do
    next = base() <> "/repos/owner/repo/issues?per_page=50&page=2&state=all"

    queue(
      auth_responses() ++
        [
          response(
            200,
            [%{"id" => 1, "number" => 1}, %{"id" => 2, "number" => 2, "pull_request" => %{}}],
            [{"link", "<#{next}>; rel=\"next\""}]
          )
        ]
    )

    assert {:ok, %{items: [%{"id" => 1}], next_page: 2}} =
             Client.fetch(connection, repository, %{kind: :issues, page: 1}, opts())

    assert length(requests()) == 4
    assert {:get, url, _, _, _} = List.last(requests())

    assert URI.decode_query(URI.parse(url).query) == %{
             "per_page" => "50",
             "page" => "1",
             "state" => "all"
           }

    queue(
      auth_responses() ++
        [
          response(200, [], [
            {"link", "<https://attacker.invalid/repos/owner/repo/issues?page=2>; rel=\"next\""}
          ])
        ]
    )

    assert {:error, %Failure{code: :invalid_pagination}} =
             Client.fetch(connection, repository, %{kind: :issues}, opts())

    skipped_page = base() <> "/repos/owner/repo/issues?per_page=50&page=3&state=all"
    queue(auth_responses() ++ [response(200, [], [{"link", "<#{skipped_page}>; rel=\"next\""}])])

    assert {:error, %Failure{code: :invalid_pagination}} =
             Client.fetch(connection, repository, %{kind: :issues, page: 1}, opts())
  end

  test "only supported GET resource paths are exposed", %{
    connection: connection,
    repository: repository
  } do
    cases = [
      {:pulls, nil, "/pulls", [%{"id" => 81}]},
      {:workflow_runs, nil, "/actions/runs", %{"workflow_runs" => [%{"id" => 81}]}},
      {:check_runs, nil, "/commits/main/check-runs", %{"check_runs" => [%{"id" => 81}]}},
      {:issue, 81, "/issues/81", %{"id" => 999, "number" => 81}},
      {:pull_request, 81, "/pulls/81", %{"id" => 999, "number" => 81}},
      {:check_run, 81, "/check-runs/81", %{"id" => 81}},
      {:check_suite, 81, "/check-suites/81", %{"id" => 81}},
      {:workflow_run, 81, "/actions/runs/81", %{"id" => 81}},
      {:comment, 81, "/issues/comments/81", %{"id" => 81}}
    ]

    for {kind, id, path, body} <- cases do
      queue(auth_responses() ++ [ok(body)])

      assert {:ok, %{items: [_]}} =
               Client.fetch(connection, repository, %{kind: kind, resource_id: id}, opts())

      assert {:get, url, _, _, _} = List.last(requests())
      assert URI.parse(url).path == "/repos/owner/repo" <> path
    end

    assert Enum.all?(requests(), fn {method, url, _, _, _} ->
             method == :get ||
               (method == :post && String.ends_with?(url, "/app/installations/9/access_tokens"))
           end)
  end

  test "rejects resource and canonical repository mismatches, moved bindings and unsafe requests",
       %{connection: connection, repository: repository} do
    for object <- [
          %{"id" => 82},
          %{"id" => 81, "repository" => %{"id" => 43}},
          %{"id" => 81, "repository_url" => "https://attacker.invalid/repos/owner/repo"},
          %{"id" => 81, "base" => %{"repo" => %{"full_name" => "other/repo"}}}
        ] do
      queue(auth_responses() ++ [ok(object)])

      assert {:error, %Failure{}} =
               Client.fetch(connection, repository, %{kind: :check_run, resource_id: 81}, opts())
    end

    queue(auth_responses())

    assert {:error, %Failure{code: :repository_changed}} =
             Client.fetch(
               connection,
               %{repository | full_name: "other/repo"},
               %{kind: :issues},
               opts()
             )

    for request <- [
          %{kind: :delete},
          %{kind: :issues, page: 0},
          %{kind: :issue, resource_id: "../secrets"},
          %{kind: :issues, since: "yesterday"}
        ] do
      queue(auth_responses())

      assert {:error, %Failure{code: :invalid_request}} =
               Client.fetch(connection, repository, request, opts())
    end
  end

  test "locally filters since timestamps while preserving empty-page pagination", %{
    connection: connection,
    repository: repository
  } do
    next = base() <> "/repos/owner/repo/pulls?page=2&per_page=50"

    queue(
      auth_responses() ++
        [
          response(200, [%{"id" => 1, "updated_at" => "2025-01-01T00:00:00Z"}], [
            {"link", "<#{next}>; rel=\"next\""}
          ])
        ]
    )

    assert {:ok, %{items: [], next_page: 2}} =
             Client.fetch(
               connection,
               repository,
               %{kind: :pulls, since: "2026-01-01T00:00:00Z"},
               opts()
             )
  end

  test "retains later completions when check runs expose start times without updated_at", %{
    connection: connection,
    repository: repository
  } do
    completed = %{
      "id" => 81,
      "status" => "completed",
      "conclusion" => "success",
      "created_at" => "2026-01-01T00:00:00Z",
      "started_at" => "2026-01-01T00:01:00Z",
      "completed_at" => "2026-01-01T02:00:00Z"
    }

    queue(auth_responses() ++ [ok(%{"check_runs" => [completed]})])

    assert {:ok, %{items: [^completed], next_page: nil}} =
             Client.fetch(
               connection,
               repository,
               %{kind: :check_runs, since: "2026-01-01T01:00:00Z"},
               opts()
             )
  end

  defp auth_responses,
    do: [
      ok(installation()),
      ok(token()),
      ok(%{"id" => 42, "full_name" => "owner/repo", "default_branch" => "main"})
    ]

  defp installation,
    do: %{"id" => 9, "app_id" => 7, "suspended_at" => nil, "permissions" => @permissions}

  defp token,
    do: %{
      "token" => "ephemeral-token",
      "expires_at" => DateTime.from_unix!(@now + 3600) |> DateTime.to_iso8601(),
      "permissions" => @permissions,
      "repositories" => [%{"id" => 42}]
    }

  defp ok(body), do: response(200, body)

  defp response(status, body, headers \\ []),
    do: {:ok, %{status: status, headers: headers, body: Jason.encode!(body)}}

  defp queue(responses), do: Process.put(:github_responses, responses)
  defp requests, do: Process.get(:github_requests)
  defp base, do: "http://127.0.0.1:43219"
  defp opts, do: [http: FakeHTTP, now: @now]
end
