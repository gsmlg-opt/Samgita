defmodule SamgitaWeb.DashboardLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Agent Hub")}
  end
end
