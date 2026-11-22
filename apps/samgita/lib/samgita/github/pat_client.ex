defmodule Samgita.GitHub.PatClient do
  @moduledoc "Read-only PAT account discovery and repository lists for the operator console."
  require Logger
  alias Samgita.GitHub.{Client, Failure, HTTP, PatFeed}

  @page_size 50
  @max_catalog_pages 2_000

  @doc false
  def valid_token?(token),
    do: is_binary(token) && byte_size(token) in 1..8192 && !String.contains?(token, ["\r", "\n"])

  def user(token, opts \\ []) do
    with {:ok, body, _} <- get(token, "/user", [], opts),
         {:ok, owner} <- owner(body) do
      {:ok, owner}
    end
  end

  def catalog(token, opts \\ []) do
    with {:ok, account} <- user(token, opts),
         {:ok, memberships, memberships_available} <- memberships(token, opts),
         {:ok, raw_repositories} <- all_pages(token, "/user/repos", [sort: "full_name"], opts),
         {:ok, organizations} <- map_valid(memberships, &membership_owner/1),
         {:ok, repositories} <- map_valid(raw_repositories, &repository/1) do
      repository_owners = Enum.map(repositories, &%{id: &1.owner_id, login: &1.owner})

      owners =
        [account | organizations ++ repository_owners]
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(&String.downcase(&1.login))

      repositories =
        repositories
        |> Enum.uniq_by(& &1.id)
        |> Enum.sort_by(&String.downcase(&1.owner <> "/" <> &1.name))

      {:ok,
       %{owners: owners, repositories: repositories, memberships_available: memberships_available}}
    end
  end

  defp memberships(token, opts) do
    case all_pages(token, "/user/memberships/orgs", [state: "active"], opts) do
      {:ok, entries} -> {:ok, entries, true}
      {:error, :forbidden} -> {:ok, [], false}
      error -> error
    end
  end

  def feed(token, repositories, filters, cursor \\ nil, opts \\ []),
    do: PatFeed.fetch(token, repositories, filters, cursor, opts)

  def sync_repository(token, selected, opts \\ []) do
    with {:ok, current} <- repository(token, selected.id, opts),
         :ok <- required_owner(current, selected),
         {:ok, issues} <- sync_pages(token, current, :issues, 1, [], opts),
         {:ok, pulls} <- sync_pages(token, current, :pulls, 1, [], opts),
         {:ok, ^current} <- repository(token, selected.id, opts) do
      {:ok, %{repository: current, items: issues ++ pulls}}
    else
      {:ok, _changed} -> {:error, :repository_changed}
      error -> error
    end
  end

  defp required_owner(current, selected) do
    case Map.get(selected, :required_owner_id) do
      nil -> :ok
      id when id == current.owner_id -> :ok
      _ -> {:error, :repository_changed}
    end
  end

  def workflow_runs(token, selected, opts \\ []) do
    with {:ok, current} <- repository(token, selected.id, opts),
         :ok <- required_owner(current, selected),
         {:ok, %{"workflow_runs" => rows}, _} when is_list(rows) <-
           get(
             token,
             "/repos/#{current.owner}/#{current.name}/actions/runs",
             [per_page: 20],
             opts
           ),
         {:ok, runs} <- map_valid(Enum.take(rows, 20), &workflow_run(&1, current)),
         {:ok, ^current} <- repository(token, selected.id, opts) do
      {:ok, %{repository: current, runs: Enum.reverse(runs)}}
    else
      {:ok, %{id: _}} -> {:error, :repository_changed}
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  defp workflow_run(%{"repository" => %{"id" => id}}, %{id: expected}) when id != expected,
    do: {:error, :repository_changed}

  defp workflow_run(%{"id" => id, "status" => status, "updated_at" => updated} = run, repo)
       when is_integer(id) and id > 0 and is_binary(status) and is_binary(updated) do
    with {:ok, datetime, _} <- DateTime.from_iso8601(updated) do
      title = optional_text(run["display_title"])
      name = optional_text(run["name"]) || title || "##{id}"

      actor =
        case run["actor"] do
          %{"login" => login} -> optional_text(login)
          _ -> nil
        end

      {:ok,
       %{
         "id" => id,
         "url" => "https://github.com/#{repo.owner}/#{repo.name}/actions/runs/#{id}",
         "name" => name,
         "number" => if(is_integer(run["run_number"]), do: run["run_number"], else: id),
         "title" => title || name,
         "branch" => optional_text(run["head_branch"]),
         "event" => optional_text(run["event"]),
         "status" => status,
         "conclusion" => optional_text(run["conclusion"]),
         "actor" => actor,
         "updated_at" => DateTime.to_iso8601(datetime)
       }}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp workflow_run(_, _), do: {:error, :invalid_response}

  defp optional_text(value) when is_binary(value), do: value
  defp optional_text(_), do: nil

  defp sync_pages(token, repository, kind, number, acc, opts) do
    path = "/repos/#{repository.owner}/#{repository.name}/#{kind}"
    # Edits to an older item should not move it between pages during the scan.
    params = [state: "open", sort: "created", direction: "asc"]

    with {:ok, page} <-
           page(token, path, params, number, Keyword.put(opts, :repository, repository)),
         {:ok, items} <- PatFeed.normalize(page.items, repository, kind) do
      item_kind = if kind == :issues, do: "issue", else: "pull_request"
      acc = [Enum.map(items, &Map.put(&1, :kind, item_kind)) | acc]

      if page.next_page do
        sync_pages(token, repository, kind, page.next_page, acc, opts)
      else
        {:ok, acc |> Enum.reverse() |> List.flatten() |> newest_items()}
      end
    end
  end

  defp newest_items(items) do
    items
    |> Enum.reduce(%{}, fn item, acc ->
      Map.update(acc, {item.kind, item.number}, item, fn previous ->
        if DateTime.compare(timestamp(item.updated_at), timestamp(previous.updated_at)) == :gt,
          do: item,
          else: previous
      end)
    end)
    |> Map.values()
  end

  defp timestamp(value) do
    {:ok, date, _} = DateTime.from_iso8601(value)
    date
  end

  @doc false
  def repository(token, id, opts) when is_integer(id) and id > 0 do
    with {:ok, body, _} <- get(token, "/repositories/#{id}", [], opts),
         {:ok, %{id: ^id} = repository} <- repository(body) do
      {:ok, repository}
    else
      {:error, _} = error -> error
      _ -> {:error, :repository_changed}
    end
  end

  @doc false
  def page(token, path, params, number, opts) when number in 1..1_000_000,
    do: page(token, path, params, %{page: number, after: nil}, opts)

  def page(token, path, params, %{page: number, after: after_cursor}, opts)
      when number in 1..1_000_000 and (is_nil(after_cursor) or is_binary(after_cursor)) do
    params = params ++ [per_page: @page_size, page: number]
    params = if after_cursor, do: params ++ [after: after_cursor], else: params
    query = URI.encode_query(params)

    with {:ok, body, headers} <- get(token, path, params, opts),
         true <- is_list(body) && length(body) <= @page_size,
         {:ok, next} <- next_page(headers, path <> "?" <> query, number, opts) do
      {:ok, %{items: body, next_page: next}}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_response}
    end
  end

  @doc false
  def now(opts), do: Keyword.get_lazy(opts, :now, fn -> System.system_time(:second) end)

  defp all_pages(token, path, params, opts), do: all_pages(token, path, params, 1, [], opts)

  defp all_pages(_token, _path, _params, page, _acc, _opts)
       when is_integer(page) and page > @max_catalog_pages,
       do: {:error, :catalog_too_large}

  defp all_pages(_token, _path, _params, %{page: page}, _acc, _opts)
       when page > @max_catalog_pages,
       do: {:error, :catalog_too_large}

  defp all_pages(token, path, params, number, acc, opts) do
    with {:ok, result} <- page(token, path, params, number, opts) do
      acc = [result.items | acc]

      case result.next_page do
        nil -> {:ok, acc |> Enum.reverse() |> List.flatten()}
        next -> all_pages(token, path, params, next, acc, opts)
      end
    end
  end

  @doc false
  def get(token, path, params, opts) do
    with true <- valid_token?(token),
         {:ok, destination} <- destination(opts) do
      http = Keyword.get(opts, :http, HTTP)
      suffix = if params == [], do: "", else: "?" <> URI.encode_query(params)

      headers = [
        {"accept", "application/vnd.github+json"},
        {"x-github-api-version", "2022-11-28"},
        {"authorization", "Bearer " <> token},
        {"user-agent", "Samgita-GitHub"}
      ]

      case http.request(:get, destination.api_url <> path <> suffix, headers, nil,
             destination: destination
           ) do
        {:ok, %{status: status, headers: headers, body: body}}
        when is_integer(status) and is_list(headers) and is_binary(body) ->
          if path == "/user" and status == 401, do: log_account_rejection(body)

          status
          |> Client.read_response(headers, body, now(opts))
          |> response(now(opts))

        _ ->
          {:error, :unavailable}
      end
    else
      false -> {:error, :invalid_token}
      {:error, %Failure{code: :unapproved_destination}} -> {:error, :unapproved_destination}
      {:error, _} -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp log_account_rejection(body) do
    reason =
      case Jason.decode(body) do
        {:ok, %{"message" => "Bad credentials"}} -> :bad_credentials
        {:ok, %{"message" => "Requires authentication"}} -> :requires_authentication
        _ -> :unauthorized
      end

    Logger.warning("GitHub GET /user returned HTTP 401 (#{reason})")
  end

  defp response({:ok, _, _} = result, _now), do: result

  defp response({:error, %Failure{class: :rate_limited, retry_after: delay}}, now),
    do: {:error, {:rate_limited, now + delay}}

  defp response({:error, %Failure{code: :rate_limit_recovery_required, retry_after: delay}}, now)
       when is_integer(delay) and delay > 0,
       do: {:error, {:rate_limited, now + delay}}

  defp response({:error, %Failure{class: :authentication}}, _now), do: {:error, :invalid_token}
  defp response({:error, %Failure{code: :resource_unavailable}}, _now), do: {:error, :not_found}
  defp response({:error, %Failure{class: :permission}}, _now), do: {:error, :forbidden}
  defp response({:error, %Failure{class: :retryable}}, _now), do: {:error, :unavailable}
  defp response({:error, %Failure{code: code}}, _now), do: {:error, code}

  defp destination(opts) do
    case Keyword.fetch(opts, :destination) do
      {:ok, destination} -> {:ok, destination}
      :error -> HTTP.resolve("github.com")
    end
  end

  defp next_page(headers, path, current, opts) do
    link =
      Enum.find_value(headers, fn {key, value} -> if String.downcase(key) == "link", do: value end)

    case Regex.scan(~r/<([^>]+)>\s*;\s*rel="next"/, link || "") do
      [] -> {:ok, nil}
      [[_, next]] -> validate_next(next, path, current, opts)
      _ -> {:error, :invalid_pagination}
    end
  end

  defp validate_next(next, path, current, opts) do
    with {:ok, destination} <- destination(opts),
         expected = URI.parse(destination.api_url <> path),
         actual = URI.parse(next),
         true <- %{actual | query: nil, path: expected.path} == %{expected | query: nil},
         true <- actual.path in pagination_paths(expected.path, destination, opts),
         params = URI.decode_query(actual.query || ""),
         {number, ""} <- Integer.parse(params["page"] || ""),
         true <- number == current + 1 && number <= 1_000_000,
         true <-
           Map.drop(params, ["page", "after"]) ==
             Map.drop(URI.decode_query(expected.query), ["page", "after"]),
         {:ok, position} <- page_position(number, Map.fetch(params, "after")) do
      {:ok, position}
    else
      _ -> {:error, :invalid_pagination}
    end
  end

  defp page_position(number, :error), do: {:ok, number}

  defp page_position(number, {:ok, after_cursor})
       when is_binary(after_cursor) and after_cursor != "",
       do: {:ok, %{page: number, after: after_cursor}}

  defp page_position(_, _), do: {:error, :invalid_pagination}

  defp pagination_paths(path, destination, opts) do
    case Keyword.get(opts, :repository) do
      %{id: id, owner: owner, name: name} when is_integer(id) and id > 0 ->
        aliases =
          Enum.flat_map(["issues", "pulls"], fn resource ->
            named = URI.parse(destination.api_url <> "/repos/#{owner}/#{name}/#{resource}").path
            numeric = URI.parse(destination.api_url <> "/repositories/#{id}/#{resource}").path
            if path == named, do: [numeric], else: []
          end)

        [path | aliases]

      _ ->
        [path]
    end
  end

  defp owner(%{"id" => id, "login" => login})
       when is_integer(id) and id > 0 and is_binary(login) do
    if Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9_-]{0,99}\z/, login),
      do: {:ok, %{id: id, login: login}},
      else: {:error, :invalid_response}
  end

  defp owner(_), do: {:error, :invalid_response}

  defp membership_owner(%{"organization" => organization}), do: owner(organization)
  defp membership_owner(_), do: {:error, :invalid_response}

  defp repository(%{"id" => id, "owner" => raw_owner, "name" => name})
       when is_integer(id) and id > 0 and is_binary(name) do
    with {:ok, owner} <- owner(raw_owner),
         true <- Regex.match?(~r/\A[A-Za-z0-9_.-]{1,100}\z/, name) && name not in [".", ".."] do
      {:ok, %{id: id, owner_id: owner.id, owner: owner.login, name: name}}
    else
      _ -> {:error, :invalid_response}
    end
  end

  defp repository(_), do: {:error, :invalid_response}

  defp map_valid(items, mapper) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case mapper.(item) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
