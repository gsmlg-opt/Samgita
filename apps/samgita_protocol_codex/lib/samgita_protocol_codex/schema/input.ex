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
                      "source/multi-agent-input-semantics.json",
                      "source/reasoning-summary-input-semantics.json",
                      "source/personality-input-semantics.json",
                      "source/history-mode-input-semantics.json",
                      "source/thread-start-source-input-semantics.json",
                      "source/thread-search-sort-key-input-semantics.json",
                      "source/thread-sort-key-input-semantics.json",
                      "source/sort-direction-input-semantics.json",
                      "source/project-sort-key-input-semantics.json"
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
  @summary Enum.find(@corrections, &(&1["definition"] == "ReasoningSummary"))
  @summary_methods @summary["methods"]
  @personality Enum.find(@corrections, &(&1["definition"] == "Personality"))
  @history_mode Enum.find(@corrections, &(&1["definition"] == "ThreadHistoryMode"))
  @start_source Enum.find(@corrections, &(&1["definition"] == "ThreadStartSource"))
  @search_sort Enum.find(@corrections, &(&1["definition"] == "ThreadSearchSortKey"))
  @list_sort Enum.find(@corrections, &(&1["definition"] == "ThreadSortKey"))
  @direction Enum.find(@corrections, &(&1["definition"] == "SortDirection"))
  @project_sort Enum.find(@corrections, &(&1["definition"] == "ProjectSortKey"))

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
    |> personality_input()
    |> history_mode_input()
    |> start_source_input()
  end

  def contract("ClientRequest.json", "thread/resume", document) do
    update_in(
      document,
      ["definitions", "ResponseItem", "oneOf"],
      &Enum.map(&1, fn branch -> response_input(branch) end)
    )
    |> personality_input()
    |> direction_input()
  end

  def contract("ClientRequest.json", method, document)
      when method in @collaboration_methods do
    update_in(
      document,
      ["definitions", "ModeKind"],
      &collaboration_input/1
    )
    |> multi_agent_input()
    |> summary_input()
    |> personality_input()
  end

  def contract("ClientRequest.json", method, document) when method in @summary_methods,
    do: summary_input(document)

  def contract("ClientRequest.json", "thread/search", document),
    do: document |> search_sort_input() |> direction_input()

  def contract("ClientRequest.json", "thread/list", document),
    do: document |> list_sort_input() |> direction_input()

  def contract("ClientRequest.json", "project/list", document),
    do: document |> project_sort_input() |> direction_input()

  def contract("ClientRequest.json", method, document)
      when method in ["thread/turns/list", "thread/items/list"],
      do: direction_input(document)

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

  defp summary_input(document) do
    update_in(
      document,
      ["definitions", "ReasoningSummary"],
      &%{"oneOf" => [&1 | @summary["input_object_branches"]]}
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

  defp personality_input(document) do
    update_in(
      document,
      ["definitions", "Personality"],
      &%{"oneOf" => [&1 | @personality["input_object_branches"]]}
    )
  end

  defp history_mode_input(document) do
    update_in(
      document,
      ["definitions", "ThreadHistoryMode"],
      &%{"oneOf" => [&1 | @history_mode["input_object_branches"]]}
    )
  end

  defp start_source_input(document) do
    update_in(
      document,
      ["definitions", "ThreadStartSource"],
      &%{"oneOf" => [&1 | @start_source["input_object_branches"]]}
    )
  end

  defp search_sort_input(document) do
    update_in(
      document,
      ["definitions", "ThreadSearchSortKey"],
      &%{"oneOf" => [&1 | @search_sort["input_object_branches"]]}
    )
  end

  defp list_sort_input(document) do
    update_in(
      document,
      ["definitions", "ThreadSortKey"],
      &%{"oneOf" => [&1 | @list_sort["input_object_branches"]]}
    )
  end

  defp direction_input(document) do
    update_in(
      document,
      ["definitions", "SortDirection"],
      &%{"oneOf" => [&1 | @direction["input_object_branches"]]}
    )
  end

  defp project_sort_input(document) do
    update_in(
      document,
      ["definitions", "ProjectSortKey"],
      &%{"oneOf" => [&1 | @project_sort["input_object_branches"]]}
    )
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
