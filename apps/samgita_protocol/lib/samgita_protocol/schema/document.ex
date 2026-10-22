defmodule SamgitaProtocol.Schema.Document do
  @moduledoc "JSON Schema 2020-12 projection of v1 definitions. Runtime also checks byte limits and request context."
  alias SamgitaProtocol.{Error, Schema}

  def build do
    metadata = %{
      "causation_id" => {:nullable, :id},
      "project_ref" => {:nullable, :id},
      "task_ref" => {:nullable, :id}
    }

    common = %{"schema_version" => {:enum, ["1.0"]}, "correlation_id" => :id}

    request =
      shape(
        Map.merge(common, %{
          "type" => {:enum, ["request"]},
          "id" => :id,
          "method" => :id,
          "params" => :object
        }),
        Map.put(metadata, "command_id", :id)
      )

    notification =
      shape(
        Map.merge(common, %{
          "type" => {:enum, ["notification"]},
          "method" => :id,
          "params" => :object
        }),
        Map.merge(metadata, %{"stream_id" => :id, "cursor" => :positive})
      )

    response =
      shape(
        Map.merge(common, %{"type" => {:enum, ["response"]}, "id" => :id}),
        Map.merge(metadata, %{"command_id" => :id, "result" => :object, "error" => :error})
      )
      |> Map.put("oneOf", [
        %{"required" => ["result"], "not" => %{"required" => ["error"]}},
        %{"required" => ["error"], "not" => %{"required" => ["result"]}}
      ])

    requests =
      for {method, {_, mutation, required, optional, _, _}} <- Enum.sort(Schema.definitions()) do
        variant = %{
          "properties" => %{
            "method" => %{"const" => method},
            "params" => shape(required, optional)
          }
        }

        variant = if mutation, do: Map.put(variant, "required", ["command_id"]), else: variant
        %{"allOf" => [ref("request"), variant]}
      end

    notifications =
      for {method, {_, fields}} <- Enum.sort(Schema.notification_definitions()) do
        %{
          "allOf" => [
            ref("notification_envelope"),
            %{"properties" => %{"method" => %{"const" => method}, "params" => shape(fields, %{})}}
          ]
        }
      end

    results =
      Map.new(Schema.definitions(), fn {method, {_, _, _, _, required, optional}} ->
        {"result." <> String.replace(method, "/", "."), shape(required, optional)}
      end)

    {event_required, event_optional} = Schema.event_fields()

    definitions =
      Map.merge(results, %{
        "request" => request,
        "notification_envelope" =>
          Map.put(notification, "dependentRequired", %{
            "stream_id" => ["cursor"],
            "cursor" => ["stream_id"]
          }),
        "notification" => %{"oneOf" => notifications},
        "response" => response,
        "event" => event_required |> shape(event_optional) |> references(),
        "error" =>
          shape(
            %{
              "code" => {:enum, Error.codes() |> Enum.sort()},
              "message" => :string,
              "retryable" => :boolean,
              "details" => :object
            },
            %{}
          )
          |> put_in(["properties", "message", "maxLength"], 512)
      })

    %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "$id" => "urn:samgita:protocol:1.0",
      "title" => "Samgita neutral Agent protocol 1.0",
      "$comment" =>
        "Runtime additionally enforces UTF-8 byte bounds, JSON depth 32, contextual result identities, stream order and capability state. Response result definitions require the original pending method. Unsequenced notifications are ephemeral.",
      "$defs" => definitions,
      "allOf" => [%{"oneOf" => requests ++ [ref("notification"), ref("response")]}]
    }
    |> references()
  end

  defp references(schema) do
    rule = %{
      "if" => %{
        "required" => ["task_ref"],
        "properties" => %{"task_ref" => %{"type" => "string"}}
      },
      "then" => %{"required" => ["project_ref"], "properties" => %{"project_ref" => type(:id)}}
    }

    Map.update(schema, "allOf", [rule], &(&1 ++ [rule]))
  end

  defp shape(required, optional) do
    %{
      "type" => "object",
      "properties" =>
        Map.new(Map.merge(required, optional), fn {key, rule} -> {key, type(rule)} end),
      "required" => Map.keys(required) |> Enum.sort(),
      "additionalProperties" => false
    }
  end

  defp ref(name), do: %{"$ref" => "#/$defs/" <> name}

  defp type(:id),
    do: %{
      "type" => "string",
      "minLength" => 1,
      "maxLength" => 256,
      "pattern" => "^[^\\u0000-\\u0020\\u007f]+$"
    }

  defp type(:string), do: %{"type" => "string", "maxLength" => 65_536}
  defp type(:boolean), do: %{"type" => "boolean"}
  defp type(:object), do: %{"type" => "object"}
  defp type(:anything), do: %{}
  defp type(:nonneg), do: %{"type" => "integer", "minimum" => 0}
  defp type(:positive), do: %{"type" => "integer", "minimum" => 1}

  defp type(:strings),
    do: %{"type" => "array", "uniqueItems" => true, "maxItems" => 64, "items" => type(:id)}

  defp type(:timestamp),
    do: %{"type" => "string", "format" => "date-time", "pattern" => "(Z|[+-]00:00)$"}

  defp type(:event), do: ref("event")
  defp type(:error), do: ref("error")

  defp type(:input),
    do: %{
      "type" => "array",
      "minItems" => 1,
      "maxItems" => 64,
      "items" => shape(%{"type" => {:enum, ["text"]}, "text" => :string}, %{})
    }

  defp type(:notifications),
    do: %{
      "type" => "array",
      "maxItems" => 128,
      "items" => %{"allOf" => [ref("notification"), %{"required" => ["stream_id", "cursor"]}]}
    }

  defp type({:enum, values}), do: %{"enum" => values}
  defp type({:nullable, rule}), do: %{"anyOf" => [type(rule), %{"type" => "null"}]}
end
