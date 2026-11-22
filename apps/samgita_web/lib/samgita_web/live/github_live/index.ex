defmodule SamgitaWeb.GitHubLive.Index do
  @moduledoc "Local GitHub repository counts, open issues and open pull requests."
  use SamgitaWeb, :live_view
  alias Samgita.GitHub.{Console, PatActions, PatDashboard, PatSync}
  alias SamgitaWeb.GitHubLive.{ItemActions, ItemTable}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Console.subscribe()
      PatActions.subscribe()
    end

    {:ok,
     socket
     |> ItemActions.reset()
     |> assign(
       page_title: "GitHub",
       tab: :overview,
       filters: default_filters(),
       rows: [],
       page: 1,
       pages: 1,
       pending_count: 0,
       failed_count: 0,
       sync_status: nil,
       sync_error: nil
     )
     |> load_settings()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = socket.assigns.live_action
    filters = parse_filters(params, socket.assigns.settings)

    {:noreply,
     socket
     |> assign(tab: tab, filters: filters)
     |> load_dashboard(positive_id(params["page"]) || 1)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    params =
      if params["_target"] == ["owner"], do: Map.put(params, "repository", ""), else: params

    filters = parse_filters(params, socket.assigns.settings)
    {:noreply, push_patch(socket, to: github_path(socket.assigns.tab, filters))}
  end

  def handle_event("repository_action", params, socket) do
    %{rows: rows, tab: tab, settings: settings} = socket.assigns
    {:noreply, ItemActions.handle_row(socket, settings.connection, tab, rows, params)}
  end

  def handle_event("reopen_closed_issue", _params, socket) do
    %{closed_issue: issue, settings: settings, filters: filters, tab: tab} = socket.assigns

    if tab == :issues && closed_repository(issue, settings, filters),
      do: {:noreply, ItemActions.reopen_closed(socket, settings.connection)},
      else: {:noreply, socket}
  end

  def handle_event("sync", _params, socket) do
    case PatSync.request() do
      :ok ->
        {:noreply, assign(socket, sync_status: gettext("Sync queued."), sync_error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, sync_status: nil, sync_error: error_message(reason))}
    end
  end

  @impl true
  def handle_info(message, socket)
      when message in [:github_console_changed, :github_catalog_changed, :github_feed_changed] do
    socket = load_settings(socket)
    filters = normalize_filters(socket.assigns.filters, socket.assigns.settings)
    {:noreply, socket |> assign(filters: filters) |> load_dashboard(socket.assigns.page)}
  end

  def handle_info({:github_pat_action, _, _, _, _, _} = message, socket) do
    case ItemActions.finish(socket, message) do
      {:ok, socket} -> {:noreply, load_dashboard(socket, socket.assigns.page)}
      :ignore -> {:noreply, socket}
    end
  end

  defp load_settings(socket) do
    settings = Console.settings()
    previous = socket.assigns[:settings]

    socket =
      if previous && previous.version != settings.version,
        do: ItemActions.reset(socket),
        else: socket

    assign(socket, settings: settings)
  end

  defp closed_repository(nil, _settings, _filters), do: nil

  defp closed_repository(%{repository_id: id}, settings, filters) do
    Enum.find(settings.repositories, fn repo ->
      repo.id == id && (is_nil(filters.owner_id) || repo.owner_id == filters.owner_id) &&
        (is_nil(filters.repository_id) || repo.id == filters.repository_id)
    end)
  end

  defp load_dashboard(socket, page) do
    result =
      PatDashboard.read(socket.assigns.settings, socket.assigns.tab, socket.assigns.filters, page)

    assign(socket,
      rows: result.rows,
      page: result.page,
      pages: result.pages,
      pending_count: Map.get(result, :pending_count, 0),
      failed_count: Map.get(result, :failed_count, 0)
    )
  end

  defp default_filters, do: %{owner_id: nil, repository_id: nil}

  defp parse_filters(params, settings) do
    %{
      owner_id: positive_id(params["owner"]),
      repository_id: positive_id(params["repository"])
    }
    |> normalize_filters(settings)
  end

  defp normalize_filters(filters, settings) do
    owner_id =
      if Enum.any?(owners(settings), &(&1.owner_id == filters.owner_id)), do: filters.owner_id

    repository_id =
      if Enum.any?(
           settings.repositories,
           &(&1.id == filters.repository_id && (is_nil(owner_id) || &1.owner_id == owner_id))
         ),
         do: filters.repository_id

    %{filters | owner_id: owner_id, repository_id: repository_id}
  end

  defp positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
  end

  defp positive_id(_), do: nil

  defp github_path(tab, filters, page \\ 1) do
    query =
      [
        owner: filters.owner_id,
        repository: filters.repository_id,
        page: page
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    case tab do
      :issues -> ~p"/github/issue?#{query}"
      :pulls -> ~p"/github/pull-request?#{query}"
      :overview -> ~p"/github?#{query}"
    end
  end

  defp detail_path(tab, repository),
    do: github_path(tab, %{owner_id: repository.owner_id, repository_id: repository.id})

  defp owners(settings) do
    (settings.repositories ++
       Enum.map(settings.selected_owners, &%{owner_id: &1.id, owner: &1.login}))
    |> Enum.uniq_by(& &1.owner_id)
    |> Enum.sort_by(&String.downcase(&1.owner))
  end

  defp filter_repositories(repositories, nil), do: repositories

  defp filter_repositories(repositories, owner_id),
    do: Enum.filter(repositories, &(&1.owner_id == owner_id))

  defp configured?(settings),
    do: settings.connection && (settings.repositories != [] || settings.selected_owners != [])

  defp readable_time(nil), do: gettext("Not synced")
  defp readable_time(%DateTime{} = date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M UTC")

  defp readable_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date, _} -> readable_time(date)
      _ -> value
    end
  end

  defp iso_time(nil), do: nil
  defp iso_time(%DateTime{} = date), do: DateTime.to_iso8601(date)
  defp iso_time(value), do: value

  defp error_message(reason) when reason in [:disconnected, "disconnected"],
    do: gettext("Connect GitHub in Settings.")

  defp error_message(reason)
       when reason in [:invalid_token, :unreadable_token, "invalid_token", "unreadable_token"],
       do: gettext("Replace the PAT in Settings to reconnect GitHub.")

  defp error_message(reason) when reason in [:unapproved_destination, "unapproved_destination"],
    do: gettext("Ask the operator to configure approved GitHub API addresses, then sync again.")

  defp error_message({:rate_limited, until}),
    do:
      gettext("GitHub requests are paused until %{time}.",
        time: readable_time(DateTime.from_unix!(until))
      )

  defp error_message(_), do: gettext("Sync could not complete. Try syncing again.")
end
