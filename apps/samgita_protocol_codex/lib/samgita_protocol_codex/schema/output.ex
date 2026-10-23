defmodule SamgitaProtocolCodex.Schema.Output do
  @moduledoc false

  # schemars in the immutable release omits serde's rename_all_fields on timeline
  # boundaries and realtime promotions. Separate descriptors are checked against the
  # exact Rust source, executable-generated TypeScript and original JSON export.
  @root Path.expand("../../../priv/upstream/0.163.0", __DIR__)
  @corrections (for relative <- [
                      "source/output-semantics.json",
                      "source/realtime-output-semantics.json"
                    ] do
                  path = Path.join(@root, relative)
                  @external_resource path
                  path |> File.read!() |> JSON.decode!()
                end)

  for correction <- @corrections do
    unless correction["upstream_commit"] == "83086188ae0614bd882818ff1aa23f3194962012" do
      raise "pinned output contract commit changed"
    end

    schemas =
      correction["schemas_sha256"] ||
        %{correction["schema"] => correction["official_schema_sha256"]}

    for {relative, expected} <-
          Map.merge(
            correction["source_sha256"],
            Map.new(schemas, fn {name, hash} -> {"experimental/" <> name, hash} end)
          ) do
      @external_resource Path.join(@root, relative)
      unless Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@root, relative))),
               case: :lower
             ) == expected do
        raise "pinned output contract source or export changed"
      end
    end
  end

  def contract(filename, document) do
    Enum.reduce(@corrections, document, fn correction, document ->
      if filename == correction["schema"] or
           Map.has_key?(correction["schemas_sha256"] || %{}, filename) do
        update_in(document, ["definitions", correction["definition"], "oneOf"], fn branches ->
          Enum.map(branches, &rename_boundary(&1, correction))
        end)
      else
        document
      end
    end)
  end

  defp rename_boundary(branch, correction) do
    tag = branch["properties"]["type"]["enum"] |> hd()
    renames = Map.get(correction["renames"], tag, %{})

    branch
    |> Map.update!("properties", fn properties ->
      Map.new(properties, fn {key, schema} -> {Map.get(renames, key, key), schema} end)
    end)
    |> Map.update!("required", &Enum.map(&1, fn key -> Map.get(renames, key, key) end))
  end
end
