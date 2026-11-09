defmodule SamgitaWeb.AgentsLive.Show do
  use SamgitaWeb, :live_view
  alias Samgita.{Agents, CodexHosts, Management, Principal}
  alias SamgitaWeb.AgentsLive.Components
  import SamgitaWeb.AgentsLive.Components, only: [agent_fields: 1]

  @codex_fields ~w(url token_ref connect_address allow_insecure ssh_host ssh_port ssh_user ssh_key_ref known_hosts remote_codex_path remote_socket_path ensure_daemon)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Samgita.PubSub, CodexHosts.Runtime.topic())

    {:ok,
     assign(socket,
       page_title: "Agent",
       detail: nil,
       codex_host: nil,
       codex_form: nil,
       codex_projects: nil,
       project_form: new_project_form(),
       project_error: nil,
       error: nil,
       load_error: nil,
       credential_reset: 0
     )}
  end

  @impl true
  def handle_params(%{"id" => id} = params, _uri, socket) do
    {:noreply, socket |> assign(agent_id: id, offset: Components.offset(params)) |> load()}
  end

  @impl true
  def handle_event("change", %{"agent" => params}, socket) do
    values = params |> Components.agent_attrs() |> Components.form_values()
    {:noreply, assign(socket, form: to_form(values, as: :agent), error: nil)}
  end

  def handle_event("save", %{"agent" => params}, socket) do
    case Agents.update(
           Principal.operator(),
           socket.assigns.agent_id,
           Components.agent_attrs(params)
         ) do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, "Agent updated.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           form: to_form(Components.form_values(Components.agent_attrs(params)), as: :agent),
           error: Components.error_message(error)
         )}
    end
  end

  def handle_event("put_credential", %{"credential" => params}, socket) do
    attrs =
      params
      |> Map.take(~w(command_id expected_version credential reference expires_at))
      |> Components.version_attrs()

    attrs = if attrs["expires_at"] in [nil, ""], do: Map.delete(attrs, "expires_at"), else: attrs
    result = Agents.put_credential(Principal.operator(), socket.assigns.agent_id, attrs)
    socket = update(socket, :credential_reset, &(&1 + 1))

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> load() |> put_flash(:info, "Credential registered. Only its digest is stored.")}

      {:error, error} ->
        safe =
          params
          |> Map.take(~w(command_id expected_version reference expires_at))
          |> Map.put("credential", "")

        {:noreply,
         assign(socket,
           credential_form: to_form(safe, as: :credential),
           error: Components.error_message(error)
         )}
    end
  end

  def handle_event("change_codex_host", %{"codex_host" => params}, socket),
    do: {:noreply, assign(socket, codex_form: to_form(params, as: :codex_host))}

  def handle_event("save_codex_host", %{"codex_host" => params}, socket) do
    attrs =
      params
      |> Map.take(["command_id", "expected_version", "transport" | @codex_fields])
      |> Map.reject(fn {_key, value} -> value == "" end)
      |> Map.update("allow_insecure", false, &(&1 == "true"))
      |> Map.update("ensure_daemon", false, &(&1 == "true"))
      |> Map.put("agent_id", socket.assigns.agent_id)
      |> Components.version_attrs()

    case CodexHosts.configure(Principal.operator(), attrs) do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, "Codex host saved.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           codex_form: to_form(params, as: :codex_host),
           error: Components.error_message(error)
         )}
    end
  end

  def handle_event(event, _params, %{assigns: %{codex_host: host}} = socket)
      when event in ~w(enable_codex_host disable_codex_host) and is_map(host) do
    fun = if event == "enable_codex_host", do: &CodexHosts.enable/3, else: &CodexHosts.disable/3

    attrs = %{"command_id" => Ecto.UUID.generate(), "expected_version" => host["version"]}

    case fun.(Principal.operator(), host["id"], attrs) do
      {:ok, _} -> {:noreply, load(socket)}
      {:error, error} -> {:noreply, assign(socket, error: Components.error_message(error))}
    end
  end

  def handle_event("reconnect_codex_host", _params, %{assigns: %{codex_host: host}} = socket)
      when is_map(host) do
    case CodexHosts.reconnect(Principal.operator(), host["id"]) do
      :ok -> {:noreply, put_flash(socket, :info, "Reconnecting to the Codex host.")}
      {:error, error} -> {:noreply, assign(socket, error: Components.error_message(error))}
    end
  end

  def handle_event("revoke_credential", %{"revoke" => params}, socket) do
    attrs =
      params
      |> Map.take(~w(command_id expected_version credential_id))
      |> Components.version_attrs()

    case Agents.revoke_credential(Principal.operator(), socket.assigns.agent_id, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, "Credential revoked. Connections using it are revoked.")}

      {:error, error} ->
        {:noreply, assign(socket, error: Components.error_message(error))}
    end
  end

  def handle_event("change_project", %{"project" => params}, socket),
    do:
      {:noreply, assign(socket, project_form: to_form(params, as: :project), project_error: nil)}

  def handle_event(
        "add_project",
        %{"project" => params},
        %{assigns: %{codex_host: host}} = socket
      )
      when is_map(host) do
    case CodexHosts.create_project(Principal.operator(), host["id"], params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(project_form: new_project_form(), project_error: nil)
         |> load_projects()
         |> put_flash(:info, "Project #{project["name"]} added to Codex.")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           project_form: to_form(params, as: :project),
           project_error: codex_error(error)
         )}
    end
  end

  def handle_event("refresh_projects", _params, socket), do: {:noreply, load_projects(socket)}

  @impl true
  def handle_info(
        {:codex_host_status, id, status},
        %{assigns: %{codex_host: %{"id" => id}}} = socket
      ) do
    socket = update(socket, :codex_host, &Map.put(&1, "status", status))

    if status["state"] == "connected",
      do: {:noreply, load_projects(socket)},
      else: {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_async(:projects, {:ok, {:ok, projects}}, socket),
    do: {:noreply, assign(socket, codex_projects: {:ok, projects})}

  def handle_async(:projects, {:ok, {:error, error}}, socket),
    do: {:noreply, assign(socket, codex_projects: {:error, codex_error(error)})}

  def handle_async(:projects, {:exit, _}, socket),
    do: {:noreply, assign(socket, codex_projects: {:error, codex_error(nil)})}

  # Codex owns its projects; they are read live from the connected host.
  defp load_projects(%{assigns: %{codex_host: %{"id" => id}}} = socket) do
    if connected?(socket),
      do: start_async(socket, :projects, fn -> CodexHosts.projects(Principal.operator(), id) end),
      else: socket
  end

  defp load_projects(socket), do: socket

  defp new_project_form,
    do: to_form(%{"name" => "", "path" => "", "command_id" => Ecto.UUID.generate()}, as: :project)

  defp codex_error(%Samgita.Error{code: :codex_unavailable}),
    do: "Codex is not connected. Start the connection and try again."

  defp codex_error(%Samgita.Error{code: :codex_request_failed}),
    do: "Codex rejected the request. Check the name and that the path exists on that machine."

  defp codex_error(%Samgita.Error{code: :invalid} = error), do: Components.error_message(error)
  defp codex_error(_), do: "Codex could not be reached."

  defp load_codex_host(socket, %{"runtime_driver" => "codex"} = agent) do
    {:ok, host} = CodexHosts.for_agent(Principal.operator(), agent["id"])

    values =
      Map.new(@codex_fields, &{&1, ""})
      |> Map.merge(%{
        "transport" => "websocket",
        "allow_insecure" => false,
        "ensure_daemon" => false
      })
      |> Map.merge(Map.take(host || %{}, ["transport" | @codex_fields]))
      |> Map.new(fn {key, value} -> {key, if(is_nil(value), do: "", else: value)} end)
      |> Map.put("command_id", Ecto.UUID.generate())
      |> Map.put("expected_version", host && host["version"])

    socket
    |> assign(codex_host: host, codex_form: to_form(values, as: :codex_host))
    |> load_projects()
  end

  defp load_codex_host(socket, _agent), do: assign(socket, codex_host: nil, codex_form: nil)

  defp load(socket) do
    case Management.agent(Principal.operator(), socket.assigns.agent_id, %{
           "limit" => 25,
           "offset" => socket.assigns.offset
         }) do
      {:ok, detail} ->
        agent = detail["agent"]

        form =
          agent
          |> Components.form_values()
          |> Map.put("command_id", Ecto.UUID.generate())
          |> Map.put("expected_version", agent["version"])

        credential = %{
          "command_id" => Ecto.UUID.generate(),
          "expected_version" => agent["version"],
          "credential" => "",
          "reference" => "",
          "expires_at" => ""
        }

        revoke_forms =
          Map.new(detail["credentials"], fn c ->
            {c["id"],
             to_form(
               %{
                 "command_id" => Ecto.UUID.generate(),
                 "expected_version" => agent["version"],
                 "credential_id" => c["id"]
               },
               as: :revoke
             )}
          end)

        total = detail["totals"] |> Map.values() |> Enum.max(fn -> 0 end)

        socket
        |> load_codex_host(agent)
        |> assign(
          detail: detail,
          page_title: agent["name"],
          form: to_form(form, as: :agent),
          credential_form: to_form(credential, as: :credential),
          revoke_forms: revoke_forms,
          total: total,
          error: nil,
          load_error: nil
        )

      {:error, error} ->
        assign(socket, detail: nil, load_error: Components.error_message(error))
    end
  end
end
