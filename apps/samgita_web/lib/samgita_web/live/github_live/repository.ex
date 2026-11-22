defmodule SamgitaWeb.GitHubLive.Repository do
  @moduledoc "The selected repository's issues, pull requests and workflow runs."
  use SamgitaWeb, :live_view
  alias Samgita.GitHub.{Console, PatDashboard, PatSync, PatWorkflowRuns}
  alias SamgitaWeb.GitHubLive.{ItemActions, ItemTable}
  import ItemActions, only: [error_message: 1]
  import ItemTable, only: [readable_time: 1]
  @poll_interval 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Console.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "GitHub",
       repository_id: nil,
       detail: nil,
       connection: nil,
       context: nil,
       subscribed_repository: nil,
       tab: :issues,
       issue_page: 1,
       pull_page: 1
     )
     |> reset_runtime()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = tab(params["tab"])

    socket =
      if tab != socket.assigns.tab,
        do: assign(socket, sync_status: nil, sync_error: nil),
        else: socket

    {:noreply,
     socket
     |> assign(
       repository_id: positive_id(params["id"]),
       tab: tab,
       issue_page: positive_id(params["issue_page"]) || 1,
       pull_page: positive_id(params["pull_page"]) || 1
     )
     |> load_repository()}
  end

  @impl true
  def handle_event("sync", _params, %{assigns: %{detail: nil}} = socket), do: {:noreply, socket}

  def handle_event("sync", _params, socket) do
    result =
      if socket.assigns.tab == :workflow_runs,
        do:
          PatWorkflowRuns.request(
            socket.assigns.connection,
            socket.assigns.repository_id,
            :manual
          ),
        else: PatSync.request_repository(socket.assigns.connection, socket.assigns.repository_id)

    case result do
      :ok ->
        {:noreply,
         socket
         |> assign(sync_status: gettext("Sync queued."), sync_error: nil, workflow_error: nil)
         |> load_workflows()}

      {:error, reason} ->
        {:noreply, assign(socket, sync_status: nil, sync_error: error_message(reason))}
    end
  end

  def handle_event("repository_action", params, socket) do
    %{detail: detail, tab: tab, connection: connection} = socket.assigns
    rows = if detail && tab in [:issues, :pulls], do: detail[tab].rows, else: []
    {:noreply, ItemActions.handle_row(socket, connection, tab, rows, params)}
  end

  def handle_event("reopen_issue", %{"number" => number}, socket) do
    socket = assign(socket, reopen_number: number)

    case positive_id(number) do
      nil ->
        {:noreply,
         assign(socket,
           action_error: gettext("Enter a positive issue number."),
           action_status: nil
         )}

      number ->
        {:noreply,
         ItemActions.queue(
           socket,
           socket.assigns.connection,
           socket.assigns.repository_id,
           :reopen_issue,
           number,
           nil
         )}
    end
  end

  def handle_event("reopen_closed_issue", _params, socket),
    do: {:noreply, ItemActions.reopen_closed(socket, socket.assigns.connection)}

  @impl true
  def handle_info(message, socket)
      when message in [:github_console_changed, :github_catalog_changed, :github_feed_changed],
      do: {:noreply, load_repository(socket)}

  def handle_info(
        {:github_workflow_runs_changed, id},
        %{assigns: %{repository_id: id, tab: :workflow_runs}} = socket
      ),
      do: {:noreply, load_repository(socket)}

  def handle_info({:github_workflow_runs_changed, _id}, socket), do: {:noreply, socket}

  def handle_info({:github_pat_action, _, _, action, _, outcome} = message, socket) do
    case ItemActions.finish(socket, message) do
      {:ok, socket} ->
        socket =
          if action == :reopen_issue && outcome == :ok,
            do: assign(socket, reopen_number: ""),
            else: socket

        {:noreply, load_repository(socket)}

      :ignore ->
        {:noreply, socket}
    end
  end

  def handle_info({:github_workflow_poll, token}, socket) do
    if token == socket.assigns.workflow_poll_token && socket.assigns.tab == :workflow_runs &&
         socket.assigns.detail && socket.assigns.workflows.active? do
      socket = cancel_poll(socket)

      socket =
        case PatWorkflowRuns.request(
               socket.assigns.connection,
               socket.assigns.repository_id,
               :poll
             ) do
          :ok -> socket
          {:error, reason} -> assign(socket, workflow_error: error_message(reason))
        end

      {:noreply, load_workflows(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns.workflow_timer, do: Process.cancel_timer(socket.assigns.workflow_timer)
    if id = socket.assigns.subscribed_repository, do: Console.unsubscribe_repository(id)
    :ok
  end

  defp load_repository(%{assigns: %{repository_id: nil}} = socket), do: unavailable(socket)

  defp load_repository(socket) do
    settings = Console.settings()

    detail =
      PatDashboard.repository(
        settings,
        socket.assigns.repository_id,
        socket.assigns.issue_page,
        socket.assigns.pull_page
      )

    case detail do
      nil ->
        unavailable(socket)

      detail ->
        context =
          {settings.connection.id, settings.connection.credential_version,
           socket.assigns.repository_id}

        socket = if context == socket.assigns.context, do: socket, else: reset_runtime(socket)
        previous = socket.assigns.detail

        socket =
          if socket.assigns.tab != :workflow_runs && previous && previous.sync != detail.sync,
            do: assign(socket, sync_status: nil),
            else: socket

        socket
        |> assign(
          detail: detail,
          connection: settings.connection,
          context: context,
          page_title: detail.repository.owner <> "/" <> detail.repository.name,
          issue_page: detail.issues.page,
          pull_page: detail.pulls.page
        )
        |> update_subscription(socket.assigns.repository_id)
        |> load_workflows()
    end
  end

  defp unavailable(socket) do
    socket
    |> reset_runtime()
    |> assign(
      detail: nil,
      connection: nil,
      context: nil,
      page_title: gettext("Repository unavailable")
    )
    |> update_subscription(nil)
  end

  defp update_subscription(socket, id) do
    if connected?(socket) && id != socket.assigns.subscribed_repository do
      if old_id = socket.assigns.subscribed_repository, do: Console.unsubscribe_repository(old_id)
      if id, do: Console.subscribe_repository(id)
      assign(socket, subscribed_repository: id)
    else
      socket
    end
  end

  defp reset_runtime(socket) do
    socket =
      if Map.has_key?(socket.assigns, :workflow_timer), do: cancel_poll(socket), else: socket

    socket
    |> ItemActions.reset()
    |> assign(
      sync_status: nil,
      sync_error: nil,
      reopen_number: "",
      workflows: %{rows: [], synced_at: nil, status: :uninitialized, error: nil, active?: false},
      workflow_initial_requested: false,
      workflow_error: nil,
      workflow_timer: nil,
      workflow_poll_token: nil
    )
  end

  defp load_workflows(%{assigns: %{tab: :workflow_runs, detail: detail}} = socket)
       when not is_nil(detail) do
    workflows = PatWorkflowRuns.read(socket.assigns.connection, socket.assigns.repository_id)
    socket = assign(socket, workflows: workflows)

    socket =
      if workflows.status in [:ready, :failed], do: assign(socket, sync_status: nil), else: socket

    socket =
      if connected?(socket) && workflows.status == :uninitialized &&
           !socket.assigns.workflow_initial_requested do
        socket = assign(socket, workflow_initial_requested: true)

        case PatWorkflowRuns.request(
               socket.assigns.connection,
               socket.assigns.repository_id,
               :initial
             ) do
          :ok ->
            assign(socket,
              workflows:
                PatWorkflowRuns.read(socket.assigns.connection, socket.assigns.repository_id)
            )

          {:error, reason} ->
            assign(socket, workflow_error: error_message(reason))
        end
      else
        socket
      end

    update_poll(socket)
  end

  defp load_workflows(socket), do: cancel_poll(socket)

  defp update_poll(socket) do
    cond do
      !connected?(socket) || !socket.assigns.workflows.active? ||
          socket.assigns.workflows.status == :refreshing ->
        cancel_poll(socket)

      socket.assigns.workflow_timer ->
        socket

      true ->
        token = make_ref()
        timer = Process.send_after(self(), {:github_workflow_poll, token}, @poll_interval)
        assign(socket, workflow_timer: timer, workflow_poll_token: token)
    end
  end

  defp cancel_poll(socket) do
    if timer = socket.assigns.workflow_timer, do: Process.cancel_timer(timer)
    assign(socket, workflow_timer: nil, workflow_poll_token: nil)
  end

  defp tab("pulls"), do: :pulls
  defp tab("workflow-runs"), do: :workflow_runs
  defp tab(_), do: :issues
  defp tab_param(:workflow_runs), do: "workflow-runs"
  defp tab_param(value), do: Atom.to_string(value)

  defp positive_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> nil
    end
  end

  defp positive_id(_), do: nil

  defp repository_path(id, tab, issue_page, pull_page),
    do:
      ~p"/github/repository/#{id}?#{[tab: tab_param(tab), issue_page: issue_page, pull_page: pull_page]}"

  defp page_path(:issues, id, page, _issue_page, pull_page),
    do: repository_path(id, :issues, page, pull_page)

  defp page_path(:pulls, id, page, issue_page, _pull_page),
    do: repository_path(id, :pulls, issue_page, page)

  defp run_status(run), do: run.conclusion || String.replace(run.status, "_", " ")

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :kind, :atom, required: true
  attr :result, :map, required: true
  attr :repository_id, :integer, required: true
  attr :issue_page, :integer, required: true
  attr :pull_page, :integer, required: true
  attr :pending, :boolean, required: true
  attr :jobs, :map, required: true

  defp item_table(assigns) do
    ~H"""
    <section id={@id} aria-labelledby={@id <> "-title"} class="min-w-0">
      <.dm_card variant="bordered">
        <:title>
          <span id={@id <> "-title"} class="flex items-center justify-between gap-3">
            <span>{@title}</span>
            <span class="text-sm font-normal text-on-surface-variant">{if @pending,
              do: "—",
              else: @result.total}</span>
          </span>
        </:title>
        <ItemTable.table
          id={@id <> "-table"}
          rows={@result.rows}
          kind={@kind}
          jobs={@jobs}
          empty_message={
            if @pending, do: gettext("Awaiting first sync."), else: gettext("No open items.")
          }
        />
        <nav
          :if={@result.pages > 1}
          aria-label={gettext("%{list} pages", list: @title)}
          class="mt-5 flex items-center justify-between gap-2"
        >
          <.link
            :if={@result.page > 1}
            id={@id <> "-previous"}
            patch={page_path(@kind, @repository_id, @result.page - 1, @issue_page, @pull_page)}
            class="btn btn-ghost btn-sm"
          >{gettext("Previous")}</.link>
          <span :if={@result.page == 1} class="btn btn-ghost btn-sm" aria-disabled="true">{gettext(
            "Previous"
          )}</span>
          <span class="text-sm text-on-surface-variant">{gettext("Page %{page} of %{pages}",
            page: @result.page,
            pages: @result.pages
          )}</span>
          <.link
            :if={@result.page < @result.pages}
            id={@id <> "-next"}
            patch={page_path(@kind, @repository_id, @result.page + 1, @issue_page, @pull_page)}
            class="btn btn-ghost btn-sm"
          >{gettext("Next")}</.link>
          <span :if={@result.page == @result.pages} class="btn btn-ghost btn-sm" aria-disabled="true">{gettext(
            "Next"
          )}</span>
        </nav>
      </.dm_card>
    </section>
    """
  end
end
