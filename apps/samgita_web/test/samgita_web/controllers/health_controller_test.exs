defmodule SamgitaWeb.HealthControllerTest do
  use SamgitaWeb.ConnCase

  describe "GET /api/health" do
    test "returns healthy status with DB checks", %{conn: conn} do
      conn = get(conn, "/api/health")
      assert json = json_response(conn, 200)

      assert json["status"] == "healthy"
      assert json["version"] == "0.1.0"
      assert json["timestamp"]
      assert is_integer(json["uptime_seconds"])
      assert json["checks"]["samgita_repo"] == "ok"
      assert json["checks"]["samgita_memory_repo"] == "ok"
    end

    test "does not require API key auth", %{conn: conn} do
      # No API key header — should still respond 200
      conn = get(conn, "/api/health")
      assert json_response(conn, 200)
    end
  end
end
