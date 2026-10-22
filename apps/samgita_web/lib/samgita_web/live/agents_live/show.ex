defmodule SamgitaWeb.AgentsLive.Show do
  use SamgitaWeb, :live_view
  alias Samgita.{Agents, Management, Principal}
  alias SamgitaWeb.AgentsLive.Components
  import SamgitaWeb.AgentsLive.Components, only: [agent_fields: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Agent",
       detail: nil,
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

        assign(socket,
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
