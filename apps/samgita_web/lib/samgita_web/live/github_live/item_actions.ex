defmodule SamgitaWeb.GitHubLive.ItemActions do
  @moduledoc "Shared operator actions and feedback for local GitHub item tables."
  import Phoenix.Component, only: [assign: 2, update: 3]
  use Gettext, backend: SamgitaWeb.Gettext
  alias Samgita.GitHub.PatActions

  @row_actions %{
    "close_issue" => :close_issue,
    "close_pull" => :close_pull,
    "approve_pull" => :approve_pull,
    "merge_pull" => :merge_pull,
    "rebase_pull" => :rebase_pull
  }

  def reset(socket) do
    assign(socket, action_jobs: %{}, action_status: nil, action_error: nil, closed_issue: nil)
  end

  def handle_row(socket, connection, kind, rows, params) do
    action = @row_actions[params["action"]]
    repository_id = positive_id(params["repository-id"])
    number = positive_id(params["number"])

    item =
      if action in table_actions(kind) do
        Enum.find(rows, &(&1.repository_id == repository_id && &1.number == number))
      end

    cond do
      is_nil(item) ->
        assign(socket,
          action_error: gettext("This item is no longer on the page. Sync and try again."),
          action_status: nil
        )

      revision_action?(action) && params["head-sha"] != Map.get(item, :head_sha) ->
        assign(socket,
          action_status: nil,
          action_error: action_failure(action, number, :head_changed)
        )

      true ->
        sha = if revision_action?(action), do: params["head-sha"]
        queue(socket, connection, repository_id, action, number, sha)
    end
  end

  def reopen_closed(socket, connection) do
    case socket.assigns.closed_issue do
      %{repository_id: id, number: number} ->
        queue(socket, connection, id, :reopen_issue, number, nil)

      nil ->
        socket
    end
  end

  def queue(socket, nil, _repository_id, _action, _number, _sha), do: socket

  def queue(socket, connection, repository_id, action, number, sha) do
    if pending?(socket.assigns.action_jobs, repository_id, action_kind(action), number) do
      socket
    else
      case PatActions.request(connection, repository_id, action, number, sha) do
        {:ok, job_id} ->
          job = %{repository_id: repository_id, action: action, number: number}

          socket
          |> update(:action_jobs, &Map.put(&1, job_id, job))
          |> assign(
            action_status:
              gettext("%{action} queued for %{item}.",
                action: action_label(action),
                item: action_item(action, number)
              ),
            action_error: nil
          )

        {:error, reason} ->
          assign(socket,
            action_status: nil,
            action_error: action_failure(action, number, reason)
          )
      end
    end
  end

  def finish(socket, {:github_pat_action, repository_id, job_id, action, number, outcome}) do
    expected = %{repository_id: repository_id, action: action, number: number}

    if socket.assigns.action_jobs[job_id] == expected do
      socket = update(socket, :action_jobs, &Map.delete(&1, job_id))
      {:ok, action_result(socket, repository_id, action, number, outcome)}
    else
      :ignore
    end
  end

  def pending?(jobs, repository_id, kind, number) do
    Enum.any?(jobs, fn {_id, job} ->
      job.repository_id == repository_id && job.number == number &&
        action_kind(job.action) == kind
    end)
  end

  def table_actions(:issues), do: [:close_issue]
  def table_actions(:pulls), do: [:close_pull, :approve_pull, :merge_pull, :rebase_pull]
  def table_actions(_), do: []

  def revision_action?(action), do: action in [:approve_pull, :merge_pull, :rebase_pull]

  def accessible_name(action, number) do
    gettext("%{action} %{item}",
      action: action_label(action),
      item: action_item(action, number)
    )
  end

  def error_message(code) when code in [:forbidden, :invalid_token, :unreadable_token],
    do:
      gettext(
        "This PAT cannot complete the operation. Check its GitHub access or replace it in Settings."
      )

  def error_message(code) when code in [:invalid_sha, :head_changed],
    do: gettext("The pull request head is unavailable or has changed. Sync before trying again.")

  def error_message(:merge_blocked),
    do:
      gettext(
        "GitHub cannot merge this pull request. Check its merge requirements and conflicts."
      )

  def error_message(:validation_failed),
    do: gettext("GitHub could not apply the operation. Check the item on GitHub, then sync.")

  def error_message(:wrong_kind), do: gettext("That number belongs to a different item type.")

  def error_message(:not_open),
    do: gettext("This item is no longer open. Sync to update the list.")

  def error_message(:stale),
    do: gettext("The GitHub connection changed. Reload this page and try again.")

  def error_message(:rate_limited),
    do: gettext("GitHub is rate limiting requests. Try again after the current cooldown.")

  def error_message(:ambiguous),
    do:
      gettext("GitHub did not confirm the outcome. Sync and check the item before trying again.")

  def error_message(:not_found),
    do: gettext("GitHub could not find this item. Sync and check the repository.")

  def error_message(_), do: gettext("GitHub could not complete the request. Sync and try again.")

  defp action_result(socket, repository_id, :close_issue, number, :ok) do
    assign(socket,
      closed_issue: %{repository_id: repository_id, number: number},
      action_error: nil,
      action_status: gettext("Issue #%{number} closed.", number: number)
    )
  end

  defp action_result(socket, repository_id, :reopen_issue, number, :ok) do
    closed_issue = socket.assigns.closed_issue
    reopened = %{repository_id: repository_id, number: number}

    assign(socket,
      closed_issue: if(closed_issue == reopened, do: nil, else: closed_issue),
      action_error: nil,
      action_status: gettext("Issue #%{number} reopened.", number: number)
    )
  end

  defp action_result(socket, _repository_id, :close_pull, number, :ok) do
    assign(socket,
      action_error: nil,
      action_status: gettext("Pull request #%{number} closed.", number: number)
    )
  end

  defp action_result(socket, _repository_id, action, number, :ok) do
    assign(socket,
      action_error: nil,
      action_status:
        gettext("%{action} completed for pull request #%{number}.",
          action: action_label(action),
          number: number
        )
    )
  end

  defp action_result(socket, _repository_id, action, number, {:error, reason}),
    do: assign(socket, action_status: nil, action_error: action_failure(action, number, reason))

  defp action_failure(action, number, reason) do
    gettext("Could not %{action} %{item}. %{reason}",
      action: String.downcase(action_label(action)),
      item: action_item(action, number),
      reason: error_message(reason)
    )
  end

  defp action_kind(action) when action in [:close_issue, :reopen_issue], do: :issues
  defp action_kind(_), do: :pulls

  defp action_label(:close_issue), do: gettext("Close")
  defp action_label(:reopen_issue), do: gettext("Reopen")
  defp action_label(:close_pull), do: gettext("Close")
  defp action_label(:approve_pull), do: gettext("Approve")
  defp action_label(:merge_pull), do: gettext("Merge")
  defp action_label(:rebase_pull), do: gettext("Rebase and merge")

  defp action_item(action, number) when action in [:close_issue, :reopen_issue],
    do: gettext("issue #%{number}", number: number)

  defp action_item(_action, number), do: gettext("pull request #%{number}", number: number)

  defp positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> nil
    end
  end

  defp positive_id(_), do: nil
end
