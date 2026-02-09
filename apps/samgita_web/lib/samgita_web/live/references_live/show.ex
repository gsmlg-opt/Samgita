defmodule SamgitaWeb.ReferencesLive.Show do
  use SamgitaWeb, :live_view

  alias Samgita.References

  @impl true
  def mount(%{"filename" => filename_parts}, _session, socket) do
    # Glob segments return a list, join them to get the filename
    filename = Enum.join(filename_parts, "/")

    case References.get_reference(filename) do
      {:ok, reference} ->
        {:ok,
         assign(socket,
           page_title: reference.title,
           reference: reference
         )}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Reference not found")
         |> push_navigate(to: ~p"/references")}
    end
  end
end
