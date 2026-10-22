defmodule SamgitaWeb.TasksLive.Show do
  use SamgitaWeb, :live_view
  alias Samgita.{Management, Principal, Tasks, TaskTransitions}
  alias SamgitaWeb.ProjectsLive.Support, as: UI

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         page_title: "Task",
         forms: %{},
         errors: %{},
         expanded: MapSet.new(),
         completed_commands: MapSet.new()
       )}

  @impl true
  def handle_params(%{"project_id" => project_id, "id" => id} = params, _, socket) do
    expanded = if socket.assigns[:task_id] == id, do: socket.assigns.expanded, else: MapSet.new()
    socket = assign(socket, expanded: expanded)

    {:noreply,
     socket |> assign(project_id: project_id, task_id: id, params: params) |> load(true)}
  end

  defp load(socket, reset) do
    case Management.task(
           Principal.operator(),
           socket.assigns.project_id,
           socket.assigns.task_id,
           socket.assigns.params
         ) do
      {:ok, page} ->
        socket = assign(socket, page: page, load_error: nil, page_title: page["task"]["title"])
        if reset, do: assign(socket, forms: forms(page["task"]), errors: %{}), else: socket

      {:error, error} ->
        assign(socket, page: nil, load_error: UI.error(error))
    end
  end

  defp forms(task) do
    %{
      "task" =>
        UI.new_form(
          "task",
          Map.take(task, ~w(title description parent_task_id required_capabilities)),
          task["version"]
        ),
      "transition" => UI.new_form("transition", %{}, task["version"]),
      "review" =>
        UI.new_form("review", %{"kind" => "review", "verdict" => "approve"}, task["version"]),
      "acceptance" =>
        UI.new_form(
          "acceptance",
          %{"kind" => "acceptance", "verdict" => "approve"},
          task["version"]
        ),
      "artifact" => UI.new_form("artifact", %{}, task["version"])
    }
  end

  @impl true
  def handle_event("toggle_section", %{"name" => name}, socket)
      when name in ~w(task transition artifact) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, name),
        do: MapSet.delete(expanded, name),
        else: MapSet.put(expanded, name)

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("change:" <> name, params, socket) do
    values = Map.fetch!(params, name)

    {:noreply,
     assign(socket,
       expanded: MapSet.put(socket.assigns.expanded, name),
       forms:
         Map.put(
           socket.assigns.forms,
           name,
           UI.changed(
             name,
             values,
             socket.assigns.page["task"]["version"],
             MapSet.member?(socket.assigns.completed_commands, values["command_id"])
           )
         ),
       errors: Map.delete(socket.assigns.errors, name)
     )}
  end

  def handle_event("save:" <> name, params, socket) do
    socket = assign(socket, expanded: MapSet.put(socket.assigns.expanded, name))
    values = Map.fetch!(params, name)
    attrs = UI.attrs(values)
    attrs = if name in ~w(review acceptance), do: Map.put(attrs, "kind", name), else: attrs
    args = [Principal.operator(), socket.assigns.project_id, socket.assigns.task_id, attrs]

    result =
      case name do
        "task" -> apply(Tasks, :update, args)
        "transition" -> apply(Tasks, :transition, args)
        "review" -> apply(Tasks, :decide, args)
        "acceptance" -> apply(Tasks, :decide, args)
        "artifact" -> apply(Tasks, :add_artifact, args)
      end

    case result do
      {:ok, _} ->
        socket = load(socket, false)
        forms = Map.put(forms(socket.assigns.page["task"]), name, to_form(values, as: name))

        {:noreply,
         socket
         |> assign(
           forms: forms,
           errors: Map.delete(socket.assigns.errors, name),
           completed_commands: MapSet.put(socket.assigns.completed_commands, values["command_id"])
         )
         |> put_flash(:info, "Saved. Review and Task acceptance are separate decisions.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           forms: Map.put(socket.assigns.forms, name, UI.rejected(name, values, error)),
           errors: Map.put(socket.assigns.errors, name, UI.error(error))
         )}
    end
  end

  defp transitions(state),
    do: Enum.filter(~w(open blocked cancelled), &(TaskTransitions.validate(state, &1) == :ok))

  defp reviewable?(task),
    do: task["state"] == "awaiting_review" && task["adopted"] && !task["execution_hold"]

  defp reviewed?(page), do: page["current_review_approved"] == true

  defp outcome_status(%{"outcome" => %{"status" => status}}) when status in ~w(succeeded failed),
    do: status

  defp outcome_status(_), do: nil

  defp outcome_summary(%{"outcome" => %{"result" => %{"summary" => summary}}})
       when is_binary(summary),
       do: summary

  defp outcome_summary(_), do: nil
  defp max_total(page), do: page["totals"] |> Map.values() |> Enum.max(fn -> 0 end)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl space-y-6 p-4 sm:p-6">
      <.link navigate={~p"/projects/#{@project_id}"} class="text-primary">Back to project</.link>
      <p :if={@load_error} role="alert">{@load_error}</p>
      <div :if={@page} class="space-y-6">
        <p :for={{name, error} <- @errors} role="alert">{name}: {error}</p>
        <header>
          <p class="text-on-surface-variant">{@page["project"]["name"]}</p><h1 class="text-3xl font-bold">
            {@page["task"]["title"]}
          </h1><p id="task-state">{@page["task"]["state"]} · version {@page["task"]["version"]}</p><p class="break-all text-sm text-on-surface-variant">
            {@task_id}
          </p><.link href={~p"/projects/#{@project_id}/tasks/#{@task_id}"} class="text-primary">Refresh persisted state</.link>
        </header>
        <.dm_alert :if={@page["task"]["execution_hold"]} variant="warning" id="task-hold">
          Execution hold: remote effects need explicit resolution. A management transition does not resolve them.
        </.dm_alert>
        <.dm_alert :if={!@page["task"]["adopted"]} variant="warning">
          Historical Task requires reviewed adoption through the management API before execution.
        </.dm_alert>
        <.dm_card :if={@page["task"]["legacy"]} id="task-legacy">
          <:title>Historical Task provenance</:title><p>
            Preserved legacy fields are read only. They do not grant execution or acceptance.
          </p><dl class="grid grid-cols-2 gap-2">
            <div :for={{key, value} <- @page["task"]["legacy"]}>
              <dt class="text-sm text-on-surface-variant">{key}</dt><dd class="break-words">
                {value}
              </dd>
            </div>
          </dl>
        </.dm_card>
        <.dm_alert :if={@page["task"]["state"] == "awaiting_review"} variant="info">
          Pending review. Attempt success does not accept this Task. Record a review, then a separate acceptance decision.
        </.dm_alert>
        <div class="grid items-start gap-6 lg:grid-cols-2">
          <.dm_card>
            <:title>Task details</:title><p class="whitespace-pre-wrap">
              {@page["task"]["description"]}
            </p><p>Parent: {@page["task"]["parent_task_id"] || "None"}</p><p>
              Required capabilities: {Enum.join(@page["task"]["required_capabilities"], ", ")}
            </p>
            <details
              :if={@page["task"]["state"] not in ~w(in_progress accepted)}
              id="task-section"
              class="mt-4"
              open={MapSet.member?(@expanded, "task")}
            >
              <summary phx-click="toggle_section" phx-value-name="task">Edit task</summary><UI.command_form
                form={@forms["task"]}
                error={@errors["task"]}
                event="save:task"
                label="Save task"
                fields={[
                  {"title", "Title", "text"},
                  {"description", "Description", "textarea"},
                  {"parent_task_id", "Parent Task UUID (optional)", "text"},
                  {"required_capabilities", "Required capabilities (comma separated)", "text"}
                ]}
              />
            </details>
            <details
              :if={transitions(@page["task"]["state"]) != []}
              id="transition-section"
              class="mt-4"
              open={MapSet.member?(@expanded, "transition")}
            >
              <summary phx-click="toggle_section" phx-value-name="transition">
                Management transition
              </summary><p>
                Available transitions: {Enum.join(transitions(@page["task"]["state"]), ", ")}. Execution starts only through an authorized Agent claim.
              </p><UI.command_form
                form={@forms["transition"]}
                error={@errors["transition"]}
                event="save:transition"
                label="Change Task state"
                fields={[{"state", "Target state", "text"}]}
              />
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Review and acceptance</:title><p>
              Reports and artifact references are evidence. They never confer acceptance.
            </p>
            <div :if={reviewable?(@page["task"])} class="mt-4 space-y-6">
              <section>
                <h2 class="text-lg font-semibold">1. Review</h2><UI.command_form
                  form={@forms["review"]}
                  error={@errors["review"]}
                  event="save:review"
                  label="Record review"
                  fields={[
                    {"verdict", "Verdict: approve or reject", "text"},
                    {"summary", "Review summary", "textarea"}
                  ]}
                />
              </section>
              <section :if={reviewed?(@page)}>
                <h2 class="text-lg font-semibold">2. Acceptance</h2><UI.command_form
                  form={@forms["acceptance"]}
                  error={@errors["acceptance"]}
                  event="save:acceptance"
                  label="Record acceptance"
                  primary
                  fields={[
                    {"verdict", "Verdict: approve or reject", "text"},
                    {"summary", "Acceptance summary", "textarea"}
                  ]}
                />
              </section><p :if={!reviewed?(@page)}>
                Acceptance is available after an approved review of the current Task version.
              </p>
            </div>
            <p :if={!reviewable?(@page["task"])}>
              Review decisions are available only for an adopted Task awaiting review without an execution hold.
            </p>
            <ul id="task-decisions" class="mt-4 space-y-3">
              <li :for={d <- @page["decisions"]}>
                {d["kind"]}: {d["verdict"]} · {d["summary"]} · {d["inserted_at"]}
              </li>
            </ul>
          </.dm_card>
          <.dm_card>
            <:title>Attempts and uncertainty</:title><p :if={@page["attempts"] == []}>
              No attempts on this page.
            </p><ul class="space-y-4">
              <li :for={a <- @page["attempts"]} id={"attempt-" <> a["id"]}>
                <p>Attempt {a["number"]}: {a["state"]} · {a["agent_name"] || a["agent_id"]}</p><p class="break-all text-sm">
                  {a["id"]} · fence {a["fence"]} · generation {a["connection_generation"]}
                </p><p>
                  Lease expires: {a["lease_expires_at"]} · terminal: {a["terminal_at"] || "pending"}
                </p><p :if={!a["effects_resolved"]} class="text-warning">
                  Remote effects unresolved. Timeout or reconnect cannot authorize another execution.
                </p><p :if={a["effects_resolved"]}>Effects resolved</p>
                <p :if={outcome_status(a)}>Reported outcome: {outcome_status(a)}</p>
                <p
                  :if={outcome_summary(a)}
                  class="attempt-outcome-summary whitespace-pre-wrap break-words"
                >
                  Agent result summary: {outcome_summary(a)}
                </p>
              </li>
            </ul>
          </.dm_card>
          <.dm_card>
            <:title>Artifact references</:title><p :if={@page["artifacts"] == []}>
              No artifact references on this page.
            </p><ul id="task-artifacts" class="space-y-3">
              <li :for={a <- @page["artifacts"]} class="break-all">
                {a["kind"]}: <code>{a["locator"]}</code> · {a["digest"]}
              </li>
            </ul>
            <details id="artifact-section" class="mt-4" open={MapSet.member?(@expanded, "artifact")}>
              <summary phx-click="toggle_section" phx-value-name="artifact">
                Record artifact reference
              </summary><UI.command_form
                form={@forms["artifact"]}
                error={@errors["artifact"]}
                event="save:artifact"
                label="Add reference"
                fields={[
                  {"kind", "Kind", "text"},
                  {"locator", "Locator (displayed as text)", "text"},
                  {"digest", "Digest (optional)", "text"},
                  {"attempt_id", "Attempt UUID (optional)", "text"}
                ]}
              />
            </details>
          </.dm_card>
        </div>
        <.dm_card id="task-progress">
          <:title>Progress reports</:title><p :if={(@page["progress"] || []) == []}>
            No progress reports on this page.
          </p><ul class="space-y-3">
            <li :for={event <- @page["progress"] || []}>
              {event["data"]["summary"]} · {event["created_at"]}
            </li>
          </ul><p class="text-sm text-on-surface-variant">
            Progress is evidence of activity; terminal outcome, review, and acceptance remain separate.
          </p>
        </.dm_card>
        <.dm_card>
          <:title>Child tasks</:title><p :if={@page["children"] == []}>
            No child tasks on this page.
          </p><ul>
            <li :for={t <- @page["children"]}>
              <.link navigate={~p"/projects/#{@project_id}/tasks/#{t["id"]}"} class="text-primary">{t[
                "title"
              ]}</.link>
              · {t["state"]}
            </li>
          </ul>
        </.dm_card>
        <p class="text-sm text-on-surface-variant">
          History pagination applies to attempts, decisions, artifacts, and child tasks together.
        </p><UI.pagination
          offset={@page["offset"]}
          limit={@page["limit"]}
          total={max_total(@page)}
          path={~p"/projects/#{@project_id}/tasks/#{@task_id}"}
        />
      </div>
    </div>
    """
  end
end
