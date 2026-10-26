defmodule SamgitaProtocolCodex.Schema.Input do
  @moduledoc false

  alias SamgitaProtocolCodex.Error

  # The exporter omits a custom decoder and serde input aliases. Source-derived
  # contracts remain separate from official exports and caller wire values.
  @root Path.expand("../../../priv/upstream/0.163.0", __DIR__)
  @corrections (for relative <- [
                      "source/input-semantics.json",
                      "source/response-item-input-semantics.json",
                      "source/collaboration-input-semantics.json",
                      "source/multi-agent-input-semantics.json"
                    ] do
                  path = Path.join(@root, relative)
                  @external_resource path
                  path |> File.read!() |> JSON.decode!()
                end)
  @legacy Enum.find_value(@corrections, & &1["legacy_schema"])
  @response Enum.find(@corrections, &(&1["definition"] == "ResponseItem"))
  @collaboration Enum.find(@corrections, &(&1["definition"] == "ModeKind"))
  @collaboration_methods @collaboration["methods"]
  @multi_agent Enum.find(@corrections, &(&1["definition"] == "MultiAgentMode"))

  for semantics <- @corrections do
    unless semantics["upstream_commit"] == "83086188ae0614bd882818ff1aa23f3194962012" do
      raise "pinned input contract commit changed"
    end

    for {relative, expected} <-
          Map.merge(
            semantics["source_sha256"],
            Map.new(semantics["schemas_sha256"], fn {name, hash} ->
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
    |> multi_agent_input()
  end

  def contract("ClientRequest.json", "thread/resume", document) do
    update_in(
      document,
      ["definitions", "ResponseItem", "oneOf"],
      &Enum.map(&1, fn branch -> response_input(branch) end)
    )
  end

  def contract("ClientRequest.json", method, document)
      when method in @collaboration_methods do
    update_in(
      document,
      ["definitions", "ModeKind"],
      &collaboration_input/1
    )
    |> multi_agent_input()
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

  defp collaboration_input(schema) do
    canonical = Map.update!(schema, "enum", &(&1 ++ @collaboration["input_aliases"]))
    %{"oneOf" => [canonical | @collaboration["input_object_branches"]]}
  end

  defp multi_agent_input(document) do
    update_in(
      document,
      ["definitions", "MultiAgentMode", "oneOf"],
      &(&1 ++ @multi_agent["input_branches"])
    )
  end

  defp response_input(branch) do
    if get_in(branch, ["properties", "type", "enum"]) == [@response["canonical_tag"]],
      do:
        put_in(
          branch,
          ["properties", "type", "enum"],
          [@response["canonical_tag"] | @response["input_aliases"]]
        ),
      else: branch
  end

  defp legacy_fields?(value) when is_map(value),
    do:
      Map.has_key?(value, "namespace") or Map.has_key?(value, "exposeToContext") or
        not Map.has_key?(value, "type")

  defp legacy_fields?(_value), do: true

  defp nested_legacy?(%{"tools" => tools}) when is_list(tools),
    do: Enum.any?(tools, &legacy_fields?/1)

  defp nested_legacy?(_value), do: false
end
