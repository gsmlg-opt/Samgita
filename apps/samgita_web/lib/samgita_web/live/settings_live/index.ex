defmodule SamgitaWeb.SettingsLive.Index do
  @moduledoc "Operator console settings. Appearance keeps the browser-local theme."
  use SamgitaWeb, :live_view

  @sections [{"appearance", "Appearance"}]
  @keys Enum.map(@sections, &elem(&1, 0))

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Settings", sections: @sections)}

  @impl true
  def handle_params(params, _uri, socket) do
    section = if params["section"] in @keys, do: params["section"], else: "appearance"
    {:noreply, assign(socket, section: section)}
  end
end
