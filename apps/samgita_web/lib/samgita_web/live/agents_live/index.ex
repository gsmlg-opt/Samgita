defmodule SamgitaWeb.AgentsLive.Index do
  use SamgitaWeb, :live_view
  alias Samgita.{Agents, Management, Principal}
  alias SamgitaWeb.AgentsLive.Components
  import SamgitaWeb.AgentsLive.Components, only: [agent_fields: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Agents",
       form: to_form(Components.defaults(), as: :agent),
       error: nil,
       load_error: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Management.agents(Principal.operator(), %{
           "limit" => 25,
           "offset" => Components.offset(params)
         }) do
      {:ok, page} ->
        {:noreply, assign(socket, page: page, load_error: nil)}

      {:error, error} ->
        {:noreply,
         assign(socket,
           page: %{"data" => [], "offset" => 0, "limit" => 25, "total" => 0},
           load_error: Components.error_message(error)
         )}
    end
  end

  @impl true
  def handle_event("change", %{"agent" => params}, socket) do
    values = params |> Components.agent_attrs() |> Components.form_values()
    {:noreply, assign(socket, form: to_form(values, as: :agent), error: nil)}
  end

  def handle_event("register", %{"agent" => params}, socket) do
    attrs = Components.agent_attrs(params)

    case Agents.register(Principal.operator(), attrs) do
      {:ok, agent} ->
        {:noreply, push_navigate(socket, to: ~p"/agents/#{agent["id"]}")}

      {:error, error} ->
        {:noreply,
         assign(socket,
           form: to_form(Components.form_values(attrs), as: :agent),
           error: Components.error_message(error)
         )}
    end
  end
end
