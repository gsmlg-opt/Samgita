defmodule SamgitaWeb.SettingsLive.Index do
  @moduledoc "Operator console appearance and GitHub repository preferences."
  use SamgitaWeb, :live_view
  alias Samgita.GitHub.Console

  @sections [{"appearance", "Appearance"}, {"github", "GitHub"}]
  @keys Enum.map(@sections, &elem(&1, 0))
  @repository_page_size 25

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Settings",
       sections: @sections,
       section: "appearance",
       github_subscribed: false
     )
     |> blank_github()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    section = if params["section"] in @keys, do: params["section"], else: "appearance"
    socket = assign(socket, section: section)

    socket =
      cond do
        section != "github" -> blank_github(socket)
        socket.assigns.github_initialized -> socket
        true -> socket |> subscribe_github() |> reload_github() |> ensure_initial_catalog()
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("github_owner", %{"id" => id}, socket) do
    owner = Enum.find(socket.assigns.owners, &(to_string(&1.id) == id))
    {:noreply, assign(socket, owner_id: owner && owner.id, search: "", repository_page: 1)}
  end

  def handle_event("github_search", %{"search" => query}, socket),
    do: {:noreply, assign(socket, search: query, repository_page: 1)}

  def handle_event("github_repository_page", %{"direction" => direction}, socket) do
    page = socket.assigns.repository_page + if(direction == "next", do: 1, else: -1)

    pages =
      repository_pages(
        socket.assigns.catalog_repositories,
        socket.assigns.owner_id,
        socket.assigns.search
      )

    {:noreply, assign(socket, repository_page: min(max(page, 1), pages))}
  end

  def handle_event(event, _params, %{assigns: %{selection_saving: true}} = socket)
      when event in ["github_toggle", "github_toggle_owner"],
      do: {:noreply, socket}

  def handle_event("github_toggle", %{"id" => id}, socket) do
    listed = Enum.find(socket.assigns.catalog_repositories, &(to_string(&1.id) == id))

    repository =
      listed || Enum.find(socket.assigns.unlisted_selections, &(to_string(&1.id) == id))

    if repository &&
         (is_nil(listed) ||
            !MapSet.member?(socket.assigns.selected_owner_ids, repository.owner_id)) do
      {:noreply,
       set_selection(
         socket,
         toggle(socket.assigns.selected_ids, repository.id),
         socket.assigns.selected_owner_ids
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("github_toggle_owner", _params, socket) do
    if socket.assigns.owner_id do
      {:noreply,
       set_selection(
         socket,
         socket.assigns.selected_ids,
         toggle(socket.assigns.selected_owner_ids, socket.assigns.owner_id)
       )}
    else
      {:noreply, socket}
    end
  end

  def handle_event("github_save_selection", _params, socket) do
    if socket.assigns.selection_saving || socket.assigns.selection_conflict do
      {:noreply, socket}
    else
      version = socket.assigns.version
      ids = MapSet.to_list(socket.assigns.selected_ids)
      owner_ids = MapSet.to_list(socket.assigns.selected_owner_ids)

      {:noreply,
       socket
       |> assign(selection_saving: true, github_error: nil)
       |> start_async(:github_save_selection, fn ->
         Console.save_selection(version, ids, owner_ids)
       end)}
    end
  end

  def handle_event("github_refresh_catalog", _params, socket) do
    case Console.refresh_catalog(socket.assigns.version) do
      :ok -> {:noreply, read_catalog(socket)}
      {:error, reason} -> {:noreply, assign(socket, catalog_error: error_message(reason))}
    end
  end

  def handle_event("github_remove", _params, socket) do
    case Console.remove(socket.assigns.version) do
      :ok ->
        {:noreply,
         socket |> reload_github() |> put_flash(:info, gettext("GitHub connection removed."))}

      {:error, reason} ->
        {:noreply, assign(socket, github_error: error_message(reason))}
    end
  end

  def handle_event("github_reload", _params, socket), do: {:noreply, reload_github(socket)}

  @impl true
  def handle_info(:github_console_changed, socket) do
    {:noreply,
     if(socket.assigns.section == "github", do: reconcile_settings(socket), else: socket)}
  end

  def handle_info(:github_catalog_changed, %{assigns: %{section: "github"}} = socket) do
    settings = Console.settings()

    cond do
      settings.version != socket.assigns.version ->
        socket = reconcile_settings(socket, settings)

        {:noreply,
         if(socket.assigns.selection_conflict,
           do: read_catalog(socket, settings.version),
           else: socket
         )}

      same_credential?(settings.connection, socket.assigns.connection) ->
        {:noreply, read_catalog(socket, settings.version)}

      true ->
        {:noreply, reconcile_settings(socket, settings)}
    end
  end

  def handle_info(:github_catalog_changed, socket), do: {:noreply, socket}
  def handle_info(:github_feed_changed, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:github_save_selection, {:ok, :ok}, socket) do
    socket = if socket.assigns.section == "github", do: reconcile_settings(socket), else: socket

    {:noreply,
     socket
     |> assign(selection_saving: false)
     |> put_flash(:info, gettext("Repository selection saved."))}
  end

  def handle_async(:github_save_selection, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, selection_saving: false, github_error: error_message(reason))}

  def handle_async(:github_save_selection, {:exit, _reason}, socket),
    do:
      {:noreply,
       assign(socket, selection_saving: false, github_error: error_message(:unavailable))}

  defp blank_github(socket) do
    assign(socket,
      connection: nil,
      version: nil,
      github_initialized: false,
      saved_ids: MapSet.new(),
      selected_ids: MapSet.new(),
      saved_owner_ids: MapSet.new(),
      selected_owner_ids: MapSet.new(),
      selection_saving: false,
      selection_dirty: false,
      selection_conflict: false,
      owners: [],
      owner_id: nil,
      catalog_repositories: [],
      unlisted_selections: [],
      catalog_loaded: false,
      catalog_status: :uninitialized,
      catalog_error: nil,
      memberships_available: true,
      github_error: nil,
      search: "",
      repository_page: 1
    )
  end

  defp apply_settings(socket, settings) do
    ids = MapSet.new(settings.repository_ids)
    owner_ids = MapSet.new(settings.selected_owners, & &1.id)

    assign(socket,
      connection: settings.connection,
      version: settings.version,
      github_initialized: true,
      saved_ids: ids,
      selected_ids: ids,
      saved_owner_ids: owner_ids,
      selected_owner_ids: owner_ids,
      selection_saving: false,
      selection_dirty: false,
      selection_conflict: false,
      github_error: nil
    )
  end

  defp reload_github(socket) do
    settings = Console.settings()

    socket =
      if same_credential?(settings.connection, socket.assigns.connection),
        do: socket,
        else: blank_github(socket)

    socket |> apply_settings(settings) |> read_catalog()
  end

  defp subscribe_github(socket) do
    if connected?(socket) && !socket.assigns.github_subscribed do
      Console.subscribe()
      assign(socket, github_subscribed: true)
    else
      socket
    end
  end

  defp ensure_initial_catalog(socket) do
    if connected?(socket) && socket.assigns.connection &&
         socket.assigns.catalog_status == :uninitialized do
      case Console.ensure_catalog(socket.assigns.version) do
        :ok -> read_catalog(socket)
        {:error, reason} -> assign(socket, catalog_error: error_message(reason))
      end
    else
      socket
    end
  end

  defp reconcile_settings(socket, settings \\ Console.settings()) do
    ids = MapSet.new(settings.repository_ids)
    owner_ids = MapSet.new(settings.selected_owners, & &1.id)

    cond do
      settings.version == socket.assigns.version ->
        socket

      !same_credential?(settings.connection, socket.assigns.connection) ->
        socket |> blank_github() |> apply_settings(settings) |> read_catalog()

      socket.assigns.selection_saving && ids == socket.assigns.selected_ids &&
          owner_ids == socket.assigns.selected_owner_ids ->
        socket |> apply_settings(settings) |> read_catalog()

      socket.assigns.selection_dirty ->
        assign(socket, selection_conflict: true, github_error: error_message(:stale))

      true ->
        socket |> apply_settings(settings) |> read_catalog()
    end
  end

  defp same_credential?(%{credential_version: v}, %{credential_version: v}), do: true
  defp same_credential?(_, _), do: false

  defp set_selection(socket, selected, owners) do
    assign(socket,
      selected_ids: selected,
      selected_owner_ids: owners,
      selection_dirty:
        selected != socket.assigns.saved_ids || owners != socket.assigns.saved_owner_ids
    )
  end

  defp read_catalog(socket, version \\ nil)
  defp read_catalog(%{assigns: %{connection: nil}} = socket, _version), do: socket

  defp read_catalog(socket, version) do
    case Console.catalog(version || socket.assigns.version) do
      {:ok, catalog} -> catalog_result(socket, catalog)
      {:error, reason} -> assign(socket, catalog_error: error_message(reason))
    end
  end

  defp catalog_result(socket, catalog) do
    listed_ids = MapSet.new(catalog.repositories, & &1.id)

    owners =
      Enum.uniq_by(
        catalog.owners ++
          Enum.filter(
            socket.assigns.owners,
            &MapSet.member?(socket.assigns.selected_owner_ids, &1.id)
          ),
        & &1.id
      )

    retained_drafts =
      (socket.assigns.catalog_repositories ++ socket.assigns.unlisted_selections)
      |> Enum.filter(
        &(MapSet.member?(socket.assigns.selected_ids, &1.id) &&
            !MapSet.member?(listed_ids, &1.id))
      )

    unlisted = Enum.uniq_by(catalog.unlisted_selections ++ retained_drafts, & &1.id)

    owner =
      Enum.find(owners, &(&1.id == socket.assigns.owner_id)) ||
        Enum.find(owners, &(&1.id == socket.assigns.connection.github_id)) || List.first(owners)

    owner_id = owner && owner.id

    assign(socket,
      owners: owners,
      owner_id: owner_id,
      memberships_available: catalog.memberships_available,
      catalog_repositories: catalog.repositories,
      unlisted_selections: unlisted,
      catalog_status: catalog.status,
      catalog_loaded: true,
      catalog_error: if(catalog.error, do: error_message(catalog.error)),
      repository_page:
        min(
          socket.assigns.repository_page,
          repository_pages(catalog.repositories, owner_id, socket.assigns.search)
        )
    )
  end

  attr :repository, :map, required: true
  attr :checked, :boolean, required: true
  attr :disabled, :boolean, required: true

  defp repository_option(assigns) do
    ~H"""
    <label
      class="flex cursor-pointer items-center gap-3 py-3"
      for={"github-repository-#{@repository.id}"}
    >
      <input
        id={"github-repository-#{@repository.id}"}
        type="checkbox"
        checked={@checked}
        disabled={@disabled}
        phx-click="github_toggle"
        phx-value-id={@repository.id}
        class="checkbox shrink-0"
      />
      <span class="break-all">{@repository.owner}/{@repository.name}</span>
    </label>
    """
  end

  defp repository_selected?(repository, ids, owner_ids),
    do: MapSet.member?(ids, repository.id) || MapSet.member?(owner_ids, repository.owner_id)

  defp selected_count(repositories, ids, owner_ids) do
    repositories
    |> Enum.filter(&repository_selected?(&1, ids, owner_ids))
    |> Enum.map(& &1.id)
    |> MapSet.new()
    |> MapSet.union(ids)
    |> MapSet.size()
  end

  defp visible_repositories(repositories, owner_id, query) do
    query = String.downcase(String.trim(query))

    Enum.filter(
      repositories,
      &(&1.owner_id == owner_id && String.contains?(String.downcase(&1.name), query))
    )
  end

  defp repository_page(repositories, owner_id, query, page),
    do:
      repositories
      |> visible_repositories(owner_id, query)
      |> Enum.slice((page - 1) * @repository_page_size, @repository_page_size)

  defp repository_pages(repositories, owner_id, query),
    do:
      max(
        1,
        div(
          length(visible_repositories(repositories, owner_id, query)) + @repository_page_size - 1,
          @repository_page_size
        )
      )

  defp toggle(selected, id) do
    if MapSet.member?(selected, id),
      do: MapSet.delete(selected, id),
      else: MapSet.put(selected, id)
  end

  defp error_message(:stale),
    do:
      gettext(
        "Settings changed elsewhere. Your unsaved selection is preserved. Reload to use the latest settings."
      )

  defp error_message(:invalid_token),
    do: gettext("The GitHub connection needs a replacement PAT.")

  defp error_message(:unreadable_token),
    do: gettext("The saved PAT cannot be read. Replace it to reconnect GitHub.")

  defp error_message(:storage_key_unavailable),
    do: gettext("Configure a stable SECRET_KEY_BASE on the server, then replace the PAT.")

  defp error_message(:unapproved_destination),
    do:
      gettext(
        "Ask the operator to configure SAMGITA_GITHUB_HOSTS with approved GitHub API addresses, then refresh."
      )

  defp error_message(:disconnected), do: gettext("Connect GitHub to choose repositories.")

  defp error_message(:refresh_interrupted),
    do: gettext("The previous catalog refresh stopped. Use the refresh button to try again.")

  defp error_message(:enqueue_failed),
    do: gettext("The catalog refresh could not be queued. Use the refresh button to try again.")

  defp error_message({:rate_limited, until}),
    do:
      gettext("GitHub requests are paused until %{time}.",
        time: DateTime.from_unix!(until) |> DateTime.to_string()
      )

  defp error_message(_), do: gettext("GitHub could not complete this request. Please try again.")
end
