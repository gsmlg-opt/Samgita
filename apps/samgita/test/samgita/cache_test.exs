defmodule Samgita.CacheTest do
  use ExUnit.Case, async: false

  alias Samgita.Cache

  setup do
    # Use the application's cache, just clear before each test
    Cache.clear()
    :ok
  end

  test "put and get a value" do
    Cache.put("key1", "value1")
    assert {:ok, "value1"} = Cache.get("key1")
  end

  test "returns :miss for missing key" do
    assert :miss = Cache.get("nonexistent")
  end

  test "respects TTL" do
    Cache.put("short", "value", 1)
    Process.sleep(10)
    assert :miss = Cache.get("short")
  end

  test "clear removes all entries" do
    Cache.put("a", 1)
    Cache.put("b", 2)
    Cache.clear()
    assert :miss = Cache.get("a")
    assert :miss = Cache.get("b")
  end
end
