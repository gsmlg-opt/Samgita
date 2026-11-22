defmodule Samgita.GitHub.PatDashboard do
  @moduledoc "Paginated open-item counts and lists for the operator's selected GitHub repositories."
  import Ecto.Query
  alias Samgita.Domain.{GitHubPatItem, GitHubPatRepositorySync}
  alias Samgita.GitHub.Console
  alias Samgita.Repo

  @page_size 30

  def read(settings, tab, filters, page \\ 1) do
    # The shared lock gives counts, sync state and items the same view of a publication.
    case Console.with_settings(settings.version, fn current ->
           repositories =
             Enum.filter(current.repositories, fn r ->
               (is_nil(filters.owner_id) || r.owner_id == filters.owner_id) &&
                 (is_nil(filters.repository_id) || r.id == filters.repository_id)
             end)

           syncs = repository_syncs(current, repositories, filters.owner_id)
           ready = for {id, %{synced_at: time}} <- syncs, time != nil, do: id
           items = scoped_items(current.connection, ready)

           result =
             case tab do
               :overview ->
                 overview(repositories, syncs, items, page)

               type when type in [:issues, :pulls] ->
                 list(repositories, items, type, page)
             end

           Map.merge(result, %{
             pending_count: length(repositories) - length(ready),
             failed_count: Enum.count(syncs, fn {_, sync} -> !is_nil(sync.error_code) end)
           })
         end) do
      {:ok, data} ->
        data

      {:error, reason} when reason in [:disconnected, :stale] ->
        %{rows: [], page: 1, pages: 1, pending_count: 0, failed_count: 0}
    end
  end

  def repository(settings, repository_id, issue_page \\ 1, pull_page \\ 1) do
    case Console.with_settings(settings.version, fn current ->
           if repo = Enum.find(current.repositories, &(&1.id == repository_id)) do
             sync = repository_syncs(current, [repo], nil)[repo.id]
             ready = if sync && sync.synced_at, do: [repo.id], else: []
             items = scoped_items(current.connection, ready)

             %{
               repository: repo,
               sync: %{synced_at: sync && sync.synced_at, error_code: sync && sync.error_code},
               issues: list([repo], items, :issues, issue_page),
               pulls: list([repo], items, :pulls, pull_page)
             }
           end
         end) do
      {:ok, detail} -> detail
      {:error, reason} when reason in [:disconnected, :stale] -> nil
    end
  end

  defp repository_syncs(settings, repositories, owner_filter) do
    ids = Enum.map(repositories, & &1.id)
    required_owners = Map.new(repositories, &{&1.id, &1.owner_id})
    individual = MapSet.new(settings.repository_ids)

    from(s in GitHubPatRepositorySync,
      where:
        s.connection_id == ^settings.connection.id and
          s.credential_version == ^settings.connection.credential_version and
          s.repository_id in ^ids
    )
    |> Repo.all()
    |> Map.new(fn s ->
      required_owner =
        owner_filter ||
          unless(MapSet.member?(individual, s.repository_id),
            do: required_owners[s.repository_id]
          )

      # A directory refresh may expose a transfer before this repository's next sync.
      sync = if required_owner && s.owner_id != required_owner, do: %{s | synced_at: nil}, else: s
      {s.repository_id, sync}
    end)
  end

  defp scoped_items(connection, ready) do
    from i in GitHubPatItem,
      where:
        i.connection_id == ^connection.id and
          i.credential_version == ^connection.credential_version and
          i.repository_id in ^ready and i.state == "open"
  end

  defp overview(repositories, syncs, items, requested) do
    {page, pages, offset} = pagination(length(repositories), requested)
    visible = Enum.slice(repositories, offset, @page_size)
    ids = Enum.map(visible, & &1.id)

    counts =
      from(i in items,
        where: i.repository_id in ^ids,
        group_by: [i.repository_id, i.kind],
        select: {i.repository_id, i.kind, count()}
      )
      |> Repo.all()
      |> Map.new(fn {id, kind, count} -> {{id, kind}, count} end)

    rows =
      for repo <- visible do
        sync = syncs[repo.id]
        synced_at = sync && sync.synced_at

        %{
          repository: repo,
          synced_at: synced_at,
          error_code: sync && sync.error_code,
          issues_count: synced_at && Map.get(counts, {repo.id, "issue"}, 0),
          pulls_count: synced_at && Map.get(counts, {repo.id, "pull_request"}, 0)
        }
      end

    %{rows: rows, page: page, pages: pages}
  end

  defp list(repositories, items, tab, requested) do
    kind = if tab == :issues, do: "issue", else: "pull_request"
    query = from i in items, where: i.kind == ^kind

    total = Repo.aggregate(query, :count)
    {page, pages, offset} = pagination(total, requested)
    names = Map.new(repositories, &{&1.id, &1.owner <> "/" <> &1.name})

    rows =
      from(i in query,
        order_by: [desc: i.github_updated_at, desc: i.repository_id, desc: i.number],
        limit: @page_size,
        offset: ^offset
      )
      |> Repo.all()
      |> Enum.map(fn item ->
        item
        |> Map.take([
          :repository_id,
          :number,
          :title,
          :state,
          :author,
          :url,
          :issue_type,
          :labels,
          :label_colors,
          :head_sha
        ])
        |> Map.merge(%{
          full_name: names[item.repository_id],
          updated_at: DateTime.to_iso8601(item.github_updated_at)
        })
      end)

    %{rows: rows, page: page, pages: pages, total: total}
  end

  defp pagination(total, requested) do
    pages = max(div(total + @page_size - 1, @page_size), 1)
    page = requested |> max(1) |> min(pages)
    {page, pages, (page - 1) * @page_size}
  end
end
