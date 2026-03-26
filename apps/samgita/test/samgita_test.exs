defmodule SamgitaTest do
  use Samgita.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox

  setup do
    pid = Sandbox.start_owner!(SamgitaMemory.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  describe "health_checks/0" do
    test "returns ok for both repos when connected" do
      result = Samgita.health_checks()
      assert %{samgita_repo: :ok, samgita_memory_repo: :ok} = result
    end

    test "returns exactly two check keys" do
      result = Samgita.health_checks()
      assert map_size(result) == 2
      assert Map.has_key?(result, :samgita_repo)
      assert Map.has_key?(result, :samgita_memory_repo)
    end
  end
end
