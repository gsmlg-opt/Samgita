defmodule SamgitaProtocol.Schema do
  @moduledoc "Strict version 1.0 envelopes and method schemas. All wire keys remain strings."
  alias SamgitaProtocol.Error

  @processing {:enum, ~w(pending processing completed failed rejected)}
  @acceptance {:enum, ~w(received durable)}
  @methods %{
    "connection/initialize" =>
      {nil, false, %{"versions" => :strings, "capabilities" => :strings},
       %{"required_capabilities" => :strings},
       %{"version" => {:enum, ["1.0"]}, "capabilities" => :strings, "connection_id" => :id}, %{}},
    "project/event.receive" =>
      {"project_events.v1", true, %{"event" => :event}, %{},
       %{
         "event_id" => :id,
         "delivery_attempt_id" => :id,
         "acceptance" => @acceptance,
         "processing_status" => @processing
       }, %{}},
    "project/event.status" =>
      {"project_events.v1", false, %{"event_id" => :id}, %{},
       %{"event_id" => :id, "acceptance" => @acceptance, "processing_status" => @processing},
       %{"decision_id" => :id, "decision" => :object, "result" => :anything}},
    "project/event.report" =>
      {"project_events.v1", true,
       %{
         "event_id" => :id,
         "decision_id" => :id,
         "status" => {:enum, ~w(completed failed rejected)},
         "decision" => :object
       }, %{"result" => :anything},
       %{
         "event_id" => :id,
         "decision_id" => :id,
         "report_status" => {:enum, ["recorded"]},
         "management_acceptance" => {:enum, ~w(not_requested accepted rejected)}
       }, %{}},
    "thread/start" =>
      {"sessions.v1", true, %{}, %{"title" => :string, "metadata" => :object},
       %{"thread_id" => :id}, %{"thread" => :anything}},
    "thread/read" =>
      {"sessions.v1", false, %{"thread_id" => :id}, %{}, %{"thread_id" => :id},
       %{"thread" => :anything}},
    "thread/resume" =>
      {"sessions.v1", true, %{"thread_id" => :id}, %{}, %{"thread_id" => :id},
       %{"thread" => :anything}},
    "turn/start" =>
      {"sessions.v1", true, %{"thread_id" => :id, "input" => :input}, %{},
       %{"thread_id" => :id, "turn_id" => :id, "status" => {:enum, ["running"]}}, %{}},
    "turn/steer" =>
      {"sessions.v1", true, %{"thread_id" => :id, "turn_id" => :id, "input" => :input}, %{},
       %{"thread_id" => :id, "turn_id" => :id, "status" => {:enum, ["running"]}}, %{}},
    "turn/interrupt" =>
      {"sessions.v1", true, %{"thread_id" => :id, "turn_id" => :id}, %{},
       %{
         "thread_id" => :id,
         "turn_id" => :id,
         "status" => {:enum, ~w(requested interrupted already_finished)}
       }, %{}},
    "stream/resume" =>
      {"streaming.v1", false, %{"stream_id" => :id, "cursor" => :nonneg}, %{},
       %{"stream_id" => :id, "cursor" => :nonneg, "events" => :notifications}, %{}},
    "approval/request" =>
      {"approvals.v1", true,
       %{"approval_id" => :id, "thread_id" => :id, "turn_id" => :id, "action" => :object},
       %{"expires_at" => :timestamp},
       %{
         "approval_id" => :id,
         "decision" => {:enum, ~w(approve deny)},
         "scope" => {:enum, ["once"]}
       }, %{}},
    "request/cancel" =>
      {"cancellation.v1", true, %{"request_id" => :id}, %{},
       %{"request_id" => :id, "status" => {:enum, ~w(requested already_finished)}}, %{}}
  }
  @notifications %{
    "project/event.updated" =>
      {"project_events.v1",
       %{"event_id" => :id, "acceptance" => @acceptance, "processing_status" => @processing}},
    "thread/started" => {"sessions.v1", %{"thread_id" => :id}},
    "turn/started" => {"sessions.v1", %{"thread_id" => :id, "turn_id" => :id}},
    "turn/completed" =>
      {"sessions.v1",
       %{
         "thread_id" => :id,
         "turn_id" => :id,
         "status" => {:enum, ~w(completed failed interrupted)}
       }},
    "item/started" =>
      {"streaming.v1",
       %{"thread_id" => :id, "turn_id" => :id, "item_id" => :id, "item" => :object}},
    "item/delta" =>
      {"streaming.v1",
       %{"thread_id" => :id, "turn_id" => :id, "item_id" => :id, "delta" => :string}},
    "item/completed" =>
      {"streaming.v1",
       %{"thread_id" => :id, "turn_id" => :id, "item_id" => :id, "item" => :object}}
  }
  @metadata %{
    "causation_id" => {:nullable, :id},
    "project_ref" => {:nullable, :id},
    "task_ref" => {:nullable, :id},
    "command_id" => :id
  }
  @common %{"schema_version" => {:enum, ["1.0"]}, "type" => :id, "correlation_id" => :id}

  def methods, do: Map.keys(@methods) |> Enum.sort()
  def notification_methods, do: Map.keys(@notifications) |> Enum.sort()
  def definitions, do: @methods
  def notification_definitions, do: @notifications

  def capability(method) do
    case @methods[method] || @notifications[method] do
      {capability, _, _, _, _, _} -> capability
      {capability, _} -> capability
      nil -> :unknown
    end
  end

  def mutating?(method), do: match?({_, true, _, _, _, _}, @methods[method])

  def validate(message) when is_map(message) do
    with true <- json?(message),
         :ok <- version(message["schema_version"]),
         :ok <- validate_envelope(message),
         :ok <- references(message) do
      {:ok, message}
    else
      false -> {:error, Error.new("invalid_message")}
      {:error, _} = error -> error
    end
  end

  def validate(_), do: {:error, Error.new("invalid_message")}

  defp validate_envelope(%{"type" => "request"} = m) do
    with :ok <-
           shape(
             m,
             Map.merge(@common, %{"id" => :id, "method" => :id, "params" => :object}),
             @metadata,
             "invalid_message"
           ),
         :ok <- validate_params(m["method"], m["params"]),
         true <- not mutating?(m["method"]) or valid?(m["command_id"], :id),
         :ok <- event_context(m) do
      :ok
    else
      false -> {:error, Error.new("invalid_message")}
      error -> error
    end
  end

  defp validate_envelope(%{"type" => "response"} = m) do
    with :ok <-
           shape(
             m,
             Map.merge(@common, %{"id" => :id}),
             Map.merge(@metadata, %{"result" => :object, "error" => :object}),
             "invalid_message"
           ),
         true <- Map.has_key?(m, "result") != Map.has_key?(m, "error") do
      if Map.has_key?(m, "error"), do: error_shape(m["error"]), else: :ok
    else
      false -> {:error, Error.new("invalid_message")}
      error -> error
    end
  end

  defp validate_envelope(%{"type" => "notification"} = m) do
    with :ok <-
           shape(
             m,
             Map.merge(@common, %{"method" => :id, "params" => :object}),
             Map.merge(Map.delete(@metadata, "command_id"), %{
               "stream_id" => :id,
               "cursor" => :positive
             }),
             "invalid_message"
           ),
         true <- Map.has_key?(m, "stream_id") == Map.has_key?(m, "cursor"),
         :ok <- notification_params(m["method"], m["params"]) do
      :ok
    else
      false -> {:error, Error.new("invalid_message")}
      error -> error
    end
  end

  defp validate_envelope(_), do: {:error, Error.new("invalid_message")}

  def validate_params(method, params) do
    case @methods[method] do
      {_, _, required, optional, _, _} -> shape(params, required, optional, "invalid_params")
      nil -> {:error, Error.new("unsupported_method")}
    end
  end

  def validate_result(method, result) do
    case @methods[method] do
      {_, _, _, _, required, optional} -> shape(result, required, optional, "invalid_response")
      nil -> {:error, Error.new("unsupported_method")}
    end
  end

  def validate_reply(request, %{"result" => result}) do
    with :ok <- validate_result(request["method"], result),
         do: result_identity(request, result)
  end

  def validate_reply(_request, %{"error" => error}), do: error_shape(error)

  defp result_identity(
         %{"method" => "project/event.receive", "params" => %{"event" => event}},
         result
       ) do
    identity(
      result["event_id"] == event["event_id"] and
        result["delivery_attempt_id"] == event["delivery_attempt_id"]
    )
  end

  defp result_identity(%{"method" => "stream/resume", "params" => params}, result) do
    events = result["events"]

    contiguous =
      Enum.with_index(events, params["cursor"] + 1)
      |> Enum.all?(fn {event, cursor} ->
        event["stream_id"] == params["stream_id"] and event["cursor"] == cursor
      end)

    identity(
      result["stream_id"] == params["stream_id"] and contiguous and
        result["cursor"] == params["cursor"] + length(events)
    )
  end

  defp result_identity(%{"method" => method, "params" => params}, result) do
    keys =
      case method do
        "connection/initialize" -> []
        "thread/start" -> []
        "turn/start" -> ["thread_id"]
        "project/event.report" -> ["event_id", "decision_id"]
        "project/event.status" -> ["event_id"]
        "approval/request" -> ["approval_id"]
        "request/cancel" -> ["request_id"]
        _ -> Enum.filter(["thread_id", "turn_id"], &Map.has_key?(params, &1))
      end

    identity(Enum.all?(keys, &(params[&1] == result[&1])))
  end

  defp identity(true), do: :ok
  defp identity(false), do: {:error, Error.new("invalid_response")}

  def notification_params(method, params) do
    case @notifications[method] do
      {_, fields} -> shape(params, fields, %{}, "invalid_params")
      nil -> {:error, Error.new("unsupported_method")}
    end
  end

  def event_fields do
    {%{
       "schema_version" => {:enum, ["1.0"]},
       "event_id" => :id,
       "delivery_attempt_id" => :id,
       "created_at" => :timestamp,
       "correlation_id" => :id,
       "type" => :id,
       "payload" => :object
     }, Map.drop(@metadata, ["command_id"])}
  end

  def references(map) do
    if map["task_ref"] != nil and not valid?(map["project_ref"], :id),
      do: {:error, Error.new("invalid_message")},
      else: :ok
  end

  def shape(map, required, optional, code) when is_map(map) and not is_struct(map) do
    fields = Map.merge(required, optional)

    if Enum.all?(required, fn {key, rule} -> Map.has_key?(map, key) and valid?(map[key], rule) end) and
         Enum.all?(map, fn {key, value} ->
           Map.has_key?(fields, key) and valid?(value, fields[key])
         end),
       do: :ok,
       else: {:error, Error.new(code)}
  end

  def shape(_, _, _, code), do: {:error, Error.new(code)}

  def valid?(value, :id),
    do:
      is_binary(value) and byte_size(value) in 1..256 and String.valid?(value) and
        not String.match?(value, ~r/[\x00-\x20\x7f]/)

  def valid?(value, :string),
    do: is_binary(value) and byte_size(value) <= 65_536 and String.valid?(value)

  def valid?(value, :object), do: is_map(value) and json?(value)
  def valid?(value, :anything), do: json?(value)
  def valid?(value, :nonneg), do: is_integer(value) and value >= 0
  def valid?(value, :positive), do: is_integer(value) and value > 0

  def valid?(value, :strings),
    do:
      is_list(value) and length(value) <= 64 and Enum.uniq(value) == value and
        Enum.all?(value, &valid?(&1, :id))

  def valid?(value, :event), do: SamgitaProtocol.Event.validate(value) == :ok

  def valid?(value, :input),
    do:
      is_list(value) and length(value) in 1..64 and
        Enum.all?(
          value,
          &(shape(&1, %{"type" => {:enum, ["text"]}, "text" => :string}, %{}, "invalid_params") ==
              :ok)
        )

  def valid?(value, :notifications),
    do:
      is_list(value) and length(value) <= 128 and
        Enum.all?(value, &match?({:ok, %{"type" => "notification", "cursor" => _}}, validate(&1)))

  def valid?(value, :timestamp) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _, 0} -> true
      _ -> false
    end
  end

  def valid?(_, :timestamp), do: false
  def valid?(value, {:enum, values}), do: value in values
  def valid?(nil, {:nullable, _}), do: true
  def valid?(value, {:nullable, rule}), do: valid?(value, rule)

  def json?(value), do: json?(value, 0)
  defp json?(_, depth) when depth > 32, do: false
  defp json?(value, _) when is_nil(value) or is_boolean(value) or is_number(value), do: true
  defp json?(value, _) when is_binary(value), do: String.valid?(value)
  defp json?(value, depth) when is_list(value), do: Enum.all?(value, &json?(&1, depth + 1))

  defp json?(value, depth) when is_map(value) and not is_struct(value),
    do:
      Enum.all?(value, fn {key, val} ->
        is_binary(key) and String.valid?(key) and json?(val, depth + 1)
      end)

  defp json?(_, _), do: false

  defp version("1.0"), do: :ok
  defp version(_), do: {:error, Error.new("unsupported_version")}

  defp error_shape(error) do
    case Error.from_map(error) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp event_context(%{"method" => "project/event.receive", "params" => %{"event" => event}} = m) do
    if Enum.all?(["project_ref", "task_ref"], fn key ->
         not Map.has_key?(m, key) or m[key] == event[key]
       end),
       do: :ok,
       else: {:error, Error.new("invalid_params")}
  end

  defp event_context(_), do: :ok
end
