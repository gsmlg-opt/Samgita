defmodule SamgitaProtocol.Server do
  @moduledoc "Validated dispatch to an explicitly registered host. No authentication, storage or tools are implied."
  alias SamgitaProtocol.{Capabilities, Client, Codec, Error, Schema}
  defstruct [:handler, :handler_state, :client, :connection_id]

  def new(handler, state, opts \\ []) do
    Code.ensure_loaded(handler)

    with true <-
           function_exported?(handler, :capabilities, 0) and
             function_exported?(handler, :methods, 0) and
             function_exported?(handler, :handle_request, 4),
         :ok <- Capabilities.validate(handler.capabilities()),
         true <- Enum.sort(handler.methods()) == Capabilities.methods(handler.capabilities()),
         {:ok, client} <- Client.new(Keyword.put(opts, :capabilities, handler.capabilities())) do
      {:ok,
       %__MODULE__{
         handler: handler,
         handler_state: state,
         client: client,
         connection_id:
           Keyword.get(
             opts,
             :connection_id,
             "connection-#{System.unique_integer([:positive, :monotonic])}"
           )
       }}
    else
      _ -> {:error, Error.new("capability_mismatch")}
    end
  end

  def request(server, method, params, opts \\ []) do
    if function_exported?(server.handler, :handle_response, 4) do
      case Client.request(server.client, method, params, opts) do
        {:ok, message, client} -> {:ok, message, %{server | client: client}}
        {:error, error, _} -> {:error, error, server}
      end
    else
      {:error, Error.new("unsupported_method"), server}
    end
  end

  def receive(server, data) do
    case decode(data, server.client.max_frame_bytes) do
      {:ok, message} -> dispatch(server, message)
      {:error, error} -> reject(server, data, error)
    end
  end

  defp dispatch(server, %{"type" => "request", "method" => "connection/initialize"} = request) do
    cond do
      server.client.phase != :new ->
        respond(server, request, {:error, Error.new("already_initialized")})

      "1.0" not in request["params"]["versions"] ->
        respond(server, request, {:error, Error.new("unsupported_version")})

      true ->
        params = request["params"]

        case Capabilities.negotiate(
               server.client.capabilities,
               params["capabilities"],
               Map.get(params, "required_capabilities", [])
             ) do
          {:ok, groups} ->
            result = %{
              "version" => "1.0",
              "capabilities" => groups,
              "connection_id" => server.connection_id
            }

            server = %{
              server
              | client: Client.establish(server.client, groups, server.connection_id)
            }

            respond(server, request, {:ok, result})

          {:error, error} ->
            respond(server, request, {:error, error})
        end
    end
  end

  defp dispatch(server, %{"type" => "request"} = request) do
    cond do
      server.client.phase != :ready ->
        respond(server, request, {:error, Error.new("not_initialized")})

      not Capabilities.supports?(server.client.negotiated, request["method"]) ->
        respond(server, request, {:error, Error.new("unsupported_capability")})

      true ->
        call_handler(server, request)
    end
  end

  defp dispatch(server, %{"type" => "response"} = response) do
    pending = server.client.pending[response["id"]]

    case Client.receive(server.client, response) do
      {:ok, [], client} ->
        {:ok, [], %{server | client: client}}

      {:ok, [effect], client} ->
        result =
          case effect do
            {:response, _, value} -> {:ok, value}
            {:error, _, error} -> {:error, error}
          end

        server = %{server | client: client}

        case safe_callback(fn ->
               server.handler.handle_response(
                 pending.request["method"],
                 result,
                 context(server, pending.request),
                 server.handler_state
               )
             end) do
          {:ok, state} -> {:ok, [], %{server | handler_state: state}}
          _ -> {:error, Error.new("handler_error"), server}
        end

      {:error, error, _} ->
        {:error, error, server}
    end
  end

  defp dispatch(server, %{"type" => "notification"} = notification) do
    cond do
      server.client.phase != :ready ->
        {:error, Error.new("not_initialized"), server}

      not Capabilities.supports?(server.client.negotiated, notification["method"]) ->
        {:error, Error.new("unsupported_capability"), server}

      not function_exported?(server.handler, :handle_notification, 4) ->
        {:error, Error.new("unsupported_method"), server}

      true ->
        case Client.receive(server.client, notification) do
          {:ok, [], _} ->
            {:ok, [], server}

          {:error, error, _} ->
            {:error, error, server}

          {:ok, [{:notification, _}], client} ->
            case safe_callback(fn ->
                   server.handler.handle_notification(
                     notification["method"],
                     notification["params"],
                     context(server, notification),
                     server.handler_state
                   )
                 end) do
              {:ok, state} ->
                {[_], client} = Client.drain(client, 1)

                client =
                  case notification do
                    %{"stream_id" => stream, "cursor" => cursor} ->
                      {:ok, client} = Client.ack_cursor(client, stream, cursor)
                      client

                    _ ->
                      client
                  end

                {:ok, [], %{server | client: client, handler_state: state}}

              {:error, %Error{} = error, state} ->
                {:error, error, %{server | handler_state: state}}

              _ ->
                {:error, Error.new("handler_error"), server}
            end
        end
    end
  end

  defp call_handler(server, request) do
    case safe_callback(fn ->
           server.handler.handle_request(
             request["method"],
             request["params"],
             context(server, request),
             server.handler_state
           )
         end) do
      {:ok, result, state} ->
        case Schema.validate_reply(request, %{"result" => result}) do
          :ok -> respond(%{server | handler_state: state}, request, {:ok, result})
          {:error, error} -> respond(server, request, {:error, error})
        end

      {:error, %Error{} = error, state} ->
        respond(%{server | handler_state: state}, request, {:error, error})

      _ ->
        respond(server, request, {:error, Error.new("handler_error")})
    end
  rescue
    _ -> respond(server, request, {:error, Error.new("handler_error")})
  end

  defp respond(server, request, result) do
    case Client.response_to(request, result) do
      {:ok, response} -> {:ok, [response], server}
      {:error, error} -> {:error, error, server}
    end
  end

  defp reject(server, data, error) do
    raw =
      if is_binary(data) and byte_size(data) <= server.client.max_frame_bytes,
        do: JSON.decode(data),
        else: {:ok, data}

    case raw do
      {:ok,
       %{
         "type" => "request",
         "schema_version" => "1.0",
         "id" => id,
         "correlation_id" => correlation
       } = request} ->
        if Schema.valid?(id, :id) and Schema.valid?(correlation, :id),
          do: respond(server, request, {:error, error}),
          else: {:error, error, server}

      _ ->
        {:error, error, server}
    end
  end

  defp context(server, request) do
    request
    |> Map.take(~w(command_id correlation_id causation_id project_ref task_ref stream_id cursor))
    |> Map.put("request_id", request["id"])
    |> Map.put("connection_id", server.connection_id)
  end

  defp safe_callback(callback) do
    callback.()
  rescue
    _ -> {:error, Error.new("handler_error")}
  catch
    _, _ -> {:error, Error.new("handler_error")}
  end

  defp decode(binary, max) when is_binary(binary), do: Codec.decode(binary, max_frame_bytes: max)

  defp decode(message, max) do
    with {:ok, _} <- Codec.encode(message, max_frame_bytes: max), do: {:ok, message}
  end
end
