defmodule SamgitaWeb.CoreComponents do
  @moduledoc """
  Thin wrappers around PhoenixDuskmoon components for backward-compatible usage.

  Direct dm_* components from PhoenixDuskmoon are preferred in new code.
  These wrappers exist for templates that use the original <.input>, <.button>,
  <.table>, <.list>, <.header> API.
  """
  use Phoenix.Component
  use Gettext, backend: SamgitaWeb.Gettext
  use PhoenixDuskmoon.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders a button. Delegates to dm_btn.
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any, default: nil
  attr :variant, :string, default: "primary"
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <.dm_btn variant={@variant} class={@class} {@rest}>
      {render_slot(@inner_block)}
    </.dm_btn>
    """
  end

  @doc """
  Renders an input. Delegates to dm_input / dm_select / dm_textarea / dm_checkbox.
  """
  attr :id, :any, default: nil
  attr :name, :any, default: nil
  attr :label, :string, default: nil
  attr :value, :any, default: nil

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, default: [], doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{}} = assigns) do
    ~H"""
    <.dm_input field={@field} label={@label} type={@type} class={@class} {@rest} />
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <.dm_select
      id={@id}
      name={@name}
      label={@label}
      value={@value}
      options={@options}
      prompt={@prompt}
      multiple={@multiple}
      errors={@errors}
      class={@class}
      {@rest}
    />
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <.dm_textarea id={@id} name={@name} label={@label} value={@value} errors={@errors} class={@class} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    ~H"""
    <.dm_checkbox id={@id} name={@name} label={@label} value={@value} checked={@checked} errors={@errors} class={@class} {@rest} />
    """
  end

  def input(assigns) do
    ~H"""
    <.dm_input id={@id} name={@name} label={@label} value={@value} type={@type} errors={@errors} class={@class} {@rest} />
    """
  end

  @doc """
  Renders a page header with title, optional subtitle, and actions.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8 text-on-surface">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-on-surface-variant">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with streaming support.
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-striped">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-item">
        <div class="font-bold text-on-surface">{item.title}</div>
        <div class="text-on-surface-variant">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com) via the heroicons CSS plugin.
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(SamgitaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SamgitaWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
