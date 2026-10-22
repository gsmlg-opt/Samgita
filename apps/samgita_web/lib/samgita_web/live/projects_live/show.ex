defmodule SamgitaWeb.ProjectsLive.Show do
  use SamgitaWeb, :live_view

  alias Samgita.{
    EventDelivery,
    Events,
    Management,
    Principal,
    Projects,
    Repositories,
    Schedules,
    Tasks
  }

  alias SamgitaWeb.ProjectsLive.Support, as: UI

  @impl true
  def mount(_, _, socket),
    do:
      {:ok,
       assign(socket,
         page_title: "Project",
         forms: %{},
         errors: %{},
         delivery: nil,
         expanded: MapSet.new(),
         completed_commands: MapSet.new()
       )}

  @impl true
  def handle_params(%{"id" => id} = params, _, socket) do
    expanded =
      if socket.assigns[:project_id] == id, do: socket.assigns.expanded, else: MapSet.new()

    socket = assign(socket, expanded: expanded)
    socket = load(assign(socket, project_id: id, params: params), true)
    {:noreply, restore_delivery(socket, params["delivery_id"])}
  end

  defp project_path(id, params),
    do: ~p"/projects/#{id}?#{Map.take(params, ~w(offset delivery_id))}"

  defp restore_delivery(socket, nil), do: socket

  defp restore_delivery(socket, id) do
    case EventDelivery.get(Principal.operator(), socket.assigns.project_id, id) do
      {:ok, delivery} ->
        form =
          UI.new_form(
            "recovery",
            %{"delivery_id" => id, "action" => "reconcile", "risk_acknowledged" => false},
            delivery["version"]
          )

        assign(socket,
          delivery: delivery,
          forms: Map.put(socket.assigns.forms, "recovery", form),
          expanded: MapSet.put(socket.assigns.expanded, "recovery")
        )

      {:error, error} ->
        put_flash(socket, :error, UI.error(error))
    end
  end

  defp load(socket, reset) do
    case Management.project(
           Principal.operator(),
           socket.assigns.project_id,
           socket.assigns.params
         ) do
      {:ok, page} ->
        socket = assign(socket, page: page, page_title: page["project"]["name"], load_error: nil)
        if reset, do: assign(socket, forms: forms(page), errors: %{}, delivery: nil), else: socket

      {:error, error} ->
        assign(socket, page: nil, load_error: UI.error(error))
    end
  end

  defp forms(page) do
    p = page["project"]

    %{
      "project" => UI.new_form("project", Map.take(p, ~w(name description)), p["version"]),
      "state" => UI.new_form("state", %{}, p["version"]),
      "repository" =>
        UI.new_form(
          "repository",
          %{"kind" => "git", "role" => "source", "primary" => false},
          p["version"]
        ),
      "member" =>
        UI.new_form("member", %{"roles" => "observer", "enabled" => true}, p["version"]),
      "routing" => UI.new_form("routing", %{"idempotency_guaranteed" => false}, p["version"]),
      "task" => UI.new_form("task"),
      "schedule" =>
        UI.new_form("schedule", %{
          "expression" => "0 * * * *",
          "timezone" => "Etc/UTC",
          "event_type" => "schedule.check",
          "payload" => %{},
          "enabled" => true
        }),
      "event" => UI.new_form("event", %{"payload" => %{}})
    }
  end

  @impl true
  def handle_event("toggle_section", %{"name" => name}, socket)
      when name in ~w(state repository choices member routing task schedule recovery) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, name),
        do: MapSet.delete(expanded, name),
        else: MapSet.put(expanded, name)

    {:noreply, assign(socket, expanded: expanded)}
  end

  def handle_event("change:recovery", %{"recovery" => values}, socket) do
    case EventDelivery.get(Principal.operator(), socket.assigns.project_id, values["delivery_id"]) do
      {:ok, delivery} ->
        form =
          UI.changed(
            "recovery",
            values,
            delivery["version"],
            MapSet.member?(socket.assigns.completed_commands, values["command_id"])
          )

        {:noreply,
         assign(socket,
           delivery: delivery,
           forms: Map.put(socket.assigns.forms, "recovery", form),
           expanded: MapSet.put(socket.assigns.expanded, "recovery"),
           errors: Map.delete(socket.assigns.errors, "recovery")
         )}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, UI.error(error))}
    end
  end

  def handle_event("change:" <> name, params, socket) do
    values = Map.fetch!(params, name)
    version = version(socket, name, values)

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
             version,
             MapSet.member?(socket.assigns.completed_commands, values["command_id"])
           )
         ),
       errors: Map.delete(socket.assigns.errors, name)
     )}
  end

  def handle_event("delivery", %{"id" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         project_path(
           socket.assigns.project_id,
           Map.put(socket.assigns.params, "delivery_id", id)
         )
     )}
  end

  def handle_event("edit_schedule", %{"id" => id}, socket) do
    schedule = Enum.find(socket.assigns.page["schedules"], &(&1["id"] == id))

    if schedule do
      values = Map.put(schedule, "schedule_id", id)

      {:noreply,
       assign(socket,
         expanded: MapSet.put(socket.assigns.expanded, "schedule"),
         forms:
           Map.put(
             socket.assigns.forms,
             "schedule",
             UI.new_form("schedule", values, schedule["version"])
           )
       )}
    else
      {:noreply,
       put_flash(socket, :error, "Schedule not found. Refresh the current Project history.")}
    end
  end

  def handle_event("new_schedule", _, socket) do
    {:noreply,
     assign(socket,
       expanded: MapSet.put(socket.assigns.expanded, "schedule"),
       forms: Map.put(socket.assigns.forms, "schedule", forms(socket.assigns.page)["schedule"])
     )}
  end

  def handle_event("save:" <> name, params, socket) do
    socket = assign(socket, expanded: MapSet.put(socket.assigns.expanded, name))
    values = Map.fetch!(params, name)
    result = execute(name, socket.assigns.project_id, values)

    case result do
      {:ok, _} ->
        socket = load(socket, false)

        updated =
          forms(socket.assigns.page)
          |> Map.merge(Map.take(socket.assigns.forms, ["recovery"]))
          |> Map.put(name, to_form(values, as: name))

        socket = refresh_delivery(socket, name, values)

        {:noreply,
         socket
         |> assign(
           forms: updated,
           errors: Map.delete(socket.assigns.errors, name),
           completed_commands: MapSet.put(socket.assigns.completed_commands, values["command_id"])
         )
         |> put_flash(:info, "Saved. Repeated submission uses the same command receipt.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           forms: Map.put(socket.assigns.forms, name, UI.rejected(name, values, error)),
           errors: Map.put(socket.assigns.errors, name, UI.error(error))
         )}
    end
  end

  defp refresh_delivery(socket, "recovery", values) do
    case EventDelivery.get(Principal.operator(), socket.assigns.project_id, values["delivery_id"]) do
      {:ok, delivery} -> assign(socket, delivery: delivery)
      _ -> socket
    end
  end

  defp refresh_delivery(socket, _, _), do: socket

  defp version(socket, "schedule", values) do
    case Enum.find(socket.assigns.page["schedules"], &(&1["id"] == values["schedule_id"])) do
      nil -> nil
      schedule -> schedule["version"]
    end
  end

  defp version(socket, "recovery", _), do: socket.assigns.delivery["version"]

  defp version(socket, name, _) when name in ~w(project state repository member routing),
    do: socket.assigns.page["project"]["version"]

  defp version(_, _, _), do: nil

  defp execute(name, id, values) when name in ~w(schedule event) do
    with {:ok, attrs} <- UI.payload(values) do
      case {name, attrs["schedule_id"]} do
        {"event", _} ->
          Events.trigger(Principal.operator(), id, attrs)

        {"schedule", nil} ->
          Schedules.create(Principal.operator(), id, attrs)

        {"schedule", schedule_id} ->
          Schedules.update(Principal.operator(), id, schedule_id, attrs)
      end
    end
  end

  defp execute(name, id, values) do
    a = UI.attrs(values)
    operator = Principal.operator()

    case name do
      "project" -> Projects.update(operator, id, a)
      "state" -> Projects.transition(operator, id, a)
      "repository" -> Repositories.associate(operator, id, a)
      "member" -> Projects.put_member(operator, id, a)
      "routing" -> Events.configure(operator, id, a)
      "task" -> Tasks.create(operator, id, a)
      "recovery" -> EventDelivery.recover(operator, id, a["delivery_id"], a)
    end
  end

  defp max_total(page), do: page["totals"] |> Map.values() |> Enum.max(fn -> 0 end)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl space-y-6 p-4 sm:p-6">
      <.link navigate={~p"/projects"} class="text-primary">All projects</.link>
      <p :if={@load_error} role="alert">{@load_error}</p>
      <div :if={@page} class="space-y-6">
        <header>
          <h1 class="text-3xl font-bold">{@page["project"]["name"]}</h1><p>
            {@page["project"]["description"]}
          </p><p class="text-on-surface-variant">
            {@page["project"]["state"]} · version {@page["project"]["version"]} · {@project_id}
          </p><.link href={project_path(@project_id, @params)} class="text-primary">Refresh persisted state</.link>
        </header>
        <div class="grid items-start gap-6 lg:grid-cols-2">
          <.dm_card>
            <:title>Project settings</:title><UI.command_form
              form={@forms["project"]}
              error={@errors["project"]}
              event="save:project"
              label="Save project"
              fields={[{"name", "Name", "text"}, {"description", "Description", "textarea"}]}
            />
            <details id="state-section" class="mt-4" open={MapSet.member?(@expanded, "state")}>
              <summary phx-click="toggle_section" phx-value-name="state">
                Change project state
              </summary><p>
                Allowed states: active, paused, archived. Restoring an archive requires a reason and returns it to paused.
              </p><UI.command_form
                form={@forms["state"]}
                error={@errors["state"]}
                event="save:state"
                label="Change state"
                fields={[{"state", "State", "text"}, {"reason", "Reason", "textarea"}]}
              />
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Repositories</:title><p :if={@page["repositories"] == []}>
              No repositories associated.
            </p>
            <ul>
              <li :for={r <- @page["repositories"]}>
                {r["repository"]["display_name"] || r["repository_id"]} · {r["role"]} · primary: {to_string(
                  r["primary"]
                )} · {r["repository"]["verification"]}
              </li>
            </ul>
            <details
              id="repository-section"
              class="mt-4"
              open={MapSet.member?(@expanded, "repository")}
            >
              <summary phx-click="toggle_section" phx-value-name="repository">
                Associate repository
              </summary><UI.command_form
                form={@forms["repository"]}
                error={@errors["repository"]}
                event="save:repository"
                label="Associate repository"
                fields={[
                  {"repository_id", "Existing repository UUID (optional)", "text"},
                  {"kind", "Kind: git or local", "text"},
                  {"display_name", "Repository name", "text"},
                  {"url", "URL alias (optional)", "text"},
                  {"role", "Role: source, documentation, reference", "text"},
                  {"primary", "Primary", "boolean"}
                ]}
              />
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Agent membership and routing</:title><p :if={@page["memberships"] == []}>
              No Agent memberships.
            </p>
            <ul>
              <li :for={m <- @page["memberships"]}>
                {m["agent_name"] || m["agent_id"]} · {Enum.join(m["roles"], ", ")} · enabled: {to_string(
                  m["enabled"]
                )}
              </li>
            </ul>
            <p class="my-3">
              Responsible Agent: {if @page["routing"],
                do: @page["routing"]["agent_id"],
                else: "Not configured"}
            </p>
            <details id="choices-section" open={MapSet.member?(@expanded, "choices")}>
              <summary phx-click="toggle_section" phx-value-name="choices">
                Registered Agent choices
              </summary><p>
                Showing {length(@page["agent_choices"] || [])} of {@page["agent_choices_total"]} registered Agents. Enter any registered UUID below.
              </p><ul>
                <li :for={a <- @page["agent_choices"] || []}>
                  {a["name"]} · {a["id"]} · enabled: {to_string(a["enabled"])}
                </li>
              </ul><.link navigate={~p"/agents"} class="text-primary">Full Agent catalog</.link>
            </details>
            <details id="member-section" class="mt-4" open={MapSet.member?(@expanded, "member")}>
              <summary phx-click="toggle_section" phx-value-name="member">
                Grant or update membership
              </summary><UI.command_form
                form={@forms["member"]}
                error={@errors["member"]}
                event="save:member"
                label="Save membership"
                fields={[
                  {"agent_id", "Agent UUID", "text"},
                  {"roles", "Roles (comma separated): observer, worker, manager, reviewer", "text"},
                  {"enabled", "Membership enabled", "boolean"}
                ]}
              />
            </details>
            <details id="routing-section" class="mt-4" open={MapSet.member?(@expanded, "routing")}>
              <summary phx-click="toggle_section" phx-value-name="routing">
                Configure responsible Agent
              </summary><p>
                Requires an enabled manager with approved and advertised project_events.v1. Enable idempotency only after reviewing the Agent contract.
              </p><UI.command_form
                form={@forms["routing"]}
                error={@errors["routing"]}
                event="save:routing"
                label="Save routing"
                fields={[
                  {"agent_id", "Agent UUID", "text"},
                  {"types", "Event types (comma separated; empty means all)", "text"},
                  {"idempotency_guaranteed", "Reviewed idempotency guarantee", "boolean"}
                ]}
              />
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Tasks</:title><p :if={@page["tasks"] == []}>No tasks on this page.</p><ul class="space-y-2">
              <li :for={t <- @page["tasks"]}>
                <.link navigate={~p"/projects/#{@project_id}/tasks/#{t["id"]}"} class="text-primary">{t[
                  "title"
                ]}</.link>
                · {t["state"]}
                <span :if={t["execution_hold"]}>· execution hold</span><span :if={!t["adopted"]}>· historical review required</span>
              </li>
            </ul>
            <details id="task-section" class="mt-4" open={MapSet.member?(@expanded, "task")}>
              <summary phx-click="toggle_section" phx-value-name="task">Create task</summary><UI.command_form
                form={@forms["task"]}
                error={@errors["task"]}
                event="save:task"
                label="Create task"
                primary
                fields={[
                  {"title", "Title", "text"},
                  {"description", "Description", "textarea"},
                  {"parent_task_id", "Parent Task UUID (optional)", "text"},
                  {"required_capabilities", "Required capabilities (comma separated)", "text"}
                ]}
              />
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Schedules</:title><p>
              Schedules emit events; they do not authorize Task execution. Updates start a new revision at the specified UTC cursor, or now.
            </p><p :if={@page["schedules"] == []}>No schedules on this page.</p>
            <ul>
              <li :for={s <- @page["schedules"]} class="my-3">
                {s["expression"]} · {s["timezone"]} · revision {s["revision"]} · enabled: {to_string(
                  s["enabled"]
                )}
                <button
                  type="button"
                  class="btn btn-ghost"
                  phx-click="edit_schedule"
                  phx-value-id={s["id"]}
                >Edit or disable</button>
              </li>
            </ul>
            <details id="schedule-section" class="mt-4" open={MapSet.member?(@expanded, "schedule")}>
              <summary phx-click="toggle_section" phx-value-name="schedule">
                Create or edit schedule
              </summary>
              <UI.command_form
                form={@forms["schedule"]}
                error={@errors["schedule"]}
                event="save:schedule"
                label="Save schedule"
                fields={[
                  {"expression", "Cron expression", "text"},
                  {"timezone", "Timezone", "text"},
                  {"event_type", "Event type: schedule.check", "text"},
                  {"payload", "Payload JSON object", "textarea"},
                  {"start_at", "Start at UTC ISO timestamp (optional)", "text"},
                  {"enabled", "Schedule enabled", "boolean"}
                ]}
              /><button type="button" class="btn btn-ghost" phx-click="new_schedule">New schedule</button>
            </details>
          </.dm_card>
          <.dm_card>
            <:title>Manual event</:title><p class="mb-4">
              A manual event requests attention. It does not change Task state or grant execution.
            </p><UI.command_form
              form={@forms["event"]}
              error={@errors["event"]}
              event="save:event"
              label="Emit manual event"
              fields={[
                {"payload", "Payload JSON object (reason, summary, task_id, reference)", "textarea"}
              ]}
            />
          </.dm_card>
        </div>
        <.dm_card id="github-mappings">
          <:title>GitHub repository mappings</:title><p>
            Read-only integration evidence. Remote GitHub writes remain disabled.
          </p><p :if={@page["github_mappings"] == []}>No approved GitHub mappings on this page.</p><ul class="space-y-4">
            <li :for={mapping <- @page["github_mappings"]} class="break-words">
              <p>
                Mapping {mapping["id"]} · enabled: {to_string(mapping["enabled"])} · version {mapping[
                  "version"
                ]}
              </p><dl class="grid gap-2 sm:grid-cols-2">
                <div :for={{key, value} <- Map.drop(mapping, ["id", "enabled", "version"])}>
                  <dt class="text-sm text-on-surface-variant">{key}</dt><dd>
                    {if is_map(value) || is_list(value), do: Jason.encode!(value), else: value}
                  </dd>
                </div>
              </dl>
            </li>
          </ul>
        </.dm_card>
        <.dm_card>
          <:title>Event and delivery history</:title><p>
            All lists use this history page offset. Receipt, processing completion, and Task acceptance are separate.
          </p>
          <div class="grid gap-6 lg:grid-cols-2">
            <section>
              <h2 class="text-lg font-semibold">Events</h2><p :if={@page["events"] == []}>
                No events on this page.
              </p><ul>
                <li :for={e <- @page["events"]} class="break-words py-2">
                  <details>
                    <summary>#{e["sequence"]} {e["type"]} · {e["created_at"]}</summary><p>
                      Event: {e["id"]}
                    </p><p>Source: {e["source"]} · {e["source_id"]}</p><p>
                      Resource: {e["resource_type"]} · {e["resource_id"]}
                    </p><p>Correlation: {e["correlation_id"]} · causation: {e["causation_id"]}</p><pre class="overflow-auto whitespace-pre-wrap break-words">{Jason.encode!(e["data"], pretty: true)}</pre>
                  </details>
                </li>
              </ul>
            </section>
            <section>
              <h2 class="text-lg font-semibold">Deliveries</h2><p :if={@page["deliveries"] == []}>
                No deliveries on this page.
              </p><ul>
                <li :for={d <- @page["deliveries"]} class="py-2">
                  <button
                    type="button"
                    class="btn btn-ghost"
                    phx-click="delivery"
                    phx-value-id={d["id"]}
                  >{d["state"]} · {d["attempt_count"]}/{d["max_attempts"]} attempts</button><p>
                    Processing: {d["processing_status"] || "not reported"} · received: {d[
                      "transport_received_at"
                    ] || "pending"}
                  </p><p
                    :if={d["remote_outcome_uncertain"] || d["state"] == "uncertain"}
                    class="text-warning"
                  >
                    Remote outcome uncertain. Reconcile status before redelivery.
                  </p><p
                    :if={d["state"] == "dead_letter" || d["cycle_attempt_count"] >= d["max_attempts"]}
                    class="text-error"
                  >
                    Retries exhausted; explicit recovery required.
                  </p><p :if={d["state"] == "authentication_failed"} class="text-error">
                    Authentication failed. Review external credential references and routing before recovery.
                  </p><p :if={d["state"] == "legacy_unreviewed"} class="text-warning">
                    Legacy delivery requires reviewed routing before explicit recovery.
                  </p>
                </li>
              </ul>
            </section>
          </div>
          <UI.pagination
            offset={@page["offset"]}
            limit={@page["limit"]}
            total={max_total(@page)}
            path={~p"/projects/#{@project_id}"}
          />
        </.dm_card>
        <.dm_card :if={@delivery} id="delivery-detail">
          <:title>Delivery evidence and recovery</:title><p class="break-all">
            {@delivery["id"]} · {@delivery["state"]} · operation {@delivery["operation_id"]}
          </p>
          <ul>
            <li :for={a <- @delivery["attempts"]}>
              Attempt {a["number"]}: {a["action"]} · {a["state"]} · {a["error_class"]} {a[
                "error_code"
              ]}
            </li>
          </ul>
          <ul>
            <li :for={a <- @delivery["acknowledgements"]}>
              Acknowledgement: {a["acceptance"]} · {a["processing_status"]} · {a["recorded_at"]}
            </li>
          </ul>
          <ul>
            <li :for={a <- @delivery["recovery_actions"]}>
              Recovery: {a["action"]} · {a["reason"]} · {a["evidence_ref"]} · {a["inserted_at"]}
            </li>
          </ul>
          <details id="recovery-section" class="mt-4" open={MapSet.member?(@expanded, "recovery")}>
            <summary phx-click="toggle_section" phx-value-name="recovery">
              Explicit operator recovery
            </summary><p>
              Redelivery can duplicate remote effects. Reconcile queries the stable operation status. Cancellation does not prove remote effects stopped.
            </p><UI.command_form
              form={@forms["recovery"]}
              error={@errors["recovery"]}
              event="save:recovery"
              label="Record recovery action"
              fields={[
                {"action", "Action: reconcile, redeliver, cancel", "text"},
                {"reason", "Reason", "textarea"},
                {"evidence_ref", "Evidence reference", "text"},
                {"risk_acknowledged", "Acknowledge duplicate-effect risk", "boolean"}
              ]}
            />
          </details>
        </.dm_card>
      </div>
    </div>
    """
  end
end
