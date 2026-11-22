defmodule Samgita.GitHub.PatActions do
  @moduledoc "Explicit operator Issue and PR mutations with a durable one-send marker."
  import Ecto.Query
  import Ecto.Changeset, only: [change: 2]
  alias Samgita.Domain.GitHubPatItem
  alias Samgita.GitHub.{Console, PatActionClient, PatCipher, PatSync}
  alias Samgita.Repo
  alias Samgita.Workers.GitHubPatActionWorker

  @actions [:close_issue, :reopen_issue, :close_pull, :approve_pull, :merge_pull, :rebase_pull]
  @errors ~w(invalid_action invalid_number invalid_sha stale not_found wrong_kind not_open head_changed merge_blocked validation_failed forbidden invalid_token rate_limited unavailable ambiguous enqueue_failed state_update_failed repository_changed invalid_response unapproved_destination storage_key_unavailable unreadable_token)a
  @topic "github:actions"

  def subscribe, do: Phoenix.PubSub.subscribe(Samgita.PubSub, @topic)

  def request(connection, repository_id, action, number, expected_sha \\ nil) do
    with :ok <- arguments(repository_id, action, number, expected_sha) do
      Repo.transact(fn ->
        with {:ok, target} <-
               Console.sync_target(
                 connection.id,
                 connection.credential_version,
                 repository_id,
                 :update
               ),
             :ok <- local_item(target, action, number, expected_sha),
             {:ok, job} <-
               Styx.insert(
                 GitHubPatActionWorker.new(%{
                   "connection_id" => connection.id,
                   "credential_version" => connection.credential_version,
                   "repository_id" => repository_id,
                   "action" => Atom.to_string(action),
                   "number" => number,
                   "expected_sha" => expected_sha
                 }),
                 retry: false
               ) do
          {:ok, job.id}
        else
          {:error, %Ecto.Changeset{}} -> {:error, :enqueue_failed}
          error -> error
        end
      end)
    end
  rescue
    _ -> {:error, :enqueue_failed}
  end

  def perform(%Styx.Job{} = job) do
    result =
      case load(job) do
        {:ok, {:done, {:error, :ambiguous}}} -> finish(job, {:error, :ambiguous}, nil)
        {:ok, {:done, result}} -> result
        {:ok, target} -> run(job, target)
        {:error, reason} -> finish(job, {:error, reason}, nil)
      end

    notify(job, result)
  rescue
    _ -> notify(job, {:error, :state_update_failed})
  catch
    _, _ -> notify(job, {:error, :state_update_failed})
  end

  defp notify(job, result) do
    action = action(job.args["action"])

    message =
      {:github_pat_action, job.args["repository_id"], job.id, action, job.args["number"], result}

    Console.broadcast_repository(job.args["repository_id"], message)
    Phoenix.PubSub.broadcast(Samgita.PubSub, @topic, message)

    if result == :ok,
      do: Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_feed_changed)

    case result do
      :ok -> :ok
      {:error, reason} -> {:cancel, reason}
    end
  end

  defp load(job) do
    Repo.transact(fn ->
      with {:ok, target} <- target(job),
           current <- locked_job(job) do
        case previous(current) do
          {:done, result} ->
            {:ok, {:done, result}}

          :fresh ->
            with :ok <- cooldown(target.connection),
                 :ok <-
                   local_item(
                     target,
                     action(job.args["action"]),
                     job.args["number"],
                     job.args["expected_sha"]
                   ),
                 do: {:ok, target}
        end
      end
    end)
  end

  defp run(job, target) do
    prepared =
      with {:ok, token} <-
             PatCipher.open(
               target.connection.ciphertext,
               target.connection.id,
               target.connection.github_id
             ),
           {:ok, prepared} <- prepare(token, target.repository, job) do
        {:ok, token, prepared}
      end

    case prepared do
      {:ok, token, prepared} ->
        case begin_action(job, prepared) do
          {:ok, :began} -> finish(job, execute(token, prepared), prepared)
          {:ok, {:done, result}} -> result
          {:error, reason} -> finish(job, {:error, reason}, nil)
        end

      {:error, reason} ->
        finish(job, {:error, reason}, nil)
    end
  end

  defp prepare(token, repository, job) do
    client().prepare(
      token,
      repository,
      action(job.args["action"]),
      job.args["number"],
      job.args["expected_sha"]
    )
  rescue
    _ -> {:error, :unavailable}
  catch
    _, _ -> {:error, :unavailable}
  end

  defp execute(token, prepared) do
    client().execute(token, prepared)
  rescue
    _ -> {:error, :ambiguous}
  catch
    _, _ -> {:error, :ambiguous}
  end

  defp begin_action(job, prepared) do
    Repo.transact(fn ->
      with {:ok, target} <- target(job),
           current <- locked_job(job) do
        case previous(current) do
          {:done, result} ->
            {:ok, {:done, result}}

          :fresh ->
            with :ok <-
                   local_item(target, prepared.action, prepared.number, prepared.expected_sha),
                 true <- repository_current?(target, prepared.repository),
                 :ok <- cooldown(target.connection),
                 {:ok, _} <-
                   Repo.update(
                     change(current, meta: Map.put(current.meta, "pat_action_began", true))
                   ) do
              {:ok, :began}
            else
              false -> {:error, :stale}
              error -> error
            end
        end
      end
    end)
  end

  defp finish(job, outcome, prepared) do
    normalized = normalize(outcome)

    result =
      Repo.transact(fn ->
        target_result = target(job)
        current = locked_job(job)

        if current.meta["pat_action_result"] == "ok" do
          {:ok, :ok}
        else
          with :ok <- apply_outcome(target_result, normalized, prepared),
               {:ok, _} <-
                 Repo.update(
                   change(current,
                     meta: Map.put(current.meta, "pat_action_result", stored(normalized))
                   )
                 ) do
            {:ok, feedback(normalized)}
          end
        end
      end)

    case result do
      {:ok, result} -> result
      {:error, _} -> {:error, :state_update_failed}
    end
  end

  defp apply_outcome({:ok, target}, {:ok, _item}, %{action: :approve_pull} = prepared) do
    if repository_current?(target, prepared.repository),
      do: PatSync.request_repository(target.connection, target.repository.id, :replace),
      else: {:error, :stale}
  end

  defp apply_outcome({:ok, target}, {:ok, item}, prepared) do
    if repository_current?(target, prepared.repository) do
      {:ok, date, _} = DateTime.from_iso8601(item.updated_at)

      row =
        Map.take(item, [
          :kind,
          :number,
          :title,
          :state,
          :author,
          :url,
          :head_sha,
          :issue_type,
          :labels
        ])

      row =
        Map.merge(row, %{
          connection_id: target.connection.id,
          credential_version: target.connection.credential_version,
          label_colors: Map.get(item, :label_colors) || %{},
          repository_id: target.repository.id,
          github_updated_at:
            DateTime.from_unix!(DateTime.to_unix(date, :microsecond), :microsecond)
        })

      row = preserve_merged(target, row)

      unless newer_issue?(row) do
        Repo.insert_all(GitHubPatItem, [row],
          on_conflict: {:replace_all_except, [:connection_id, :repository_id, :kind, :number]},
          conflict_target: [:connection_id, :repository_id, :kind, :number]
        )
      end

      PatSync.request_repository(target.connection, target.repository.id, :replace)
    else
      {:error, :stale}
    end
  end

  defp apply_outcome({:ok, target}, {:error, reason}, _prepared)
       when reason in [:ambiguous, :head_changed],
       do: PatSync.request_repository(target.connection, target.repository.id, :replace)

  defp apply_outcome({:ok, target}, {:error, {:rate_limited, until}}, _prepared) do
    case Repo.update(
           change(target.connection, retry_at: max(target.connection.retry_at || 0, until))
         ) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp apply_outcome({:error, _}, {:ok, _}, _), do: {:error, :stale}
  defp apply_outcome(_, _, _), do: :ok

  defp preserve_merged(target, %{kind: "pull_request", state: state} = row)
       when state != "merged" do
    merged? =
      Repo.exists?(
        from i in GitHubPatItem,
          where:
            i.connection_id == ^target.connection.id and
              i.credential_version == ^target.connection.credential_version and
              i.repository_id == ^target.repository.id and
              i.kind == "pull_request" and i.number == ^row.number and i.state == "merged"
      )

    if merged?, do: %{row | state: "merged"}, else: row
  end

  defp preserve_merged(_, row), do: row

  defp newer_issue?(%{kind: "issue"} = row) do
    Repo.exists?(
      from i in GitHubPatItem,
        where:
          i.connection_id == ^row.connection_id and
            i.credential_version == ^row.credential_version and
            i.repository_id == ^row.repository_id and
            i.kind == "issue" and i.number == ^row.number and
            i.github_updated_at > ^row.github_updated_at
    )
  end

  defp newer_issue?(_), do: false

  defp local_item(target, action, number, sha) do
    kind = if action in [:close_issue, :reopen_issue], do: "issue", else: "pull_request"

    row =
      Repo.get_by(GitHubPatItem,
        connection_id: target.connection.id,
        credential_version: target.connection.credential_version,
        repository_id: target.repository.id,
        kind: kind,
        number: number
      )

    other_kind = if kind == "issue", do: "pull_request", else: "issue"

    other =
      Repo.exists?(
        from i in GitHubPatItem,
          where:
            i.connection_id == ^target.connection.id and
              i.credential_version == ^target.connection.credential_version and
              i.repository_id == ^target.repository.id and
              i.kind == ^other_kind and i.number == ^number
      )

    cond do
      other ->
        {:error, :wrong_kind}

      action == :reopen_issue ->
        :ok

      is_nil(row) ->
        {:error, :not_found}

      row.state != "open" ->
        {:error, :not_open}

      action in [:approve_pull, :merge_pull, :rebase_pull] && row.head_sha != sha ->
        {:error, :head_changed}

      true ->
        :ok
    end
  end

  defp arguments(repository_id, action, number, sha) do
    cond do
      action not in @actions ->
        {:error, :invalid_action}

      !is_integer(repository_id) || repository_id <= 0 ||
          repository_id > 9_223_372_036_854_775_807 ->
        {:error, :invalid_number}

      !is_integer(number) || number <= 0 || number > 9_223_372_036_854_775_807 ->
        {:error, :invalid_number}

      action in [:approve_pull, :merge_pull, :rebase_pull] &&
          !(is_binary(sha) && Regex.match?(~r/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/, sha)) ->
        {:error, :invalid_sha}

      true ->
        :ok
    end
  end

  defp repository_current?(target, repository),
    do:
      target.repository.id == repository.id &&
        (is_nil(target.repository.required_owner_id) ||
           target.repository.required_owner_id == repository.owner_id)

  defp target(job),
    do:
      Console.sync_target(
        job.args["connection_id"],
        job.args["credential_version"],
        job.args["repository_id"],
        :update
      )

  defp locked_job(job),
    do: Repo.one!(from j in Styx.Job, where: j.id == ^job.id, lock: "FOR UPDATE")

  defp previous(%{meta: %{"pat_action_result" => "ok"}}), do: {:done, :ok}

  defp previous(%{meta: %{"pat_action_result" => code}}),
    do: {:done, {:error, Enum.find(@errors, :ambiguous, &(Atom.to_string(&1) == code))}}

  defp previous(%{meta: %{"pat_action_began" => true}}), do: {:done, {:error, :ambiguous}}
  defp previous(_), do: :fresh
  defp action(value), do: Enum.find(@actions, &(Atom.to_string(&1) == value))
  defp normalize({:ok, _} = result), do: result

  defp normalize({:error, {:rate_limited, until}}) when is_integer(until),
    do: {:error, {:rate_limited, until}}

  defp normalize({:error, reason}) when reason in @errors, do: {:error, reason}
  defp normalize(_), do: {:error, :ambiguous}
  defp feedback({:ok, _}), do: :ok
  defp feedback({:error, {:rate_limited, _}}), do: {:error, :rate_limited}
  defp feedback({:error, reason}), do: {:error, reason}
  defp stored({:ok, _}), do: "ok"
  defp stored({:error, {:rate_limited, _}}), do: "rate_limited"
  defp stored({:error, reason}), do: Atom.to_string(reason)

  defp cooldown(%{retry_at: until}) when is_integer(until),
    do: if(until > System.system_time(:second), do: {:error, :rate_limited}, else: :ok)

  defp cooldown(_), do: :ok
  defp client, do: Application.get_env(:samgita, :github_pat_action_client, PatActionClient)
end
