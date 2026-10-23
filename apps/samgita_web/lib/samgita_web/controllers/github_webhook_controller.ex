defmodule SamgitaWeb.GitHubWebhookController do
  use SamgitaWeb, :controller

  def create(conn, %{"connection_id" => id}) do
    with [event] <- get_req_header(conn, "x-github-event"),
         [delivery] <- get_req_header(conn, "x-github-delivery"),
         [signature] <- get_req_header(conn, "x-hub-signature-256"),
         raw when is_binary(raw) <- conn.private[:github_raw_body] do
      respond(conn, Samgita.GitHub.ingest(id, event, delivery, raw, signature))
    else
      _ -> failure(conn, :invalid)
    end
  rescue
    _ in [Postgrex.Error, DBConnection.ConnectionError] -> failure(conn, :persistence_unavailable)
  end

  defp respond(conn, {:ok, receipt}),
    do: conn |> put_status(if(receipt["duplicate"], do: 200, else: 202)) |> json(receipt)

  defp respond(conn, {:error, %{code: code}}), do: failure(conn, code)

  defp failure(conn, code) do
    status =
      case code do
        :unauthorized -> 401
        :forbidden -> 403
        :not_found -> 404
        :conflict -> 409
        code when code in [:enqueue_failed, :persistence_unavailable, :secret_unavailable] -> 503
        _ -> 400
      end

    conn |> put_status(status) |> json(%{errors: %{code: code}})
  end
end
