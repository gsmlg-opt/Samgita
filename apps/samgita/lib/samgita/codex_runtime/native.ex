defmodule Samgita.CodexRuntime.Native do
  @moduledoc false
  alias Samgita.Commands
  alias SamgitaProtocolCodex.{Schema, Wire}

  @reads ~w(initialize thread/list thread/loaded/list thread/read thread/turns/list model/list config/read configRequirements/read account/read skills/list)

  def effect(method, direction \\ "client_request")

  # rust-v0.163.0 (83086188ae0614bd882818ff1aa23f3194962012):
  # app-server/src/message_processor.rs:740-751 only logs client notifications;
  # app-server-protocol/src/protocol/common.rs:2097-2099 declares only Initialized.
  def effect("initialized", "client_notification"), do: "read"
  def effect(method, "client_request"), do: if(method in @reads, do: "read", else: "mutation")
  def effect(_method, _direction), do: "mutation"

  def outgoing!(wire, runtime) do
    case Wire.classify(wire) do
      :request ->
        request!(wire, runtime)
        "client_request"

      :notification ->
        encode!(wire)

        validate!(
          Schema.validate_notification(:client_notification, wire["method"], wire["params"],
            experimental: runtime.experimental,
            params_present: Map.has_key?(wire, "params")
          )
        )

        "client_notification"

      _ ->
        Commands.fail!(:invalid_native_payload)
    end
  end

  def request!(wire, runtime) do
    encode!(wire)
    if Wire.classify(wire) != :request, do: Commands.fail!(:invalid_native_payload)

    validate!(
      Schema.validate_request(wire["method"], wire["params"],
        experimental: runtime.experimental,
        params_present: Map.has_key?(wire, "params")
      )
    )

    if wire["method"] == "initialize" &&
         get_in(wire, ["params", "capabilities", "experimentalApi"]) == true !=
           runtime.experimental,
       do: Commands.fail!(:invalid, %{reason: "initialization_profile_mismatch"})

    wire
  end

  def response!(wire, request, direction, method) do
    encode!(wire)

    if Wire.classify(wire) not in [:response, :error] || wire["id"] != request["id"],
      do: Commands.fail!(:invalid_native_payload)

    if Map.has_key?(wire, "result"),
      do: validate!(Schema.validate_result(direction, method, wire["result"], experimental: true))

    wire
  end

  def event!(wire, runtime) do
    encode!(wire)

    case Wire.classify(wire) do
      :request ->
        validate!(
          Schema.validate_request(wire["method"], wire["params"],
            direction: :server_request,
            experimental: runtime.experimental,
            params_present: Map.has_key?(wire, "params")
          )
        )

        "server_request"

      :notification ->
        validate!(
          Schema.validate_notification(:server_notification, wire["method"], wire["params"],
            experimental: runtime.experimental,
            params_present: Map.has_key?(wire, "params")
          )
        )

        "server_notification"

      _ ->
        Commands.fail!(:invalid_native_payload)
    end
  end

  defp encode!(wire), do: validate!(Wire.encode(wire, max_bytes: 8_388_608))
  defp validate!(:ok), do: :ok
  defp validate!({:ok, _}), do: :ok

  defp validate!({:error, %SamgitaProtocolCodex.Error{code: code}}),
    do: Commands.fail!(:invalid_native_payload, %{reason: to_string(code)})
end
