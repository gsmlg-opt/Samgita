defmodule SamgitaWeb.FeatureControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Features

  @valid_attrs %{
    name: "Test Feature",
    description: "A test feature with enough description length",
    status: "draft",
    priority: "medium",
    tags: ["test", "api"]
  }

  defp create_feature(_) do
    {:ok, feature} =
      Features.create_feature(%{
        name: "Existing Feature #{System.unique_integer([:positive])}",
        description: "An existing feature for testing purposes"
      })

    %{feature: feature}
  end

  describe "index" do
    test "lists all features when empty", %{conn: conn} do
      conn = get(conn, ~p"/api/features")
      assert json_response(conn, 200)["data"] == []
    end

    test "lists features after creation", %{conn: conn} do
      {:ok, feature} =
        Features.create_feature(%{
          name: "Listed Feature #{System.unique_integer([:positive])}",
          description: "A feature that should appear in the list"
        })

      conn = get(conn, ~p"/api/features")
      data = json_response(conn, 200)["data"]
      assert length(data) >= 1
      assert Enum.any?(data, &(&1["id"] == feature.id))
    end

    test "filters features by status", %{conn: conn} do
      conn = get(conn, ~p"/api/features?status=active")
      data = json_response(conn, 200)["data"]
      Enum.each(data, fn f -> assert f["status"] == "active" end)
    end
  end

  describe "create" do
    test "creates feature with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/features", feature: @valid_attrs)
      data = json_response(conn, 201)["data"]
      assert data["name"] == "Test Feature"
      assert data["status"] == "draft"
      assert data["priority"] == "medium"
      assert data["tags"] == ["test", "api"]
    end

    test "returns errors for missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/features", feature: %{})
      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns errors for too short name", %{conn: conn} do
      conn =
        post(conn, ~p"/api/features",
          feature: %{name: "AB", description: "Valid desc length here"}
        )

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "show" do
    setup [:create_feature]

    test "shows feature", %{conn: conn, feature: feature} do
      conn = get(conn, ~p"/api/features/#{feature}")
      data = json_response(conn, 200)["data"]
      assert data["id"] == feature.id
    end

    test "returns 404 for missing feature", %{conn: conn} do
      conn = get(conn, ~p"/api/features/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end

  describe "update" do
    setup [:create_feature]

    test "updates feature", %{conn: conn, feature: feature} do
      conn =
        put(conn, ~p"/api/features/#{feature}",
          feature: %{description: "Updated description with enough length"}
        )

      data = json_response(conn, 200)["data"]
      assert data["description"] == "Updated description with enough length"
    end
  end

  describe "delete" do
    setup [:create_feature]

    test "deletes feature", %{conn: conn, feature: feature} do
      conn = delete(conn, ~p"/api/features/#{feature}")
      assert response(conn, 204)
    end
  end

  describe "enable" do
    setup [:create_feature]

    test "enables a feature", %{conn: conn, feature: feature} do
      conn = post(conn, ~p"/api/features/#{feature}/enable")
      data = json_response(conn, 200)["data"]
      assert data["enabled"] == true
    end

    test "returns 404 for missing feature", %{conn: conn} do
      conn = post(conn, ~p"/api/features/#{Ecto.UUID.generate()}/enable")
      assert json_response(conn, 404)
    end
  end

  describe "disable" do
    test "disables a feature", %{conn: conn} do
      {:ok, feature} =
        Features.create_feature(%{
          name: "Enabled Feature #{System.unique_integer([:positive])}",
          description: "A feature that will be disabled soon",
          enabled: true
        })

      conn = post(conn, ~p"/api/features/#{feature}/disable")
      data = json_response(conn, 200)["data"]
      assert data["enabled"] == false
    end
  end

  describe "archive" do
    setup [:create_feature]

    test "archives a feature", %{conn: conn, feature: feature} do
      conn = post(conn, ~p"/api/features/#{feature}/archive")
      data = json_response(conn, 200)["data"]
      assert data["status"] == "archived"
      assert data["enabled"] == false
    end

    test "returns 404 for missing feature", %{conn: conn} do
      conn = post(conn, ~p"/api/features/#{Ecto.UUID.generate()}/archive")
      assert json_response(conn, 404)
    end
  end
end
