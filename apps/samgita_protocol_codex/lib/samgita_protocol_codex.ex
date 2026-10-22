defmodule SamgitaProtocolCodex do
  @moduledoc """
  Pure, explicitly limited Codex 0.163.0 app-server translation.

  The caller owns transport authentication, initialization order, pending requests,
  execution uncertainty and event retention. See the package README for omissions.
  """

  alias SamgitaProtocol.{Codec, Error}

  @methods ~w(thread/start thread/read thread/resume turn/start turn/steer turn/interrupt)
  @notifications ~w(turn/started turn/completed item/agentMessage/delta)
  @metadata ~w(correlation_id causation_id project_ref task_ref command_id)
  @notification_metadata ~w(correlation_id causation_id project_ref task_ref stream_id cursor)

  @doc "The exact request subset; this is not a native capability-group advertisement."
  def supported_methods, do: @methods

  @doc "The exact upstream notification subset. No replay support is implied."
  def supported_notifications, do: @notifications

  @doc "Pinned official source and schema provenance."
  def source do
    :samgita_protocol_codex
    |> :code.priv_dir()
    |> Path.join("upstream/source.json")
    |> File.read!()
    |> JSON.decode!()
  end

  @doc "Build the upstream-only initialize request without enabling experimental APIs."
  def initialize_request(id, client_info)
      when is_binary(id) and is_map(client_info) and not is_struct(client_info) do
    if nonempty?(id) and nonempty?(client_info["name"]) and
         nonempty?(client_info["version"]) and
         Enum.all?(Map.keys(client_info), &(&1 in ~w(name title version))) and
         (not Map.has_key?(client_info, "title") or
            (is_binary(client_info["title"]) and String.valid?(client_info["title"]))) do
      {:ok, %{"id" => id, "method" => "initialize", "params" => %{"clientInfo" => client_info}}}
    else
      error("invalid_params")
    end
  end

  def initialize_request(_, _), do: error("invalid_params")

  @doc "Send only after accepting the matching successful initialize response."
  def initialized, do: %{"method" => "initialized"}

  @doc "Validate the selected initialize metadata and exact request ID."
  def decode_initialize_response(wire, id)
      when is_map(wire) and not is_struct(wire) and is_binary(id) do
    with :ok <- matches(wire["id"], id),
         :ok <- response_shape(wire) do
      case wire do
        %{"result" => result} when is_map(result) ->
          fields = ~w(codexHome platformFamily platformOs userAgent)

          if Enum.all?(fields, &(is_binary(result[&1]) and String.valid?(result[&1]))) do
            {:ok, Map.take(result, fields)}
          else
            error("invalid_response")
          end

        %{"error" => upstream} ->
          upstream_error(upstream)
      end
    end
  end

  def decode_initialize_response(_, _), do: error("invalid_response")

  @doc "Translate a validated native request; native command IDs never go upstream."
  def encode_request(%{"type" => "request", "method" => method} = request)
      when method in @methods do
    with {:ok, _} <- Codec.encode(request),
         {:ok, params} <- encode_params(method, request["params"]) do
      {:ok, %{"id" => request["id"], "method" => method, "params" => params}}
    end
  end

  def encode_request(%{"type" => "request", "method" => _}), do: error("unsupported_method")
  def encode_request(_), do: error("invalid_message")

  @doc "Decode a reply using its original native request, or a notification using explicit context."
  def decode_message(%{"method" => method} = wire, context)
      when is_map(context) and not is_struct(context) do
    cond do
      Map.has_key?(wire, "id") -> error("unsupported_method")
      method not in @notifications -> error("unsupported_method")
      true -> decode_notification(method, wire, context)
    end
  end

  def decode_message(%{"id" => _} = wire, %{"type" => "request"} = original) do
    with {:ok, _} <- encode_request(original),
         :ok <- matches(wire["id"], original["id"]),
         :ok <- response_shape(wire),
         {:ok, payload} <- decode_payload(wire, original) do
      original
      |> Map.take(@metadata ++ ["id"])
      |> Map.merge(%{"schema_version" => "1.0", "type" => "response"})
      |> Map.merge(payload)
      |> native()
    end
  end

  def decode_message(_, _), do: error("invalid_message")

  defp encode_params("thread/start", params) when map_size(params) == 0, do: {:ok, %{}}
  defp encode_params("thread/start", _), do: error("unsupported_capability")

  defp encode_params(method, params) when method in ~w(thread/read thread/resume) do
    {:ok, %{"threadId" => params["thread_id"]}}
  end

  defp encode_params("turn/start", params) do
    {:ok, %{"threadId" => params["thread_id"], "input" => params["input"]}}
  end

  defp encode_params("turn/steer", params) do
    {:ok,
     %{
       "threadId" => params["thread_id"],
       "expectedTurnId" => params["turn_id"],
       "input" => params["input"]
     }}
  end

  defp encode_params("turn/interrupt", params) do
    {:ok, %{"threadId" => params["thread_id"], "turnId" => params["turn_id"]}}
  end

  defp decode_payload(%{"error" => upstream}, _original) do
    case upstream_error(upstream) do
      {:error, %Error{code: "upstream_error"} = failure} ->
        {:ok, %{"error" => Error.to_map(failure)}}

      invalid ->
        invalid
    end
  end

  defp decode_payload(%{"result" => result}, original) do
    with {:ok, projection} <- decode_result(original["method"], result, original["params"]) do
      {:ok, %{"result" => projection}}
    end
  end

  defp decode_result(method, %{"thread" => %{"id" => id} = thread}, params)
       when method in ~w(thread/start thread/read thread/resume) do
    with :ok <- required_strings([id], "invalid_response"),
         :ok <- matches_if_present(params["thread_id"], id) do
      {:ok, %{"thread_id" => id, "thread" => thread}}
    end
  end

  defp decode_result("turn/start", %{"turn" => %{"id" => id, "status" => "inProgress"}}, params) do
    with :ok <- required_strings([id], "invalid_response") do
      {:ok, %{"thread_id" => params["thread_id"], "turn_id" => id, "status" => "running"}}
    end
  end

  defp decode_result("turn/steer", %{"turnId" => id}, params) do
    with :ok <- matches(id, params["turn_id"]) do
      {:ok, %{"thread_id" => params["thread_id"], "turn_id" => id, "status" => "running"}}
    end
  end

  defp decode_result("turn/interrupt", result, params) when map_size(result) == 0 do
    {:ok,
     %{
       "thread_id" => params["thread_id"],
       "turn_id" => params["turn_id"],
       "status" => "requested"
     }}
  end

  defp decode_result(_, _, _), do: error("invalid_response")

  defp decode_notification(method, %{"params" => params} = wire, context)
       when is_map(params) and not is_struct(params) do
    with :ok <- exact_keys(wire, ~w(method params), "invalid_message"),
         :ok <-
           required_strings(
             [context["correlation_id"], context["thread_id"], context["turn_id"]],
             "invalid_message"
           ),
         :ok <- required_strings([params["threadId"]], "invalid_params"),
         :ok <- matches(params["threadId"], context["thread_id"]),
         {:ok, neutral_method, projection} <- notification_params(method, params, context) do
      context
      |> Map.take(@notification_metadata)
      |> Map.merge(%{
        "schema_version" => "1.0",
        "type" => "notification",
        "method" => neutral_method,
        "params" => projection
      })
      |> native()
    end
  end

  defp decode_notification(_, _, _), do: error("invalid_params")

  defp notification_params("item/agentMessage/delta", params, context) do
    with :ok <- required_strings([params["itemId"], params["turnId"]], "invalid_params"),
         :ok <- matches(params["turnId"], context["turn_id"]) do
      if is_binary(params["delta"]) do
        {:ok, "item/delta",
         %{
           "thread_id" => context["thread_id"],
           "turn_id" => context["turn_id"],
           "item_id" => params["itemId"],
           "delta" => params["delta"]
         }}
      else
        error("invalid_params")
      end
    end
  end

  defp notification_params(method, %{"turn" => %{"id" => id, "status" => status}}, context)
       when method in ~w(turn/started turn/completed) do
    with :ok <- matches(id, context["turn_id"]) do
      projection = %{"thread_id" => context["thread_id"], "turn_id" => id}

      cond do
        method == "turn/started" and status == "inProgress" ->
          {:ok, method, projection}

        method == "turn/completed" and status in ~w(completed failed interrupted) ->
          {:ok, method, Map.put(projection, "status", status)}

        true ->
          error("invalid_params")
      end
    end
  end

  defp notification_params(_, _, _), do: error("invalid_params")

  defp response_shape(wire) do
    cond do
      Map.has_key?(wire, "result") and is_map(wire["result"]) and
          not is_struct(wire["result"]) ->
        exact_keys(wire, ~w(id result), "invalid_response")

      Map.has_key?(wire, "error") and is_map(wire["error"]) ->
        exact_keys(wire, ~w(id error), "invalid_response")

      true ->
        error("invalid_response")
    end
  end

  defp upstream_error(%{"code" => code, "message" => message})
       when is_integer(code) and is_binary(message) do
    failure = Error.new("upstream_error", %{"upstream_code" => code})
    {:error, %{failure | retryable: code == -32001}}
  end

  defp upstream_error(_), do: error("invalid_response")

  defp native(message) do
    with {:ok, _} <- Codec.encode(message), do: {:ok, message}
  end

  defp matches(value, expected) when is_binary(value) and value == expected, do: :ok
  defp matches(_, _), do: error("correlation_mismatch")
  defp matches_if_present(nil, _), do: :ok
  defp matches_if_present(expected, value), do: matches(value, expected)

  defp required_strings(values, code) do
    if Enum.all?(values, &nonempty?/1), do: :ok, else: error(code)
  end

  defp exact_keys(map, keys, code) do
    if Enum.sort(Map.keys(map)) == Enum.sort(keys), do: :ok, else: error(code)
  end

  defp nonempty?(value), do: is_binary(value) and byte_size(value) > 0 and String.valid?(value)
  defp error(code), do: {:error, Error.new(code)}
end
