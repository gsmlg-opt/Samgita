defmodule SamgitaWeb.AgentsLive.Components do
  use SamgitaWeb, :html

  attr :form, Phoenix.HTML.Form, required: true

  def agent_fields(assigns) do
    assigns = assign(assigns, :capabilities, Enum.map(SamgitaProtocol.capabilities(), &{&1, &1}))

    ~H"""
    <input type="hidden" name={@form[:command_id].name} value={@form[:command_id].value} />
    <input
      :if={@form[:expected_version].value}
      type="hidden"
      name={@form[:expected_version].name}
      value={@form[:expected_version].value}
    />
    <div class="grid gap-4 sm:grid-cols-2">
      <.dm_input field={@form[:name]} label={gettext("Name")} required maxlength="200" />
      <.dm_input
        field={@form[:implementation]}
        label={gettext("Implementation label")}
        maxlength="200"
        helper={gettext("Descriptive only; this label grants no authority.")}
      />
      <.dm_input
        field={@form[:capacity]}
        type="number"
        label={gettext("Capacity")}
        min="1"
        max="1000"
        required
      />
      <.dm_input
        field={@form[:enabled]}
        type="checkbox"
        label={gettext("Enabled for authorized work")}
      />
    </div>
    <fieldset class="space-y-4">
      <legend class="font-semibold">{gettext("Protocol and outbound endpoint")}</legend>
      <div class="grid gap-4 sm:grid-cols-2">
        <.dm_input
          field={@form[:protocol]}
          type="select"
          label={gettext("Protocol")}
          options={[{"Samgita", "samgita"}]}
        />
        <.dm_input
          field={@form[:protocol_version]}
          type="select"
          label={gettext("Protocol version")}
          options={[{SamgitaProtocol.version(), SamgitaProtocol.version()}]}
        />
        <.dm_input
          field={@form[:endpoint_url]}
          label={gettext("Agent endpoint URL (optional)")}
          placeholder="wss://agent.example/app-server"
          helper={
            gettext("Use the exact approved endpoint. Remote WebSocket destinations require WSS.")
          }
        />
        <.dm_input
          field={@form[:endpoint_transport]}
          type="select"
          label={gettext("Endpoint transport")}
          options={[{gettext("Not configured"), ""}, {"WebSocket", "websocket"}, {"stdio", "stdio"}]}
        />
      </div>
      <.dm_input
        field={@form[:credential_ref]}
        label={gettext("Outbound credential reference (optional)")}
        maxlength="512"
        helper={
          gettext(
            "External versioned reference name only, never a secret value. Runtime destination/address approvals and credential resolution must be configured separately before delivery."
          )
        }
      />
    </fieldset>
    <fieldset class="space-y-4">
      <legend class="font-semibold">{gettext("Capabilities")}</legend>
      <p class="text-sm text-on-surface-variant">
        {gettext(
          "Approval must be a subset of advertised capabilities. Project membership grants roles separately."
        )}
      </p>
      <input type="hidden" name="agent[advertised_capabilities][]" value="" />
      <.dm_input
        field={@form[:advertised_capabilities]}
        type="checkbox_group"
        label={gettext("Advertised capabilities")}
        options={@capabilities}
      />
      <input type="hidden" name="agent[approved_capabilities][]" value="" />
      <.dm_input
        field={@form[:approved_capabilities]}
        type="checkbox_group"
        label={gettext("Operator-approved capabilities")}
        options={@capabilities}
      />
    </fieldset>
    """
  end

  def defaults do
    %{
      "name" => "",
      "implementation" => "",
      "capacity" => 1,
      "enabled" => true,
      "advertised_capabilities" => [],
      "approved_capabilities" => [],
      "protocol" => "samgita",
      "protocol_version" => SamgitaProtocol.version(),
      "endpoint_url" => "",
      "endpoint_transport" => "",
      "credential_ref" => "",
      "command_id" => Ecto.UUID.generate()
    }
  end

  def agent_attrs(params) do
    params
    |> Map.take(
      ~w(name implementation capacity enabled advertised_capabilities approved_capabilities protocol protocol_version credential_ref command_id expected_version)
    )
    |> Map.put(
      "advertised_capabilities",
      Enum.reject(List.wrap(params["advertised_capabilities"]), &(&1 == ""))
    )
    |> Map.put(
      "approved_capabilities",
      Enum.reject(List.wrap(params["approved_capabilities"]), &(&1 == ""))
    )
    |> version_attrs()
    |> endpoint_attrs(params)
  end

  def form_values(attrs) do
    endpoint = attrs["endpoint_metadata"] || %{}

    attrs
    |> Map.put("endpoint_url", safe_endpoint_url(endpoint["url"]))
    |> Map.put("endpoint_transport", endpoint["transport"] || "")
  end

  defp safe_endpoint_url(value) when is_binary(value) do
    uri = URI.parse(value)
    if uri.userinfo || uri.query || uri.fragment, do: "", else: value
  end

  defp safe_endpoint_url(_), do: ""

  defp endpoint_attrs(attrs, params) do
    if Map.has_key?(params, "endpoint_url") or Map.has_key?(params, "endpoint_transport") do
      endpoint = %{"url" => params["endpoint_url"], "transport" => params["endpoint_transport"]}

      Map.put(
        attrs,
        "endpoint_metadata",
        Map.reject(endpoint, fn {_key, value} -> value in [nil, ""] end)
      )
    else
      attrs
    end
  end

  def version_attrs(%{"expected_version" => value} = attrs) when is_binary(value) do
    case Integer.parse(value) do
      {version, ""} -> Map.put(attrs, "expected_version", version)
      _ -> attrs
    end
  end

  def version_attrs(attrs), do: attrs

  def error_message(%Samgita.Error{code: :invalid, details: details}) do
    fields = Map.get(details, :fields, Map.get(details, "fields", []))
    field = Map.get(details, :field, Map.get(details, "field"))

    names =
      Enum.map_join(List.wrap(field) ++ fields, ", ", &String.replace(to_string(&1), "_", " "))

    if names == "",
      do: "Check the submitted fields.",
      else: "Check these fields: " <> names <> "."
  end

  def error_message(%Samgita.Error{code: :stale_version}),
    do:
      "This record changed. Refresh the page and review its current values before submitting again."

  def error_message(%Samgita.Error{code: :conflict}),
    do: "This command conflicts with an existing change. Refresh and review the current record."

  def error_message(%Samgita.Error{code: :not_found}), do: "Agent not found."
  def error_message(_), do: "The request could not be completed. Refresh and try again."

  def offset(params) do
    case Integer.parse(to_string(params["offset"] || "0")) do
      {n, ""} when n >= 0 -> n
      _ -> 0
    end
  end
end
