defmodule SamgitaProtocolCodex.Schema.Output do
  @moduledoc false

  # schemars in the immutable release omits serde's rename_all_fields on two
  # timeline variants. The separately derived descriptor is checked against the
  # exact Rust source, executable-generated TypeScript and original JSON export.
  @root Path.expand("../../../priv/upstream/0.163.0", __DIR__)
  @semantics Path.join(@root, "source/output-semantics.json")
  @external_resource @semantics
  @correction @semantics |> File.read!() |> JSON.decode!()
  @schema @correction["schema"]
  @official Path.join([@root, "experimental", @schema])
  @external_resource @official

  unless @correction["upstream_commit"] == "83086188ae0614bd882818ff1aa23f3194962012" and
           Base.encode16(:crypto.hash(:sha256, File.read!(@official)), case: :lower) ==
             @correction["official_schema_sha256"] do
    raise "pinned timeline output contract changed"
  end

  for {relative, expected} <- @correction["source_sha256"] do
    @external_resource Path.join(@root, relative)
    unless Base.encode16(:crypto.hash(:sha256, File.read!(Path.join(@root, relative))),
             case: :lower
           ) ==
             expected do
      raise "pinned timeline output source changed"
    end
  end

  def contract(@schema, document) do
    update_in(document, ["definitions", @correction["definition"], "oneOf"], fn branches ->
      Enum.map(branches, &rename_boundary/1)
    end)
  end

  def contract(_filename, document), do: document

  defp rename_boundary(branch) do
    tag = branch["properties"]["type"]["enum"] |> hd()
    renames = Map.get(@correction["renames"], tag, %{})

    branch
    |> Map.update!("properties", fn properties ->
      Map.new(properties, fn {key, schema} -> {Map.get(renames, key, key), schema} end)
    end)
    |> Map.update!("required", &Enum.map(&1, fn key -> Map.get(renames, key, key) end))
  end
end
