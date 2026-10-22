defmodule Samgita.GitHub.Payload do
  @moduledoc """
  Pure, allowlisted GitHub fact normalization. Text remains explicitly untrusted;
  neither webhook fields nor API snapshots confer routing or Task authority.
  """

  @events %{
    "issues" =>
      {"issue", "issue",
       ~w(opened edited deleted transferred pinned unpinned closed reopened assigned unassigned labeled unlabeled locked unlocked milestoned demilestoned typed untyped)},
    "issue_comment" => {"comment", "comment", ~w(created edited deleted)},
    "pull_request" =>
      {"pull_request", "pull_request",
       ~w(opened edited closed reopened assigned unassigned labeled unlabeled synchronize ready_for_review converted_to_draft locked unlocked review_requested review_request_removed enqueued dequeued auto_merge_enabled auto_merge_disabled milestoned demilestoned)},
    "check_run" => {"check_run", "check_run", ~w(created completed rerequested requested_action)},
    "check_suite" => {"check_suite", "check_suite", ~w(completed requested rerequested)},
    "workflow_run" => {"workflow_run", "workflow_run", ~w(requested in_progress completed)}
  }
  @kinds ~w(issue pull_request check_run check_suite workflow_run comment)
  @statuses ~w(requested queued pending waiting in_progress completed)
  @states ~w(open closed)
  @conclusions ~w(action_required cancelled failure neutral success skipped stale timed_out startup_failure)
  @marker "\n[truncated]"

  @doc "Normalizes supported webhook facts without trusting payload routing references."
  def normalize(event, payload) when is_binary(event) and is_map(payload) do
    case Map.fetch(@events, event) do
      {:ok, {kind, key, actions}} -> normalize_event(event, kind, key, actions, payload)
      :error -> {:unsupported, :unsupported_event}
    end
  end

  def normalize(_, _), do: {:error, :invalid_payload}

  defp normalize_event(event, kind, key, actions, payload) do
    with {:ok, action} <- text(payload["action"], 100),
         true <- action in actions,
         {:ok, installation_id} <- nested_id(payload["installation"]),
         {:ok, repository_id} <- nested_id(payload["repository"]),
         {:ok, result} <- object(kind, payload[key]),
         {:ok, facts} <- comment_parent(kind, payload, result.facts) do
      {:ok,
       %{
         event: event,
         action: action,
         installation_id: installation_id,
         repository_id: repository_id,
         kind: kind,
         resource_id: result.resource_id,
         occurred_at: result.external_updated_at,
         facts: facts,
         untrusted_input: result.untrusted_input
       }}
    else
      false -> {:unsupported, :unsupported_action}
      _ -> {:error, :invalid_payload}
    end
  end

  @doc "Normalizes a fetched current object. Its timestamp alone is not authoritative ordering."
  def object(kind, item) when kind in @kinds and is_map(item) do
    with {:ok, external_id} <- id(item["id"]),
         {:ok, resource_id} <- resource_id(kind, item, external_id),
         {:ok, updated_at} <- timestamp(item["updated_at"]),
         {:ok, facts} <- metadata(item),
         {:ok, untrusted} <- content(kind, item) do
      facts =
        facts
        |> Map.put("kind", kind)
        |> Map.put("resource_id", resource_id)
        |> Map.put("external_id", external_id)

      {:ok,
       %{
         kind: kind,
         resource_id: resource_id,
         external_updated_at: updated_at,
         facts: facts,
         untrusted_input: untrusted
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  def object(_, _), do: {:error, :invalid_payload}

  defp resource_id(kind, item, _) when kind in ["issue", "pull_request"],
    do: id(item["number"])

  defp resource_id(_, _, external_id), do: {:ok, external_id}

  defp comment_parent("comment", payload, facts) do
    with %{} = issue <- payload["issue"],
         {:ok, external_id} <- id(issue["id"]),
         {:ok, number} <- id(issue["number"]) do
      {:ok, facts |> Map.put("issue_external_id", external_id) |> Map.put("issue_number", number)}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp comment_parent(_, _, facts), do: {:ok, facts}

  defp metadata(item) do
    validators = [
      {"number", &id/1},
      {"status", &enum(&1, @statuses)},
      {"state", &enum(&1, @states)},
      {"state_reason", &enum(&1, ~w(completed not_planned reopened))},
      {"conclusion", &enum(&1, @conclusions)},
      {"merged", &boolean/1},
      {"draft", &boolean/1},
      {"merged_at", &iso_timestamp/1},
      {"head_sha", &sha/1},
      {"updated_at", &iso_timestamp/1},
      {"head", &git_ref/1},
      {"base", &git_ref/1}
    ]

    Enum.reduce_while(validators, {:ok, %{}}, fn {key, validate}, {:ok, facts} ->
      case item[key] do
        nil when key == "merged_at" ->
          safe = if Map.has_key?(item, key), do: Map.put(facts, key, nil), else: facts
          {:cont, {:ok, safe}}

        nil ->
          {:cont, {:ok, facts}}

        value ->
          case validate.(value) do
            {:ok, safe} -> {:cont, {:ok, Map.put(facts, key, safe)}}
            _ -> {:halt, {:error, :invalid_payload}}
          end
      end
    end)
  end

  defp content(kind, item) do
    fields =
      if kind == "comment",
        do: [{"comment", "body", 16_000}],
        else: [{"title", "title", 1_000}, {"body", "body", 16_000}]

    Enum.reduce_while(fields, {:ok, %{"trust" => "untrusted", "truncated" => %{}}}, fn
      {target, source, limit}, {:ok, result} ->
        case item[source] do
          nil ->
            {:cont, {:ok, result}}

          value ->
            case bounded_content(value, limit) do
              {:ok, safe, truncated?} ->
                result =
                  result |> Map.put(target, safe) |> put_in(["truncated", target], truncated?)

                {:cont, {:ok, result}}

              _ ->
                {:halt, {:error, :invalid_payload}}
            end
        end
    end)
  end

  defp bounded_content(value, limit) when is_binary(value) do
    cond do
      not String.valid?(value) or String.contains?(value, <<0>>) -> {:error, :invalid_payload}
      byte_size(value) <= limit -> {:ok, value, false}
      true -> {:ok, utf8_prefix(value, limit - byte_size(@marker)) <> @marker, true}
    end
  end

  defp bounded_content(_, _), do: {:error, :invalid_payload}

  defp utf8_prefix(value, bytes) do
    prefix = binary_part(value, 0, bytes)
    if String.valid?(prefix), do: prefix, else: utf8_prefix(value, bytes - 1)
  end

  defp text(value, limit)
       when is_binary(value) and byte_size(value) > 0 and byte_size(value) <= limit do
    if String.valid?(value) and not String.contains?(value, <<0>>),
      do: {:ok, value},
      else: {:error, :invalid_payload}
  end

  defp text(_, _), do: {:error, :invalid_payload}

  defp id(value) when is_integer(value) and value > 0, do: id(Integer.to_string(value))

  defp id(value) when is_binary(value) and byte_size(value) <= 20 do
    if Regex.match?(~r/\A[1-9][0-9]*\z/, value),
      do: {:ok, value},
      else: {:error, :invalid_payload}
  end

  defp id(_), do: {:error, :invalid_payload}

  defp nested_id(%{"id" => value}), do: id(value)
  defp nested_id(_), do: {:error, :invalid_payload}

  defp enum(value, allowed) do
    if value in allowed, do: {:ok, value}, else: {:error, :invalid_payload}
  end

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_), do: {:error, :invalid_payload}

  defp timestamp(nil), do: {:ok, nil}

  defp timestamp(value) when is_binary(value) and byte_size(value) <= 40 do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, datetime}
      _ -> {:error, :invalid_payload}
    end
  end

  defp timestamp(_), do: {:error, :invalid_payload}

  defp iso_timestamp(value) do
    with {:ok, datetime} <- timestamp(value), do: {:ok, DateTime.to_iso8601(datetime)}
  end

  defp sha(value) when is_binary(value) and byte_size(value) in [40, 64] do
    case Base.decode16(value, case: :mixed) do
      {:ok, _} -> {:ok, String.downcase(value)}
      :error -> {:error, :invalid_payload}
    end
  end

  defp sha(_), do: {:error, :invalid_payload}

  defp git_ref(value) when is_map(value) do
    with {:ok, ref} <- text(value["ref"], 255),
         false <- Regex.match?(~r/[\x00-\x20\x7f]/, ref),
         {:ok, head_sha} <- sha(value["sha"]) do
      {:ok, %{"ref" => ref, "sha" => head_sha}}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp git_ref(_), do: {:error, :invalid_payload}
end
