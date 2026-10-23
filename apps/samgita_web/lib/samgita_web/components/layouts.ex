defmodule SamgitaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SamgitaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group using PhoenixDuskmoon's dm_flash_group.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    # Accessibility limitation tracked in duskmoon-dev/phoenix-duskmoon-ui#162:
    # the connected toast remains in the accessibility tree.
    ~H"""
    <.dm_flash_group flash={@flash} />
    """
  end
end
