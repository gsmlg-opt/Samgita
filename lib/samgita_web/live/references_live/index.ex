defmodule SamgitaWeb.ReferencesLive.Index do
  use SamgitaWeb, :live_view

  alias Samgita.References

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "References",
       references: References.list_by_category(),
       selected_category: nil
     )}
  end

  @impl true
  def handle_params(%{"category" => category}, _uri, socket) do
    {:noreply, assign(socket, selected_category: category)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, selected_category: nil)}
  end

  @impl true
  def handle_event("select_category", %{"category" => category}, socket) do
    {:noreply, push_patch(socket, to: ~p"/references?category=#{category}")}
  end

  @impl true
  def handle_event("clear_selection", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/references")}
  end
end
