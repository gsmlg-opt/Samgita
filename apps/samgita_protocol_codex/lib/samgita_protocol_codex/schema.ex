defmodule SamgitaProtocolCodex.Schema do
  @moduledoc """
  Native method contracts from the pinned Codex 0.163.0 executable and source.

  Official JSON exports remain unchanged. A separately labelled, source-derived
  supplement covers the three omitted legacy requests/results and two internal
  raw-response notifications. Its provenance is shipped with the pinned source.

  All four message directions and correlated result schemas are available.
  `experimental: true` selects the complete upstream input profile. The default
  input profile uses the pinned Rust field-presence rules: false booleans,
  absent/null options and empty nonoptional collections do not use an experimental
  capability. Server output payloads and correlated results always validate against
  the full output schema: upstream does not recursively apply client-input field
  gates to emitted data. Server notification method gates come from the pinned
  Rust enum annotations; server requests have no experimental method gate.
  Validation never transforms values, inserts defaults, or creates atoms.

  Pass `params_present: false` for an omitted params member; explicit `nil` is
  validated as JSON null. Server-initiated requests use `direction: :server_request`.
  This validates wire contracts and cannot establish behavioral compatibility.
  """

  alias SamgitaProtocolCodex.{Error, Wire}
  alias SamgitaProtocolCodex.Schema.{Gates, Validator}

  @version "0.163.0"
  @source Path.expand("../../priv/upstream/0.163.0/source/common.rs", __DIR__)
  @external_resource @source
  @source_text File.read!(@source)
  # Both exported notification profiles include every method. The runtime uses
  # ServerNotification's ExperimentalApi derive instead (transport.rs), so schema
  # membership alone cannot determine notification availability.
  @notification_source @source_text
                       |> String.split("server_notification_definitions! {", parts: 2)
                       |> List.last()
                       |> String.split("\n}", parts: 2)
                       |> hd()
  @experimental_notifications for [_, wire] <-
                                    Regex.scan(
                                      ~r/#\[experimental\("[^"]+"\)\]\s+\w+\s*=>\s*"([^"]+)"\s*\(/,
                                      @notification_source
                                    ),
                                  do: wire
  if length(@experimental_notifications) !=
       length(Regex.scan(~r/#\[experimental\(/, @notification_source)) do
    raise "unparsed pinned server notification experimental annotation"
  end

  @directions %{
    client_request: "ClientRequest.json",
    server_request: "ServerRequest.json",
    server_notification: "ServerNotification.json",
    client_notification: "ClientNotification.json"
  }
  @result_paths (for {macro, direction} <- [
                       {"client_request_definitions", :server_response},
                       {"server_request_definitions", :client_response}
                     ],
                     block =
                       @source_text
                       |> String.split(macro <> "! {", parts: 2)
                       |> List.last()
                       |> String.split("\n}", parts: 2)
                       |> hd(),
                     [_, variant, name, type] <-
                       Regex.scan(
                         ~r/(\w+)\s*(?:=>\s*"([^"]+)")?\s*\{\s*params:.*?response:\s*([:\w]+),\s*\}/s,
                         block
                       ),
                     into: %{} do
                   wire =
                     if name == "",
                       do:
                         String.replace_prefix(
                           variant,
                           String.first(variant),
                           String.downcase(String.first(variant))
                         ),
                       else: name

                   path = String.replace(type, "::", "/") <> ".json"
                   {{direction, wire}, path}
                 end)

  @doc "Wire names in the selected direction/profile."
  def methods(direction, opts \\ []) do
    case Map.fetch(@directions, direction) do
      {:ok, filename} ->
        # ServerRequest's macro uses experimental annotations for exports only;
        # it does not derive ExperimentalApi or gate outbound method variants.
        selected_profile =
          if direction == :server_request, do: "experimental", else: profile(opts)

        methods =
          filename
          |> documents(selected_profile)
          |> Enum.flat_map(&Map.fetch!(&1, "oneOf"))
          |> Enum.map(&wire_name/1)

        if direction == :server_notification and not Keyword.get(opts, :experimental, false),
          do: methods -- @experimental_notifications,
          else: methods

      :error ->
        []
    end
  end

  def validate_request(method, params, opts \\ []) do
    validate_message(Keyword.get(opts, :direction, :client_request), method, params, opts)
  end

  def validate_notification(direction, method, params, opts \\ [])
      when direction in [:client_notification, :server_notification] do
    validate_message(direction, method, params, opts)
  end

  def validate_result(direction, method, result, opts \\ []) do
    with {:ok, filename} <- result_path(direction, method) do
      validate(read(filename, "experimental"), result, opts)
    end
  end

  @doc "Validate a JSON value against an explicit draft-07 contract without modifying it."
  def validate(schema, value, opts \\ []) do
    with :ok <- Wire.validate_value(value, opts), do: Validator.validate(schema, value)
  end

  defp validate_message(direction, method, params, opts) do
    with {:ok, filename} <- direction_file(direction),
         :ok <- method_available(direction, method, opts) do
      document = method_document(filename, profile(opts), method)
      full = method_document(filename, "experimental", method)
      schema = Enum.find(document["oneOf"], &(wire_name(&1) == method))
      full_schema = Enum.find(full["oneOf"], &(wire_name(&1) == method))

      value =
        if Keyword.get(opts, :params_present, true),
          do: %{"method" => method, "params" => params},
          else: %{"method" => method}

      value =
        if direction in [:client_request, :server_request],
          do: Map.put(value, "id", "schema-validation"),
          else: value

      with :ok <- Wire.validate_value(value, opts),
           :ok <- Validator.validate(full_schema, value, full) do
        gates(direction, full_schema, schema, value, full, document, opts)
      end
    end
  end

  defp gates(:client_request, full, stable, value, full_root, stable_root, opts) do
    if Keyword.get(opts, :experimental, false),
      do: :ok,
      else: Gates.check(full, stable, value, full_root, stable_root)
  end

  defp gates(_direction, _full, _stable, _value, _full_root, _stable_root, _opts), do: :ok

  defp method_available(direction, method, opts) do
    cond do
      method not in methods(direction, experimental: true) -> failure(:unsupported_method)
      method not in methods(direction, opts) -> failure(:experimental_api_required)
      true -> :ok
    end
  end

  defp direction_file(direction) do
    case Map.fetch(@directions, direction) do
      {:ok, filename} -> {:ok, filename}
      :error -> failure(:invalid_direction)
    end
  end

  defp result_path(direction, method) do
    case Map.fetch(@result_paths, {direction, method}) do
      {:ok, filename} ->
        root =
          :samgita_protocol_codex
          |> :code.priv_dir()
          |> Path.join("upstream/" <> @version)

        filename =
          Enum.find([filename, Path.basename(filename), "supplemental/" <> filename], fn path ->
            File.exists?(schema_path(root, path, "experimental"))
          end)

        if filename, do: {:ok, filename}, else: failure(:unsupported_method)

      :error ->
        failure(:unsupported_method)
    end
  end

  defp profile(opts),
    do: if(Keyword.get(opts, :experimental, false), do: "experimental", else: "stable")

  defp wire_name(schema), do: schema["properties"]["method"]["enum"] |> hd()

  defp documents(filename, profile)
       when filename in ["ClientRequest.json", "ServerNotification.json"],
       do: [read(filename, profile), read("supplemental/" <> filename, profile)]

  defp documents(filename, profile), do: [read(filename, profile)]

  defp method_document(filename, profile, method) do
    available = documents(filename, profile)

    Enum.find(available, hd(available), fn document ->
      Enum.any?(document["oneOf"], &(wire_name(&1) == method))
    end)
  end

  defp read(filename, profile) do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/" <> @version)
    |> schema_path(filename, profile)
    |> File.read!()
    |> JSON.decode!()
  end

  defp schema_path(root, "supplemental/" <> _ = filename, _profile),
    do: Path.join(root, filename)

  defp schema_path(root, filename, profile), do: Path.join([root, profile, filename])

  defp failure(code), do: {:error, Error.new(code)}
end
