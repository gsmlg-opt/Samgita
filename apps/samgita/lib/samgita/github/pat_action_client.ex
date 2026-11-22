defmodule Samgita.GitHub.PatActionClient do
  @moduledoc "Prepares explicit GitHub item actions and sends each mutation once."
  alias Samgita.GitHub.{HTTP, PatClient, PatFeed}

  def prepare(token, selected, action, number, expected_sha, opts \\ []) do
    kind = if action in [:close_issue, :reopen_issue], do: "issue", else: "pull_request"
    resource = if kind == "issue", do: "issues", else: "pulls"

    with {:ok, repository} <- PatClient.repository(token, selected.id, opts),
         :ok <- owner(repository, selected),
         {:ok, raw, _headers} <-
           PatClient.get(
             token,
             "/repos/#{repository.owner}/#{repository.name}/#{resource}/#{number}",
             [],
             opts
           ),
         {:ok, item} <- item(raw, repository, kind, number),
         :ok <- action_head(action, item, expected_sha),
         {:ok, ^repository} <- PatClient.repository(token, selected.id, opts) do
      {:ok,
       %{
         repository: repository,
         item: item,
         action: action,
         number: number,
         expected_sha: expected_sha
       }}
    else
      {:ok, _changed} -> {:error, :repository_changed}
      error -> error
    end
  end

  def execute(token, prepared, opts \\ []) do
    if already_done?(prepared) do
      {:ok, prepared.item}
    else
      write(token, prepared, opts)
    end
  end

  defp owner(current, selected) do
    required = Map.get(selected, :required_owner_id)

    if is_nil(required) || current.owner_id == required,
      do: :ok,
      else: {:error, :repository_changed}
  end

  defp action_head(action, item, expected)
       when action in [:approve_pull, :merge_pull, :rebase_pull] do
    cond do
      item.state != "open" -> {:error, :not_open}
      item.head_sha != expected -> {:error, :head_changed}
      true -> :ok
    end
  end

  defp action_head(_, _, _), do: :ok

  defp already_done?(%{action: :reopen_issue, item: %{state: "open"}}), do: true

  defp already_done?(%{action: action, item: %{state: "closed"}})
       when action in [:close_issue, :close_pull],
       do: true

  defp already_done?(%{action: :close_pull, item: %{state: "merged"}}), do: true
  defp already_done?(_), do: false

  defp write(token, prepared, opts) do
    destination =
      case Keyword.fetch(opts, :destination) do
        {:ok, destination} -> {:ok, destination}
        :error -> HTTP.resolve("github.com")
      end

    with {:ok, destination} <- destination do
      transport = Keyword.get(opts, :http, HTTP)

      headers = [
        {"accept", "application/vnd.github+json"},
        {"content-type", "application/json"},
        {"x-github-api-version", "2022-11-28"},
        {"authorization", "Bearer " <> token},
        {"user-agent", "Samgita-GitHub"}
      ]

      transport.pat_action(
        prepared.action,
        prepared.repository,
        prepared.number,
        headers,
        Jason.encode!(payload(prepared)),
        destination: destination
      )
      |> response(prepared, opts)
    else
      _ -> {:error, :unapproved_destination}
    end
  rescue
    _ -> {:error, :ambiguous}
  catch
    _, _ -> {:error, :ambiguous}
  end

  defp payload(%{action: :reopen_issue}), do: %{state: "open"}

  defp payload(%{action: action}) when action in [:close_issue, :close_pull],
    do: %{state: "closed"}

  defp payload(%{action: :approve_pull, expected_sha: sha}),
    do: %{event: "APPROVE", commit_id: sha}

  defp payload(%{action: :merge_pull, expected_sha: sha}), do: %{sha: sha, merge_method: "merge"}

  defp payload(%{action: :rebase_pull, expected_sha: sha}),
    do: %{sha: sha, merge_method: "rebase"}

  defp response({:ok, %{status: status, body: body}}, prepared, _opts) when status in 200..299 do
    case Jason.decode(body) do
      {:ok, value} -> completed(prepared, value)
      _ -> {:error, :ambiguous}
    end
  end

  defp response({:ok, %{status: status, headers: headers, body: body}}, _prepared, opts) do
    case status do
      401 ->
        {:error, :invalid_token}

      404 ->
        {:error, :not_found}

      405 ->
        {:error, :merge_blocked}

      409 ->
        {:error, :head_changed}

      422 ->
        {:error, :validation_failed}

      value when value in [403, 429] ->
        case Samgita.GitHub.Client.read_response(status, headers, body, PatClient.now(opts)) do
          {:error, %Samgita.GitHub.Failure{class: :rate_limited, retry_after: delay}} ->
            {:error, {:rate_limited, PatClient.now(opts) + delay}}

          {:error,
           %Samgita.GitHub.Failure{code: :rate_limit_recovery_required, retry_after: delay}}
          when is_integer(delay) and delay > 0 ->
            {:error, {:rate_limited, PatClient.now(opts) + delay}}

          _ ->
            {:error, :forbidden}
        end

      _ ->
        {:error, :ambiguous}
    end
  end

  defp response(_, _, _), do: {:error, :ambiguous}

  defp completed(%{action: action} = prepared, %{"merged" => true})
       when action in [:merge_pull, :rebase_pull],
       do: {:ok, %{prepared.item | state: "merged"}}

  defp completed(%{action: action}, %{"merged" => false})
       when action in [:merge_pull, :rebase_pull],
       do: {:error, :merge_blocked}

  defp completed(
         %{action: :approve_pull, expected_sha: sha} = prepared,
         %{"state" => state, "commit_id" => sha}
       )
       when state in ["APPROVED", "approved"],
       do: {:ok, prepared.item}

  defp completed(%{action: action} = prepared, raw)
       when action in [:close_issue, :reopen_issue, :close_pull] do
    expected = if action == :reopen_issue, do: "open", else: "closed"

    case item(raw, prepared.repository, prepared.item.kind, prepared.number) do
      {:ok, %{state: ^expected} = item} -> {:ok, item}
      {:ok, %{state: "merged"} = item} when action == :close_pull -> {:ok, item}
      _ -> {:error, :ambiguous}
    end
  end

  defp completed(_, _), do: {:error, :ambiguous}

  defp item(%{"number" => number} = raw, repository, kind, number) do
    correct_kind =
      if kind == "issue",
        do: !Map.has_key?(raw, "pull_request"),
        else: match?(%{"base" => %{"repo" => %{"id" => id}}} when id == repository.id, raw)

    resource = if kind == "issue", do: :issues, else: :pulls

    with true <- correct_kind,
         {:ok, item} <- PatFeed.normalize_item(raw, repository, resource) do
      {:ok, Map.put(item, :kind, kind)}
    else
      false -> {:error, :wrong_kind}
      error -> error
    end
  end

  defp item(_, _, _, _), do: {:error, :invalid_response}
end
