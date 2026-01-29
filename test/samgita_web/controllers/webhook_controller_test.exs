defmodule SamgitaWeb.WebhookControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Webhooks

  @valid_attrs %{
    url: "https://example.com/hook",
    events: ["task.completed", "task.failed"]
  }

  defp create_webhook(_) do
    {:ok, webhook} = Webhooks.create_webhook(@valid_attrs)
    %{webhook: webhook}
  end

  describe "index" do
    test "lists all webhooks when empty", %{conn: conn} do
      conn = get(conn, ~p"/api/webhooks")
      assert json_response(conn, 200)["data"] == []
    end

    test "lists all webhooks", %{conn: conn} do
      {:ok, webhook} = Webhooks.create_webhook(@valid_attrs)
      conn = get(conn, ~p"/api/webhooks")
      data = json_response(conn, 200)["data"]
      assert [%{"id" => id}] = data
      assert id == webhook.id
    end
  end

  describe "create" do
    test "creates webhook with valid attrs", %{conn: conn} do
      conn =
        post(conn, ~p"/api/webhooks", %{
          webhook: %{
            url: "https://example.com/new-hook",
            events: ["task.completed"]
          }
        })

      assert %{"data" => %{"id" => _id, "url" => url}} = json_response(conn, 201)
      assert url == "https://example.com/new-hook"
    end

    test "returns error with invalid URL", %{conn: conn} do
      conn =
        post(conn, ~p"/api/webhooks", %{
          webhook: %{url: "not-a-url", events: ["task.completed"]}
        })

      assert json_response(conn, 422)["errors"] != %{}
    end

    test "returns error with invalid events", %{conn: conn} do
      conn =
        post(conn, ~p"/api/webhooks", %{
          webhook: %{url: "https://example.com/hook", events: ["bogus.event"]}
        })

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete" do
    setup [:create_webhook]

    test "deletes webhook", %{conn: conn, webhook: webhook} do
      conn = delete(conn, ~p"/api/webhooks/#{webhook.id}")
      assert response(conn, 204)
    end

    test "returns 404 for nonexistent webhook", %{conn: conn} do
      conn = delete(conn, ~p"/api/webhooks/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end
  end
end
