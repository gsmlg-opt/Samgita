defmodule SamgitaWeb.ProjectsLive.Support do
  @moduledoc false
  use SamgitaWeb, :html

  def new_form(name, values \\ %{}, version \\ nil) do
    values = Map.new(values, fn {key, value} -> {key, display(value)} end)
    values = Map.merge(%{"command_id" => Ecto.UUID.generate()}, values)
    values = if version, do: Map.put(values, "expected_version", to_string(version)), else: values
    to_form(values, as: name)
  end

  def changed(name, values, version, completed? \\ false) do
    if completed? do
      new_form(name, Map.drop(values, ~w(command_id expected_version)), version)
    else
      # Form recovery must retain an unknown submission's receipt identity.
      to_form(values, as: name)
    end
  end

  def rejected(name, values, error) do
    fields = Map.get(error.details, :fields, []) ++ List.wrap(Map.get(error.details, :field))
    errors = Enum.map(fields, &{&1, {"is invalid", []}})
    to_form(values, as: name, errors: errors)
  end

  def error(error) do
    reason = Map.get(error.details, :reason)
    suffix = if reason, do: " (#{reason})", else: ""

    refresh =
      if error.code == :stale_version,
        do: ". Refresh to review the current version before retrying.",
        else: ""

    error.message <> suffix <> refresh
  end

  def attrs(values) do
    values
    |> Enum.reject(fn {key, value} ->
      value == "" &&
        key not in ~w(name title description summary parent_task_id required_capabilities roles types)
    end)
    |> Map.new(fn
      {"parent_task_id", ""} ->
        {"parent_task_id", nil}

      {"expected_version", value} ->
        {"expected_version", integer(value)}

      {key, value} when key in ~w(enabled primary idempotency_guaranteed risk_acknowledged) ->
        {key, value in [true, "true", "on"]}

      {key, value} when key in ~w(roles required_capabilities types) ->
        {key,
         if(is_list(value),
           do: value,
           else: String.split(value, ",", trim: true) |> Enum.map(&String.trim/1)
         )}

      pair ->
        pair
    end)
  end

  def payload(values) do
    case Jason.decode(values["payload"] || "{}") do
      {:ok, payload} when is_map(payload) -> {:ok, Map.put(attrs(values), "payload", payload)}
      _ -> {:error, Samgita.Error.new(:invalid, %{field: "payload"})}
    end
  end

  defp integer(value) when is_integer(value), do: value

  defp integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> nil
    end
  end

  defp display(value) when is_map(value), do: Jason.encode!(value)
  defp display(value) when is_list(value), do: Enum.join(value, ", ")
  defp display(nil), do: ""
  defp display(value), do: to_string(value)

  attr :form, :any, required: true
  attr :fields, :list, required: true
  attr :event, :string, required: true
  attr :label, :string, required: true
  attr :error, :string, default: nil
  attr :primary, :boolean, default: false

  def command_form(assigns) do
    ~H"""
    <.form
      for={@form}
      id={@form.name <> "-form"}
      phx-submit={@event}
      phx-change={"change:" <> @form.name}
      class="space-y-4"
    >
      <input type="hidden" name={@form[:command_id].name} value={@form[:command_id].value} />
      <input
        :if={@form[:expected_version].value}
        type="hidden"
        name={@form[:expected_version].name}
        value={@form[:expected_version].value}
      />
      <input
        :for={key <- ~w(schedule_id delivery_id)}
        :if={@form[key].value}
        type="hidden"
        name={@form[key].name}
        value={@form[key].value}
      />
      <p :if={@error} role="alert" class="text-error">{@error}</p>
      <.field :for={spec <- @fields} form={@form} spec={spec} />
      <.dm_btn
        native_submit
        variant={if @primary, do: "primary", else: "secondary"}
        phx-disable-with="Saving…"
      >
        {@label}
      </.dm_btn>
    </.form>
    """
  end

  attr :form, :any, required: true
  attr :spec, :any, required: true

  def field(assigns) do
    {name, label, type} = assigns.spec
    assigns = assign(assigns, name: name, label: label, type: type, field: assigns.form[name])

    ~H"""
    <.dm_input :if={@type not in ["textarea", "boolean"]} field={@field} label={@label} />
    <.dm_input :if={@type == "textarea"} field={@field} label={@label} type="textarea" />
    <.dm_select
      :if={@type == "boolean"}
      field={@field}
      label={@label}
      options={[{"true", "Yes"}, {"false", "No"}]}
    />
    """
  end

  attr :offset, :integer, required: true
  attr :limit, :integer, required: true
  attr :total, :integer, required: true
  attr :path, :string, required: true

  def pagination(assigns) do
    ~H"""
    <nav aria-label="History pagination" class="flex flex-wrap items-center gap-4 py-4">
      <.link
        :if={@offset > 0}
        patch={@path <> "?offset=#{max(@offset - @limit, 0)}"}
        class="text-primary"
      >Previous page</.link>
      <span>Page {div(@offset, @limit) + 1}</span>
      <.link
        :if={@offset + @limit < @total}
        patch={@path <> "?offset=#{@offset + @limit}"}
        class="text-primary"
      >Next page</.link>
    </nav>
    """
  end
end
