defmodule SamgitaWeb.Plugs.GitHubRawBody do
  @moduledoc "Capture bounded webhook bytes before parsers; never log or normalize signed input."
  import Plug.Conn
  def init(opts), do: opts

  def call(%{method: "POST", path_info: ["api", "github", "webhooks", _]} = conn, _) do
    case read_body(conn, length: 1_048_576, read_length: 65_536, read_timeout: 5_000) do
      {:ok, body, conn} ->
        # Plug.Parsers skips fetched body_params. Signature verification precedes JSON decoding.
        %{conn | body_params: %{}} |> put_private(:github_raw_body, body)

      {:more, _, conn} ->
        reject(conn, 413, "payload_too_large")

      {:error, _} ->
        reject(conn, 400, "body_read_failed")
    end
  end

  def call(conn, _), do: conn

  defp reject(conn, status, code),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(%{errors: %{code: code}}))
      |> halt()
end
