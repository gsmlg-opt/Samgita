defmodule SamgitaMemory.CacheTest do
  use ExUnit.Case, async: false

  alias SamgitaMemory.Cache.MemoryTable
  alias SamgitaMemory.Cache.PRDTable

  describe "MemoryTable" do
    setup do
      MemoryTable.clear()
      :ok
    end

    test "put and get" do
      MemoryTable.put(:project, "p1", "mem-1", %{content: "test"})
      assert {:ok, %{content: "test"}} = MemoryTable.get(:project, "p1", "mem-1")
    end

    test "returns :miss for non-existent entry" do
      assert :miss = MemoryTable.get(:project, "p1", "nonexistent")
    end

    test "invalidate removes entry" do
      MemoryTable.put(:project, "p1", "mem-1", %{content: "test"})
      MemoryTable.invalidate(:project, "p1", "mem-1")
      assert :miss = MemoryTable.get(:project, "p1", "mem-1")
    end

    test "clear removes all entries" do
      MemoryTable.put(:project, "p1", "m1", %{})
      MemoryTable.put(:project, "p1", "m2", %{})
      MemoryTable.clear()
      assert MemoryTable.size() == 0
    end
  end

  describe "PRDTable" do
    setup do
      PRDTable.clear()
      :ok
    end

    test "put and get" do
      PRDTable.put("prd-1", %{execution: %{status: :in_progress}})
      assert {:ok, %{execution: %{status: :in_progress}}} = PRDTable.get("prd-1")
    end

    test "returns :miss for non-existent entry" do
      assert :miss = PRDTable.get("nonexistent")
    end

    test "invalidate removes entry" do
      PRDTable.put("prd-1", %{})
      PRDTable.invalidate("prd-1")
      assert :miss = PRDTable.get("prd-1")
    end
  end
end
