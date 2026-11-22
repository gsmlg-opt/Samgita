defmodule Samgita.GitHub.PatFeed do
  @moduledoc "Bounded merge of repository pages ordered by the most recently updated issue or PR."
  alias Samgita.GitHub.PatClient

  @page_size 30
  @request_budget 100

  def fetch(token, repositories, %{kind: kind}, cursor, opts)
      when kind in [:issues, :pulls] do
    filters = %{kind: kind, state: :open}
    signature = signature(token, repositories, filters)

    with {:ok, cursor} <- cursor(cursor, repositories, signature),
         :ok <- ready(cursor.retry_at, opts) do
      merge(token, filters, %{cursor | retry_at: nil}, [], @request_budget, opts)
    else
      {:cooldown, retry_at} -> {:ok, result([], cursor, retry_at)}
      {:error, _} = error -> error
    end
  end

  def fetch(_, _, _, _, _), do: {:error, :invalid_request}

  @doc false
  def normalize(raw, repository, kind) do
    with {:ok, items} <- items(raw, repository, kind) do
      {:ok, Enum.map(items, &Map.delete(&1, :order))}
    end
  end

  defp cursor(nil, repositories, signature) do
    streams =
      repositories
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.id)
      |> Enum.map(
        &%{
          id: &1.id,
          repository: &1,
          required_owner_id: Map.get(&1, :required_owner_id),
          page: 1,
          buffer: [],
          done: false,
          seen: MapSet.new()
        }
      )

    {:ok, %{signature: signature, streams: streams, failed: %{}, retry_at: nil}}
  end

  defp cursor(%{signature: signature} = cursor, _, signature), do: {:ok, cursor}
  defp cursor(_, _, _), do: {:error, :stale_cursor}

  defp signature(token, repositories, filters) do
    scope = repositories |> Enum.map(&{&1.id, Map.get(&1, :required_owner_id)}) |> Enum.sort()

    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({token, scope, filters})
    )
  end

  defp ready(nil, _), do: :ok

  defp ready(retry_at, opts) do
    if retry_at > PatClient.now(opts), do: {:cooldown, retry_at}, else: :ok
  end

  defp merge(_token, _filters, cursor, items, _budget, _opts) when length(items) == @page_size,
    do: {:ok, result(items, cursor, nil)}

  defp merge(token, filters, cursor, items, budget, opts) do
    case fill_heads(token, filters, cursor, budget, opts) do
      {:ok, cursor, remaining} ->
        case newest(cursor.streams) do
          nil ->
            {:ok, result(items, cursor, nil)}

          stream ->
            [item | rest] = stream.buffer
            stream = %{stream | buffer: rest, seen: MapSet.put(stream.seen, item.number)}
            cursor = %{cursor | streams: replace_stream(cursor.streams, stream)}
            merge(token, filters, cursor, [item | items], remaining, opts)
        end

      {:pending, cursor} ->
        {:ok, result(items, cursor, nil)}

      {:cooldown, cursor, retry_at} ->
        {:ok, result(items, cursor, retry_at)}

      {:error, _} = error ->
        error
    end
  end

  defp fill_heads(token, filters, cursor, budget, opts) do
    case Enum.find(cursor.streams, &(&1.buffer == [] && !&1.done)) do
      nil ->
        {:ok, cursor, budget}

      _ when budget < 2 ->
        {:pending, cursor}

      stream ->
        fill_stream(token, filters, cursor, stream, budget, opts)
    end
  end

  defp fill_stream(token, filters, cursor, stream, budget, opts) do
    case load_page(token, stream, filters, opts) do
      {:ok, stream} ->
        cursor = %{cursor | streams: replace_stream(cursor.streams, stream)}
        fill_heads(token, filters, cursor, budget - 2, opts)

      {:error, {:rate_limited, retry_at}} ->
        {:cooldown, %{cursor | retry_at: retry_at}, retry_at}

      {:error, reason} = error
      when reason in [:invalid_token, :rate_limit_recovery_required, :unapproved_destination] ->
        error

      {:error, reason} ->
        cursor = %{
          cursor
          | streams: replace_stream(cursor.streams, %{stream | buffer: [], done: true}),
            failed: Map.put(cursor.failed, stream.id, reason)
        }

        fill_heads(token, filters, cursor, budget - 2, opts)
    end
  end

  defp load_page(token, stream, filters, opts) do
    with {:ok, repository} <- PatClient.repository(token, stream.id, opts),
         true <-
           is_nil(stream.required_owner_id) or repository.owner_id == stream.required_owner_id,
         full_name = repository.owner <> "/" <> repository.name,
         path = "/repos/" <> full_name <> "/" <> Atom.to_string(filters.kind),
         params = [state: Atom.to_string(filters.state), sort: "updated", direction: "desc"],
         {:ok, page} <-
           PatClient.page(
             token,
             path,
             params,
             stream.page,
             Keyword.put(opts, :repository, repository)
           ),
         {:ok, items} <- items(page.items, repository, filters.kind) do
      buffer =
        items
        |> Enum.reject(&MapSet.member?(stream.seen, &1.number))
        |> Enum.sort_by(& &1.order, :desc)

      {:ok,
       %{
         stream
         | repository: repository,
           buffer: buffer,
           page: page.next_page,
           done: is_nil(page.next_page)
       }}
    else
      false -> {:error, :repository_changed}
      error -> error
    end
  end

  defp newest(streams) do
    streams
    |> Enum.reject(&(&1.buffer == []))
    |> Enum.max_by(fn stream -> hd(stream.buffer).order end, fn -> nil end)
  end

  defp replace_stream(streams, changed),
    do: Enum.map(streams, fn stream -> if stream.id == changed.id, do: changed, else: stream end)

  defp result(reversed_items, cursor, retry_at) do
    complete = Enum.all?(cursor.streams, &(&1.done && &1.buffer == []))

    %{
      items: reversed_items |> Enum.reverse() |> Enum.map(&Map.delete(&1, :order)),
      repositories: Enum.map(cursor.streams, & &1.repository),
      cursor: if(complete, do: nil, else: cursor),
      failed: cursor.failed,
      retry_at: retry_at
    }
  end

  defp items(raw, repository, kind) do
    raw
    |> Enum.reject(fn item ->
      is_map(item) &&
        (item["state"] == "closed" ||
           (kind == :pulls && item["merged_at"] != nil) ||
           (kind == :issues && Map.has_key?(item, "pull_request")))
    end)
    |> Enum.reduce_while({:ok, []}, fn raw_item, {:ok, acc} ->
      case normalize_item(raw_item, repository, kind) do
        {:ok, item} -> {:cont, {:ok, [item | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @doc false
  def normalize_item(
        %{"number" => number, "title" => title, "state" => state, "updated_at" => updated_at} =
          raw,
        repository,
        kind
      )
      when is_integer(number) and number > 0 and is_binary(title) and
             state in ["open", "closed"] and is_binary(updated_at) do
    with {:ok, datetime, _} <- DateTime.from_iso8601(updated_at),
         author when is_binary(author) <- author(raw["user"]),
         labels when is_list(labels) <- raw["labels"] || [],
         true <- repository_matches?(raw["base"], repository) do
      full_name = repository.owner <> "/" <> repository.name
      path = if kind == :pulls, do: "pull", else: "issues"

      {:ok,
       %{
         repository_id: repository.id,
         full_name: full_name,
         number: number,
         title: title,
         state: if(kind == :pulls && raw["merged_at"] != nil, do: "merged", else: state),
         author: author,
         issue_type: if(kind == :issues, do: name(raw["type"])),
         labels: for(label <- labels, label_name = name(label), do: label_name),
         label_colors: label_colors(labels),
         head_sha: if(kind == :pulls, do: head_sha(raw["head"])),
         updated_at: DateTime.to_iso8601(datetime),
         url: "https://github.com/#{full_name}/#{path}/#{number}",
         order: {DateTime.to_unix(datetime, :microsecond), repository.id, number}
       }}
    else
      _ -> {:error, :invalid_response}
    end
  end

  def normalize_item(_, _, _), do: {:error, :invalid_response}

  defp label_colors(labels) do
    for %{"name" => name, "color" => color} <- labels,
        is_binary(name) and is_binary(color),
        Regex.match?(~r/\A[0-9a-fA-F]{6}\z/, color),
        into: %{},
        do: {name, String.downcase(color)}
  end

  defp name(%{"name" => name}) when is_binary(name), do: name
  defp name(name) when is_binary(name), do: name
  defp name(_), do: nil

  defp head_sha(%{"sha" => sha}) when is_binary(sha), do: sha
  defp head_sha(_), do: nil

  defp author(nil), do: "Deleted user"
  defp author(%{"login" => login}) when is_binary(login), do: login
  defp author(_), do: nil

  defp repository_matches?(nil, _), do: true
  defp repository_matches?(%{"repo" => %{"id" => id}}, %{id: id}), do: true
  defp repository_matches?(_, _), do: false
end
