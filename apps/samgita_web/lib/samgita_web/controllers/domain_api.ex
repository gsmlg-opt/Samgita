defmodule SamgitaWeb.DomainAPI do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def principal(conn), do: Map.fetch!(conn.assigns, :samgita_principal)

  def attrs(conn) do
    case conn.body_params do
      attrs when is_map(attrs) and not is_struct(attrs) -> attrs
      _ -> %{}
    end
  end

  def result(conn, result, status \\ :ok)

  def result(conn, {:ok, %{"data" => data} = page}, status) when is_list(data) do
    conn
    |> put_status(status)
    |> json(page)
  end

  def result(conn, {:ok, data}, status) do
    conn
    |> put_status(status)
    |> json(%{data: data})
  end

  def result(_conn, {:error, error}, _status), do: {:error, error}

  def no_store(conn), do: put_resp_header(conn, "cache-control", "no-store")
end
