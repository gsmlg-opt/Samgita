defmodule Samgita.ReferencesTest do
  use ExUnit.Case, async: true

  alias Samgita.References

  describe "list_references/0" do
    test "returns all references" do
      refs = References.list_references()
      assert length(refs) == 20
    end

    test "references have required fields" do
      refs = References.list_references()

      Enum.each(refs, fn ref ->
        assert Map.has_key?(ref, :title)
        assert Map.has_key?(ref, :category)
        assert Map.has_key?(ref, :description)
        assert Map.has_key?(ref, :filename)
        assert String.ends_with?(ref.filename, ".md")
      end)
    end

    test "references are sorted by title" do
      refs = References.list_references()
      titles = Enum.map(refs, & &1.title)
      assert titles == Enum.sort(titles)
    end
  end

  describe "list_by_category/0" do
    test "groups references by category" do
      grouped = References.list_by_category()
      assert is_list(grouped)

      categories = Enum.map(grouped, fn {category, _} -> category end)
      assert "Architecture" in categories
      assert "Agents" in categories
    end

    test "categories are sorted alphabetically" do
      grouped = References.list_by_category()
      categories = Enum.map(grouped, fn {category, _} -> category end)
      assert categories == Enum.sort(categories)
    end
  end

  describe "get_reference/1" do
    test "returns reference with content for valid filename" do
      assert {:ok, ref} = References.get_reference("agents.md")
      assert ref.title == "Agent Type Definitions"
      assert ref.filename == "agents.md"
      assert is_binary(ref.content)
      assert String.length(ref.content) > 0
    end

    test "returns error for nonexistent filename" do
      assert {:error, :not_found} = References.get_reference("nonexistent.md")
    end
  end

  describe "category_color/1" do
    test "returns color for known categories" do
      assert References.category_color("Agents") =~ "purple"
      assert References.category_color("Research") =~ "blue"
      assert References.category_color("Architecture") =~ "green"
      assert References.category_color("Quality") =~ "pink"
    end

    test "returns default color for unknown categories" do
      assert References.category_color("Unknown") =~ "zinc"
    end
  end
end
