defmodule SamgitaProtocolCodex.Schema.Input do
  @moduledoc false

  alias SamgitaProtocolCodex.Error

  # ThreadStartParams uses a custom serde decoder omitted by the JSON exporter.
  # Keep its accepted input contract separate from the untouched official export.
  @root Path.expand("../../../priv/upstream/0.163.0", __DIR__)
  @semantics_path Path.join(@root, "source/input-semantics.json")
  @external_resource @semantics_path
  @semantics @semantics_path |> File.read!() |> JSON.decode!()
  @legacy @semantics["legacy_schema"]

  unless @semantics["upstream_commit"] == "83086188ae0614bd882818ff1aa23f3194962012" do
    raise "pinned input contract commit changed"
  end

  for {relative, expected} <-
        Map.merge(
          @semantics["source_sha256"],
          Map.new(@semantics["schemas_sha256"], fn {name, hash} ->
            {"experimental/" <> name, hash}
          end)
        ) do
    @external_resource Path.join(@root, relative)
    unless Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@root, relative))),
             case: :lower
           ) == expected do
      raise "pinned input contract source or export changed"
    end
  end

  def contract("ClientRequest.json", "thread/start", document) do
    update_in(document, ["definitions", "ThreadStartParams", "properties"], fn properties ->
      case Map.fetch(properties, "dynamicTools") do
        {:ok, schema} ->
          Map.put(
            properties,
            "dynamicTools",
            Map.update!(schema, "items", &%{"oneOf" => [&1, @legacy]})
          )

        :error ->
          properties
      end
    end)
  end

  def contract(_filename, _method, document), do: document

  def check(:client_request, "thread/start", %{"params" => %{"dynamicTools" => tools}})
      when is_list(tools) do
    canonical = Enum.any?(tools, &(is_map(&1) and Map.has_key?(&1, "type")))
    legacy = Enum.any?(tools, &(legacy_fields?(&1) or nested_legacy?(&1)))

    if canonical and legacy,
      do:
        {:error,
         Error.new(:schema_violation, %{
           "path" => ["params", "dynamicTools"],
           "keyword" => "canonicalOrLegacy"
         })},
      else: :ok
  end

  def check(_direction, _method, _value), do: :ok

  defp legacy_fields?(value) when is_map(value),
    do:
      Map.has_key?(value, "namespace") or Map.has_key?(value, "exposeToContext") or
        not Map.has_key?(value, "type")

  defp legacy_fields?(_value), do: true

  defp nested_legacy?(%{"tools" => tools}) when is_list(tools),
    do: Enum.any?(tools, &legacy_fields?/1)

  defp nested_legacy?(_value), do: false
end
