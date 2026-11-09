defmodule SamgitaWeb.ProjectsLive.Index do
  use SamgitaWeb, :live_view
  alias Samgita.{CodexHosts, Principal}

  @impl true
  def mount(_, _, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())

    {:ok,
     socket
     |> assign(page_title: "Projects")
     |> assign(codex_projects: %{}, sessions: %{}, expanded: MapSet.new())
     |> load_hosts()}
  end

  @impl true
  # Codex workspaces: hosts -> projects -> sessions, read live from each host.
  def handle_event("toggle_project", %{"host" => host_id, "project" => project_id}, socket) do
    key = {host_id, project_id}

    if MapSet.member?(socket.assigns.expanded, key) do
      {:noreply, update(socket, :expanded, &MapSet.delete(&1, key))}
    else
      socket = update(socket, :expanded, &MapSet.put(&1, key))

      {:noreply,
       if(Map.has_key?(socket.assigns.sessions, key),
         do: socket,
         else: load_sessions(socket, key)
       )}
    end
  end

  def handle_event("refresh_sessions", %{"host" => host_id, "project" => project_id}, socket),
    do: {:noreply, load_sessions(socket, {host_id, project_id})}

  @impl true
  def handle_info({:codex_host_status, _id, _status}, socket), do: {:noreply, load_hosts(socket)}
  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async({:projects, host_id}, {:ok, result}, socket),
    do: {:noreply, update(socket, :codex_projects, &Map.put(&1, host_id, outcome(result)))}

  def handle_async({:projects, host_id}, {:exit, _}, socket),
    do:
      {:noreply,
       update(
         socket,
         :codex_projects,
         &Map.put(&1, host_id, {:error, "Codex could not be reached."})
       )}

  def handle_async({:sessions, host_id, project_id}, {:ok, result}, socket),
    do:
      {:noreply, update(socket, :sessions, &Map.put(&1, {host_id, project_id}, outcome(result)))}

  def handle_async({:sessions, host_id, project_id}, {:exit, _}, socket),
    do:
      {:noreply,
       update(
         socket,
         :sessions,
         &Map.put(&1, {host_id, project_id}, {:error, "Codex could not be reached."})
       )}

  defp load_hosts(socket) do
    {:ok, hosts} = CodexHosts.list(Principal.operator())
    socket = assign(socket, hosts: hosts)

    # Load projects once per connected host; a reconnect reloads them.
    Enum.reduce(hosts, socket, fn host, acc ->
      connected = get_in(host, ["status", "state"]) == "connected"
      loaded = Map.get(acc.assigns.codex_projects, host["id"])

      cond do
        connected and (loaded == nil or match?({:error, _}, loaded)) ->
          id = host["id"]

          acc
          |> update(:codex_projects, &Map.put(&1, id, nil))
          |> start_async({:projects, id}, fn -> CodexHosts.projects(Principal.operator(), id) end)

        connected ->
          acc

        true ->
          update(acc, :codex_projects, &Map.delete(&1, host["id"]))
      end
    end)
  end

  defp load_sessions(socket, {host_id, project_id} = key) do
    roots =
      case socket.assigns.codex_projects[host_id] do
        {:ok, projects} -> Enum.find_value(projects, [], &(&1["id"] == project_id && &1["roots"]))
        _ -> []
      end

    socket
    |> update(:sessions, &Map.put(&1, key, nil))
    |> start_async({:sessions, host_id, project_id}, fn ->
      CodexHosts.sessions(Principal.operator(), host_id, roots)
    end)
  end

  defp outcome({:ok, value}), do: {:ok, value}

  defp outcome({:error, %Samgita.Error{code: :codex_unavailable}}),
    do: {:error, "Codex is not connected."}

  defp outcome(_), do: {:error, "Codex could not answer this request."}

  defp host_state(host), do: get_in(host, ["status", "state"]) || "stopped"

  defp state_variant("connected"), do: "success"
  defp state_variant(state) when state in ~w(connecting backoff), do: "warning"
  defp state_variant(_), do: "neutral"

  # Codex thread status: a thread not loaded in memory is simply idle.
  defp session_state("active"), do: "running"
  defp session_state("systemError"), do: "error"
  defp session_state(_), do: "idle"

  defp when_updated(nil), do: ""

  defp when_updated(seconds) when is_integer(seconds),
    do: seconds |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m-%d %H:%M")

  defp when_updated(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
    <section id="codex-workspaces" class="space-y-6" aria-labelledby="projects-title">
      <header>
        <h1 id="projects-title" class="text-3xl font-bold">Projects</h1>
        <p class="text-on-surface-variant">Codex projects and sessions on each machine.</p>
      </header>
      <p :if={@hosts == []} id="codex-workspaces-empty" class="text-on-surface-variant">
        No Codex machines yet. Add one on the
        <.link navigate={~p"/agents"} class="text-primary">Agents</.link>
        page.
      </p>
      <.dm_card :for={host <- @hosts} id={"codex-host-" <> host["id"]} variant="bordered">
        <:title>
          <div class="flex flex-wrap items-center gap-3">
            <.link navigate={~p"/agents/#{host["agent_id"]}"} class="font-semibold">
              {host["agent_name"]}
            </.link>
            <span
              :if={host["machine_name"] not in [nil, host["agent_name"]]}
              class="text-sm text-on-surface-variant"
            >
              {host["machine_name"]}
            </span>
            <.dm_badge variant={state_variant(host_state(host))}>{host_state(host)}</.dm_badge>
          </div>
        </:title>
        <%= case {@codex_projects[host["id"]], host_state(host)} do %>
          <% {nil, "connected"} -> %>
            <p class="text-on-surface-variant">Loading projects…</p>
          <% {nil, _} -> %>
            <p class="text-on-surface-variant">
              Not connected. Start it on the Agent page to see its projects.
            </p>
          <% {{:error, message}, _} -> %>
            <p role="alert" class="text-error">{message}</p>
          <% {{:ok, []}, _} -> %>
            <p class="text-on-surface-variant">
              No projects on this machine.
              <.link
                navigate={~p"/agents/#{host["agent_id"]}?section=projects"}
                class="text-primary"
              >Add a project</.link>
            </p>
          <% {{:ok, projects}, _} -> %>
            <ul class="divide-y divide-outline-variant">
              <li :for={project <- projects} id={"codex-project-" <> project["id"]}>
                <button
                  type="button"
                  class="flex w-full items-center gap-3 py-3 text-left"
                  phx-click="toggle_project"
                  phx-value-host={host["id"]}
                  phx-value-project={project["id"]}
                  aria-expanded={to_string(MapSet.member?(@expanded, {host["id"], project["id"]}))}
                >
                  <.dm_mdi
                    name={
                      if MapSet.member?(@expanded, {host["id"], project["id"]}),
                        do: "chevron-down",
                        else: "chevron-right"
                    }
                    class="h-5 w-5 text-on-surface-variant"
                  />
                  <span class="font-semibold">{project["name"]}</span>
                  <code class="truncate text-sm text-on-surface-variant">{Enum.join(
                    project["roots"],
                    ", "
                  )}</code>
                </button>
                <div
                  :if={MapSet.member?(@expanded, {host["id"], project["id"]})}
                  class="pb-3 pl-8"
                >
                  <.link
                    :if={project["roots"] != []}
                    id={"codex-new-session-" <> project["id"]}
                    navigate={~p"/sessions/#{host["id"]}/new?#{%{cwd: hd(project["roots"])}}"}
                    class="mb-2 inline-flex items-center gap-1 text-sm font-semibold text-primary"
                  >
                    <.dm_mdi name="plus" class="h-4 w-4" /> New session
                  </.link>
                  <%= case @sessions[{host["id"], project["id"]}] do %>
                    <% nil -> %>
                      <p class="text-on-surface-variant">Loading sessions…</p>
                    <% {:error, message} -> %>
                      <p role="alert" class="text-error">{message}</p>
                    <% {:ok, []} -> %>
                      <p class="text-on-surface-variant">No sessions in this project yet.</p>
                    <% {:ok, sessions} -> %>
                      <ul class="codex-sessions space-y-1">
                        <li
                          :for={session <- sessions}
                          id={"codex-session-" <> session["id"]}
                          class="flex items-center gap-3"
                        >
                          <.dm_mdi name="message-outline" class="h-4 w-4 text-on-surface-variant" />
                          <.link
                            navigate={~p"/sessions/#{host["id"]}/#{session["id"]}"}
                            class="truncate hover:underline"
                          >
                            {session["title"]}
                          </.link>
                          <span class="ml-auto shrink-0 text-xs text-on-surface-variant">
                            {session_state(session["status"])} · {when_updated(session["updated_at"])}
                          </span>
                        </li>
                      </ul>
                  <% end %>
                </div>
              </li>
            </ul>
        <% end %>
      </.dm_card>
    </section>
    """
  end
end
