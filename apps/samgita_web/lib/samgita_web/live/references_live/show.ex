defmodule SamgitaWeb.ReferencesLive.Show do
  use SamgitaWeb, :live_view

  alias Samgita.References

  @impl true
  def mount(%{"filename" => filename_parts}, _session, socket) do
    # Glob segments return a list, join them to get the filename
    filename = Enum.join(filename_parts, "/")

    # Defense-in-depth: reject path traversal attempts
    if String.contains?(filename, "..") do
      {:ok,
       socket
       |> put_flash(:error, "Invalid reference path")
       |> push_navigate(to: ~p"/references")}
    else
      mount_reference(filename, socket)
    end
  end

  defp mount_reference(filename, socket) do
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
