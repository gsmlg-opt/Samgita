defmodule SamgitaWeb.InfoControllerTest do
  use SamgitaWeb.ConnCase

  describe "GET /api/info" do
    test "returns app metadata", %{conn: conn} do
      conn = get(conn, "/api/info")
      assert json = json_response(conn, 200)

      assert json["app"] == "samgita"
      assert json["version"] == "0.1.0"
      assert is_binary(json["elixir"])
      assert is_binary(json["otp"])
      assert is_binary(json["phoenix"])
      assert is_binary(json["endpoint"])
      assert is_list(json["umbrella_apps"])
      assert length(json["umbrella_apps"]) == 4

      app_names = Enum.map(json["umbrella_apps"], & &1["name"])
      assert "samgita_provider" in app_names
      assert "samgita" in app_names
      assert "samgita_memory" in app_names
      assert "samgita_web" in app_names
    end

    test "does not require API key auth", %{conn: conn} do
      conn = get(conn, "/api/info")
      assert json_response(conn, 200)
    end
  end
end
