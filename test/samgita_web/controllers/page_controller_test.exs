defmodule SamgitaWeb.PageControllerTest do
  use SamgitaWeb.ConnCase

  test "GET / redirects to dashboard LiveView", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Dashboard"
  end
end
