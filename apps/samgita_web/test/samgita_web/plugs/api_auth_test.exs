defmodule SamgitaWeb.Plugs.ApiAuthTest do
  use SamgitaWeb.ConnCase, async: true

  alias SamgitaWeb.Plugs.ApiAuth

  setup do
    Application.put_env(:samgita, :api_keys, ["test-key-123"])
    on_exit(fn -> Application.put_env(:samgita, :api_keys, []) end)
    :ok
  end

  test "allows request with valid API key", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-api-key", "test-key-123")
      |> ApiAuth.call([])

    refute conn.halted
  end

  test "rejects request with invalid API key", %{conn: conn} do
    conn =
      conn
      |> put_req_header("x-api-key", "wrong-key")
      |> ApiAuth.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "rejects request without API key", %{conn: conn} do
    conn = ApiAuth.call(conn, [])
    assert conn.halted
    assert conn.status == 401
  end

  test "allows all requests when no API keys configured", %{conn: conn} do
    Application.put_env(:samgita, :api_keys, [])
    conn = ApiAuth.call(conn, [])
    refute conn.halted
  end
end
