defmodule SamgitaWeb.DashboardLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    case Samgita.Management.overview(Samgita.Principal.operator()) do
      {:ok, overview} ->
        {:ok, assign(socket, page_title: "Agent Hub", overview: overview, error: nil)}

      {:error, _} ->
        {:ok,
         assign(socket,
           page_title: "Agent Hub",
           overview: nil,
           error: "Management state could not be loaded. Refresh and try again."
         )}
    end
  end
end
