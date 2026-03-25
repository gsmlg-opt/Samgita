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

    test "returns environment field as string", %{conn: conn} do
      conn = get(conn, "/api/info")
      json = json_response(conn, 200)

      assert is_binary(json["environment"])
      # In test, environment should be "test" (from config or Mix.env fallback)
      assert json["environment"] == "test"
    end

    test "returns all expected fields with correct types", %{conn: conn} do
      conn = get(conn, "/api/info")
      json = json_response(conn, 200)

      assert Map.has_key?(json, "app")
      assert Map.has_key?(json, "version")
      assert Map.has_key?(json, "elixir")
      assert Map.has_key?(json, "otp")
      assert Map.has_key?(json, "environment")
      assert Map.has_key?(json, "umbrella_apps")
      assert Map.has_key?(json, "phoenix")
      assert Map.has_key?(json, "endpoint")

      # Each umbrella app has name and version
      for app <- json["umbrella_apps"] do
        assert Map.has_key?(app, "name")
        assert Map.has_key?(app, "version")
        assert is_binary(app["name"])
        assert is_binary(app["version"])
      end
    end

    test "does not require API key auth", %{conn: conn} do
      conn = get(conn, "/api/info")
      assert json_response(conn, 200)
    end
  end
end
