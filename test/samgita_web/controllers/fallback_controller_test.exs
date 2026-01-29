defmodule SamgitaWeb.FallbackControllerTest do
  use SamgitaWeb.ConnCase, async: true

  alias Samgita.Domain.Project
  alias SamgitaWeb.FallbackController

  defp json_conn(%{conn: conn}) do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> Map.put(:params, %{"_format" => "json"})

    {:ok, conn: conn}
  end

  describe "call/2" do
    setup :json_conn

    test "renders 404 for :not_found error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_found})
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end

    test "renders 422 for :not_running error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_running})
      assert conn.status == 422
    end

    test "renders 422 for :not_paused error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_paused})
      assert conn.status == 422
    end

    test "renders 422 for :not_retriable error", %{conn: conn} do
      conn = FallbackController.call(conn, {:error, :not_retriable})
      assert conn.status == 422
    end

    test "renders 422 for changeset error", %{conn: conn} do
      changeset =
        %Project{}
        |> Project.changeset(%{name: nil})

      conn = FallbackController.call(conn, {:error, changeset})
      assert conn.status == 422
      assert json_response(conn, 422)["errors"]
    end
  end
end
