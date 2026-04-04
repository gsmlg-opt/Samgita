defmodule Samgita.Provider.HealthCheckerTest do
  use ExUnit.Case, async: false

  alias Samgita.Provider.HealthChecker

  # HealthChecker is started in Application supervisor, so it's already running

  describe "healthy?/1" do
    test "returns false for unknown endpoint" do
      refute HealthChecker.healthy?("http://unknown:9999")
    end
  end

  describe "all_statuses/0" do
    test "returns a list" do
      assert is_list(HealthChecker.all_statuses())
    end
  end

  describe "healthy_endpoints/1" do
    test "returns empty list when no endpoints healthy" do
      project = %{synapsis_endpoints: [%{"url" => "http://fake:1234"}]}
      assert HealthChecker.healthy_endpoints(project) == []
    end

    test "handles nil synapsis_endpoints" do
      project = %{synapsis_endpoints: nil}
      assert HealthChecker.healthy_endpoints(project) == []
    end
  end

  describe "register_endpoint/1" do
    test "does not crash" do
      assert :ok = HealthChecker.register_endpoint("http://test:5000")
    end
  end
end
