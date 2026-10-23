defmodule Samgita.GitHub.Client do
  @moduledoc """
  Read-only GitHub App REST client pinned to API version 2022-11-28.

  Every operation rechecks the installation and obtains a fresh repository-scoped
  token with metadata/issues/pull_requests/checks/actions read permissions. The
  sole POST is installation-token authentication; no repository writes exist.
  Credentials never appear in results, errors or logs and are not cached.

  Successful responses that exhaust quota or prescribe Retry-After stop the
  operation before another request. The caller durably records the returned
  cooldown and retries the same operation after it. Provider delays are never
  shortened. Automatic retry is bounded to seven days; longer or malformed
  deadlines return permanent `rate_limit_recovery_required` for explicit recovery.

  Lists use at most 50 objects per page. `check_runs` covers the current default
  branch only. `since` uses GitHub's server filter for issues and a local
  `updated_at` filter for other lists. Objects without a modification timestamp
  are retained; callers must follow every page, including empty pages.
  Pagination reads page numbers from validated same-endpoint links, never follows
  response URLs, and returns provider object maps with string keys.

  References: https://docs.github.com/en/rest/apps/apps?apiVersion=2022-11-28,
  https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app,
  https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28.
  """
  alias Samgita.GitHub.{Failure, HTTP, Secrets}
  @permissions Map.new(~w(metadata issues pull_requests checks actions), &{&1, "read"})
  @max_bytes 2_097_152
  @max_retry_seconds 604_800
  @max_unix_seconds 253_402_300_799
  @list_kinds [:issues, :pulls, :workflow_runs, :check_runs]

  def verify(connection, external_id, opts \\ []) do
    with {:ok, context} <- authorize(connection, external_id, opts) do
      {:ok, context.repository}
    end
  end

  def fetch(connection, repository, request, opts \\ []) do
    with {:ok, context} <- authorize(connection, repository.external_id, opts),
         true <-
           context.repository.full_name == repository.full_name &&
             context.repository.default_branch == repository.default_branch,
         {:ok, path, page, since} <- resource_path(repository, request),
         {:ok, body, headers} <- fetch_resource(connection, context, request, path, opts),
         {:ok, items} <- items(body, request.kind),
         true <- Enum.all?(items, &valid_object?(&1, repository, context, request)),
         {:ok, next_page} <- next_page(headers, context.destination.api_url <> path, page) do
      items =
        if request.kind == :issues,
          do: Enum.reject(items, &Map.has_key?(&1, "pull_request")),
          else: items

      {:ok, %{items: filter_since(items, since), next_page: next_page}}
    else
      {:error, %Failure{class: :not_found, code: :object_absent}} ->
        {:ok, %{items: [], next_page: nil, missing: true}}

      {:error, %Failure{}} = error ->
        error

      _ ->
        error(:permanent, :repository_changed)
    end
  rescue
    _ -> error(:permanent, :invalid_request)
  end

  # A targeted 404 is ambiguous until the installation and this exact repository
  # are revalidated. List, installation and repository 404s retain access fencing.
  defp fetch_resource(connection, context, resource, path, opts) do
    case request(context, :get, path, nil, context.token, opts) do
      {:error, %Failure{class: :permission, code: :resource_unavailable}}
      when resource.kind not in @list_kinds ->
        with {:ok, current} <- authorize(connection, context.repository.external_id, opts),
             true <- current.repository == context.repository do
          error(:not_found, :object_absent)
        else
          {:error, %Failure{}} = error -> error
          _ -> error(:permanent, :repository_changed)
        end

      result ->
        result
    end
  end

  defp authorize(connection, external_id, opts) do
    with {:ok, repository_id} <- positive_id(external_id),
         {:ok, app_id} <- positive_id(connection.app_id),
         {:ok, installation_id} <- positive_id(connection.installation_id),
         {:ok, destination} <- HTTP.resolve(connection.host),
         {:ok, private_key} <- Secrets.resolve(connection.private_key_ref),
         {:ok, jwt} <- jwt(app_id, private_key, now(opts)),
         context = %{destination: destination},
         {:ok, installation, _} <-
           request(context, :get, "/app/installations/#{installation_id}", nil, jwt, opts),
         :ok <- installation(installation, app_id, installation_id),
         {:ok, token_body, _} <-
           request(
             context,
             :post,
             "/app/installations/#{installation_id}/access_tokens",
             %{"repository_ids" => [repository_id], "permissions" => @permissions},
             jwt,
             opts
           ),
         {:ok, token} <- token(token_body, repository_id, now(opts)),
         {:ok, repository, _} <-
           request(context, :get, "/repositories/#{repository_id}", nil, token, opts),
         {:ok, metadata} <- repository(repository, repository_id) do
      {:ok, Map.merge(context, %{token: token, repository: metadata})}
    else
      {:error, %Failure{}} = error -> error
      _ -> error(:permanent, :invalid_connection)
    end
  rescue
    _ -> error(:permanent, :invalid_connection)
  end

  defp installation(body, app_id, installation_id) when is_map(body) do
    cond do
      body["id"] != installation_id || body["app_id"] != app_id ->
        error(:authentication, :installation_mismatch)

      !Map.has_key?(body, "suspended_at") ->
        error(:permanent, :invalid_response)

      body["suspended_at"] != nil ->
        error(:permission, :installation_suspended)

      !is_map(body["permissions"]) ->
        error(:permission, :permissions_missing)

      !Enum.all?(@permissions, fn {key, _} -> body["permissions"][key] in ["read", "write"] end) ->
        error(:permission, :permissions_missing)

      true ->
        :ok
    end
  end

  defp installation(_, _, _), do: error(:permanent, :invalid_response)

  defp token(body, repository_id, now) when is_map(body) do
    with token when is_binary(token) and byte_size(token) in 1..8192 <- body["token"],
         false <- String.contains?(token, ["\r", "\n"]),
         permissions when is_map(permissions) <- body["permissions"],
         true <- permissions == @permissions,
         {:ok, expires_at, _} <- DateTime.from_iso8601(body["expires_at"] || ""),
         expiry = DateTime.to_unix(expires_at),
         true <- expiry > now + 30 && expiry <= now + 3660,
         true <- token_repositories?(body, repository_id) do
      {:ok, token}
    else
      _ -> error(:permission, :unsafe_installation_token)
    end
  end

  defp token(_, _, _), do: error(:permission, :unsafe_installation_token)

  defp token_repositories?(%{"repositories" => [%{"id" => id}]}, id), do: true
  defp token_repositories?(body, _), do: !Map.has_key?(body, "repositories")

  defp repository(body, id) when is_map(body) do
    if body["id"] == id && safe_full_name?(body["full_name"]) &&
         safe_branch?(body["default_branch"]) do
      {:ok,
       %{
         external_id: Integer.to_string(id),
         full_name: body["full_name"],
         default_branch: body["default_branch"],
         permissions: @permissions
       }}
    else
      error(:permanent, :repository_mismatch)
    end
  end

  defp repository(_, _), do: error(:permanent, :invalid_response)

  defp jwt(app_id, pem, now) do
    with [entry] <- :public_key.pem_decode(pem),
         key when is_tuple(key) <- :public_key.pem_entry_decode(entry),
         true <- elem(key, 0) == :RSAPrivateKey do
      header = encode(%{"alg" => "RS256", "typ" => "JWT"})

      claims =
        encode(%{"iss" => Integer.to_string(app_id), "iat" => now - 60, "exp" => now + 540})

      unsigned = header <> "." <> claims
      signature = :public_key.sign(unsigned, :sha256, key) |> Base.url_encode64(padding: false)
      {:ok, unsigned <> "." <> signature}
    else
      _ -> error(:authentication, :private_key_invalid)
    end
  rescue
    _ -> error(:authentication, :private_key_invalid)
  catch
    _, _ -> error(:authentication, :private_key_invalid)
  end

  defp encode(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp request(context, method, path, body, credential, opts) do
    headers = [
      {"accept", "application/vnd.github+json"},
      {"x-github-api-version", "2022-11-28"},
      {"authorization", "Bearer " <> credential},
      {"user-agent", "Samgita-GitHub-App"},
      {"content-type", "application/json"}
    ]

    http = Keyword.get(opts, :http, HTTP)
    body = if body, do: Jason.encode!(body), else: nil
    url = context.destination.api_url <> path
    transport_opts = [destination: context.destination, timeout: 10_000, max_bytes: @max_bytes]

    case http.request(method, url, headers, body, transport_opts) do
      {:ok, %{status: status, headers: headers, body: body}}
      when is_integer(status) and is_binary(body) and is_list(headers) ->
        classify_response(status, headers, body, now(opts))

      {:error, :response_too_large} ->
        error(:permanent, :response_too_large)

      {:error, :timeout} ->
        error(:retryable, :timeout)

      _ ->
        error(:retryable, :transport_unavailable)
    end
  rescue
    _ -> error(:retryable, :transport_unavailable)
  catch
    _, _ -> error(:retryable, :transport_unavailable)
  end

  defp classify_response(status, headers, body, now) do
    cond do
      byte_size(body) > @max_bytes -> error(:permanent, :response_too_large)
      status in 200..299 -> successful_response(body, headers, now)
      true -> response_failure(status, headers, body, now)
    end
  end

  defp decode(body, headers) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) or is_list(decoded) -> {:ok, decoded, headers}
      _ -> error(:permanent, :invalid_response)
    end
  end

  defp successful_response(body, headers, now) do
    if header(headers, "x-ratelimit-remaining") == "0" || header(headers, "retry-after") != nil,
      do: rate_limit_failure(retry_after(headers, now), now),
      else: decode(body, headers)
  end

  defp response_failure(status, headers, body, now) do
    message = response_message(body)
    retry = retry_after(headers, now)

    cond do
      rate_limited?(status, headers, message) ->
        rate_limit_failure(retry, now)

      status == 401 ->
        error(:authentication, :authentication_failed)

      status == 403 ->
        permission_failure(message)

      status == 404 ->
        error(:permission, :resource_unavailable)

      status in 300..399 ->
        error(:permanent, :redirect_rejected)

      transient_status?(status) ->
        transient_failure(retry, now)

      true ->
        error(:permanent, :request_rejected)
    end
  end

  defp response_message(body) do
    case Jason.decode(body) do
      {:ok, %{"message" => value}} when is_binary(value) -> String.downcase(value)
      _ -> ""
    end
  end

  defp transient_failure(retry, now) do
    with {:ok, retry} <- safe_retry_delay(retry, now) do
      {:error, Failure.new(:retryable, :github_unavailable, retry)}
    end
  end

  defp permission_failure(message) do
    code =
      if String.contains?(message, "suspend"),
        do: :installation_suspended,
        else: :permission_denied

    error(:permission, code)
  end

  defp transient_status?(status), do: status in [408, 425] || status >= 500

  defp rate_limited?(429, _, _), do: true

  defp rate_limited?(403, headers, message) do
    header(headers, "x-ratelimit-remaining") == "0" || header(headers, "retry-after") != nil ||
      String.contains?(message, ["secondary rate limit", "rate limit exceeded", "abuse detection"])
  end

  defp rate_limited?(_, _, _), do: false

  defp rate_limit_failure(retry, now) do
    with {:ok, retry} <- safe_retry_delay(retry, now) do
      {:error, Failure.new(:rate_limited, :rate_limited, max(retry || 60, 1))}
    end
  end

  defp safe_retry_delay(nil, _now), do: {:ok, nil}

  defp safe_retry_delay(delay, now) when is_integer(delay) and delay >= 0 do
    cond do
      delay > @max_unix_seconds - now ->
        error(:permanent, :rate_limit_recovery_required)

      delay > @max_retry_seconds ->
        {:error, Failure.new(:permanent, :rate_limit_recovery_required, delay)}

      true ->
        {:ok, delay}
    end
  end

  defp safe_retry_delay(_, _now), do: error(:permanent, :rate_limit_recovery_required)

  defp retry_after(headers, now) do
    explicit = explicit_retry_after(header(headers, "retry-after"), now)

    reset =
      if header(headers, "x-ratelimit-remaining") == "0",
        do: integer_delay(header(headers, "x-ratelimit-reset"), now),
        else: nil

    case Enum.reject([explicit, reset], &is_nil/1) do
      [] -> nil
      values -> if :invalid in values, do: :invalid, else: Enum.max(values)
    end
  end

  defp explicit_retry_after(nil, _), do: nil

  defp explicit_retry_after(value, now) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> seconds
      _ -> http_date_delay(value, now) || :invalid
    end
  end

  defp integer_delay(value, now) when is_binary(value) do
    case Integer.parse(value) do
      {seconds, ""} when seconds >= 0 -> max(0, seconds - now)
      _ -> :invalid
    end
  end

  defp integer_delay(_, _), do: nil

  defp http_date_delay(value, now) do
    with [_, day, month, year, hour, minute, second] <-
           Regex.run(
             ~r/\A[A-Za-z]{3}, ([0-9]{2}) ([A-Za-z]{3}) ([0-9]{4}) ([0-9]{2}):([0-9]{2}):([0-9]{2}) GMT\z/,
             value
           ),
         month when is_integer(month) <-
           Enum.find_index(~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec), &(&1 == month)),
         {:ok, date} <- Date.new(String.to_integer(year), month + 1, String.to_integer(day)),
         {:ok, time} <-
           Time.new(String.to_integer(hour), String.to_integer(minute), String.to_integer(second)),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      max(0, DateTime.to_unix(datetime) - now)
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp resource_path(repository, request) do
    page = Map.get(request, :page, 1)
    since = Map.get(request, :since)

    with true <- safe_full_name?(repository.full_name) && safe_branch?(repository.default_branch),
         true <- is_integer(page) && page in 1..1_000_000,
         {:ok, since} <- since(since),
         {:ok, suffix} <- suffix(request, repository.default_branch) do
      params =
        if request.kind in @list_kinds,
          do: [{"per_page", "50"}, {"page", Integer.to_string(page)}],
          else: []

      params = if request.kind == :issues, do: params ++ [{"state", "all"}], else: params
      params = if request.kind == :pulls, do: params ++ [{"state", "all"}], else: params

      params =
        if request.kind == :issues && since,
          do: params ++ [{"since", DateTime.to_iso8601(since)}],
          else: params

      query = if params == [], do: "", else: "?" <> URI.encode_query(params)
      {:ok, "/repos/" <> repository.full_name <> suffix <> query, page, since}
    else
      _ -> error(:permanent, :invalid_request)
    end
  end

  defp suffix(%{kind: :issues}, _), do: {:ok, "/issues"}
  defp suffix(%{kind: :pulls}, _), do: {:ok, "/pulls"}
  defp suffix(%{kind: :workflow_runs}, _), do: {:ok, "/actions/runs"}

  defp suffix(%{kind: :check_runs}, branch),
    do: {:ok, "/commits/" <> URI.encode(branch, &URI.char_unreserved?/1) <> "/check-runs"}

  defp suffix(%{kind: kind, resource_id: id}, _) do
    with {:ok, id} <- positive_id(id),
         suffix when is_binary(suffix) <-
           %{
             issue: "/issues/",
             pull_request: "/pulls/",
             check_run: "/check-runs/",
             check_suite: "/check-suites/",
             workflow_run: "/actions/runs/",
             comment: "/issues/comments/"
           }[kind] do
      {:ok, suffix <> Integer.to_string(id)}
    else
      _ -> error(:permanent, :invalid_request)
    end
  end

  defp suffix(_, _), do: error(:permanent, :invalid_request)

  defp items(body, kind) when kind in [:issues, :pulls] and is_list(body), do: list_items(body)
  defp items(%{"workflow_runs" => items}, :workflow_runs), do: list_items(items)
  defp items(%{"check_runs" => items}, :check_runs), do: list_items(items)
  defp items(body, kind) when is_map(body) and kind not in @list_kinds, do: {:ok, [body]}
  defp items(_, _), do: error(:permanent, :invalid_response)

  defp list_items(items) when is_list(items) and length(items) <= 50, do: {:ok, items}
  defp list_items(_), do: error(:permanent, :invalid_response)

  defp valid_object?(object, repository, context, request) when is_map(object) do
    identity =
      if request.kind in [:issue, :pull_request], do: object["number"], else: object["id"]

    valid_identity =
      case positive_id(identity) do
        {:ok, id} ->
          request.kind in @list_kinds || match?({:ok, ^id}, positive_id(request.resource_id))

        _ ->
          false
      end

    valid_identity && canonical_repository?(object["repository"], repository) &&
      canonical_repository?(get_in(object, ["base", "repo"]), repository) &&
      canonical_url?(object["url"], repository, context) &&
      canonical_url?(object["repository_url"], repository, context)
  end

  defp valid_object?(_, _, _, _), do: false

  defp canonical_repository?(nil, _), do: true

  defp canonical_repository?(value, repository) when is_map(value) do
    (!Map.has_key?(value, "id") || to_string(value["id"]) == to_string(repository.external_id)) &&
      (!Map.has_key?(value, "full_name") || value["full_name"] == repository.full_name)
  end

  defp canonical_repository?(_, _), do: false

  defp canonical_url?(nil, _, _), do: true

  defp canonical_url?(url, repository, context) when is_binary(url) do
    base = context.destination.api_url <> "/repos/" <> repository.full_name
    url == base || String.starts_with?(url, base <> "/")
  end

  defp canonical_url?(_, _, _), do: false

  defp next_page(headers, url, page) do
    case header(headers, "link") do
      nil ->
        {:ok, nil}

      link ->
        links = Regex.scan(~r/<([^>]+)>\s*;\s*rel="next"/, link)

        case links do
          [] -> {:ok, nil}
          [[_, next]] -> validated_next(next, url, page)
          _ -> error(:permanent, :invalid_pagination)
        end
    end
  end

  defp validated_next(next, url, page) do
    actual = URI.parse(next)
    expected = URI.parse(url)
    params = URI.decode_query(actual.query || "")

    with true <-
           actual.scheme == expected.scheme && actual.host == expected.host &&
             actual.port == expected.port && actual.path == expected.path &&
             is_nil(actual.userinfo) && is_nil(actual.fragment),
         {:ok, next_page} <- positive_id(params["page"]),
         true <- next_page == page + 1 && next_page <= 1_000_000 do
      {:ok, next_page}
    else
      _ -> error(:permanent, :invalid_pagination)
    end
  end

  defp filter_since(items, nil), do: items

  defp filter_since(items, since) do
    Enum.filter(items, fn item ->
      case since(item["updated_at"]) do
        {:ok, nil} -> true
        {:ok, date} -> DateTime.compare(date, since) != :lt
        _ -> false
      end
    end)
  end

  defp since(nil), do: {:ok, nil}
  defp since(%DateTime{} = date), do: {:ok, date}

  defp since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> {:ok, date}
      _ -> :error
    end
  end

  defp since(_), do: :error

  defp header(headers, name) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) and is_binary(value) ->
        if String.downcase(key) == name, do: value

      _ ->
        nil
    end)
  end

  defp safe_full_name?(value) when is_binary(value),
    do:
      Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9-]{0,99}\/[A-Za-z0-9_.-]{1,100}\z/, value) &&
        !String.ends_with?(value, ["/.", "/.."])

  defp safe_full_name?(_), do: false

  defp safe_branch?(value),
    do:
      is_binary(value) && byte_size(value) in 1..255 &&
        !String.contains?(value, ["\r", "\n", "\u0000", ".."]) && value != "."

  defp positive_id(id) when is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807,
    do: {:ok, id}

  defp positive_id(id) when is_binary(id) and byte_size(id) in 1..19 do
    case Integer.parse(id) do
      {number, ""} when number > 0 and number <= 9_223_372_036_854_775_807 ->
        if Integer.to_string(number) == id, do: {:ok, number}, else: :error

      _ ->
        :error
    end
  end

  defp positive_id(_), do: :error

  defp now(opts) do
    case Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end) do
      %DateTime{} = value -> DateTime.to_unix(value)
      value when is_integer(value) -> value
    end
  end

  defp error(class, code), do: {:error, Failure.new(class, code)}
end
