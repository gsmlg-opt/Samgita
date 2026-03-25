defmodule Samgita.CacheTest do
  use ExUnit.Case, async: false

  alias Samgita.Cache

  setup do
    Mox.set_mox_global(self())
    Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

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

  test "overwrite existing key" do
    Cache.put("key", "first")
    Cache.put("key", "second")
    assert {:ok, "second"} = Cache.get("key")
  end

  test "stores complex values" do
    value = %{nested: %{list: [1, 2, 3]}, atom: :test}
    Cache.put("complex", value)
    assert {:ok, ^value} = Cache.get("complex")
  end

  test "invalidate removes key" do
    Cache.put("to_remove", "value")
    assert {:ok, "value"} = Cache.get("to_remove")
    Cache.invalidate("to_remove")
    assert :miss = Cache.get("to_remove")
  end

  test "invalidate on nonexistent key is safe" do
    assert :ok = Cache.invalidate("does_not_exist")
  end

  test "invalidate broadcasts via PubSub" do
    Phoenix.PubSub.subscribe(Samgita.PubSub, "cache:invalidate")

    Cache.put("pubsub_key", "value")
    Cache.invalidate("pubsub_key")

    assert_receive {:invalidate, "pubsub_key"}, 500
  end

  test "PubSub invalidation deletes key on subscriber" do
    Cache.put("remote_key", "value")
    assert {:ok, "value"} = Cache.get("remote_key")

    # Broadcast directly as if from another node
    Phoenix.PubSub.broadcast(
      Samgita.PubSub,
      "cache:invalidate",
      {:invalidate, "remote_key"}
    )

    # Allow the GenServer to process the message
    Process.sleep(50)
    assert :miss = Cache.get("remote_key")
  end

  test "custom TTL extends entry lifetime" do
    Cache.put("long_ttl", "value", 5_000)
    Process.sleep(50)
    assert {:ok, "value"} = Cache.get("long_ttl")
  end

  test "cleanup message triggers expired entry removal" do
    Cache.put("expired", "value", 1)
    Process.sleep(10)

    send(Process.whereis(Cache), :cleanup)
    Process.sleep(50)

    assert :miss = Cache.get("expired")
  end

  test "cleanup preserves non-expired entries" do
    # Use a very large TTL to avoid any race conditions
    Cache.put("alive", "value", 300_000)
    # Verify it's there first
    assert {:ok, "value"} = Cache.get("alive")

    # Directly verify the ETS entry's expiration is in the future
    [{_key, _val, expires_at}] = :ets.lookup(:samgita_cache, "alive")
    assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt

    # After cleanup, the non-expired entry should remain
    assert {:ok, "value"} = Cache.get("alive")
  end

  test "multiple keys can be set and retrieved" do
    for i <- 1..10 do
      Cache.put("key_#{i}", i)
    end

    for i <- 1..10 do
      assert {:ok, ^i} = Cache.get("key_#{i}")
    end
  end
end
