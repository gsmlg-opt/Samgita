defmodule SamgitaWeb.Plugs.ApiAuth do
  @moduledoc """
  API authentication plug that verifies API keys from the x-api-key header.
  API keys are configured via the SAMGITA_API_KEYS environment variable.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-api-key") do
      [key] -> verify_api_key(conn, key)
      _ -> unauthorized(conn)
    end
  end

  defp verify_api_key(conn, key) do
    valid_keys = Application.get_env(:samgita, :api_keys, [])

    if key in valid_keys do
      conn
    else
      unauthorized(conn)
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{error: "Unauthorized", message: "Invalid or missing API key"})
    |> halt()
  end
end
