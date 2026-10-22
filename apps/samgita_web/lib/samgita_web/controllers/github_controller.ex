defmodule SamgitaWeb.GitHubController do
  use SamgitaWeb, :controller
  alias Samgita.GitHub

  def connections(conn, params),
    do: respond(conn, GitHub.connections(conn.assigns.samgita_principal, params))

  def configure(conn, params),
    do: respond(conn, GitHub.configure(conn.assigns.samgita_principal, params))

  def mappings(conn, %{"project_id" => project} = params),
    do: respond(conn, GitHub.mappings(conn.assigns.samgita_principal, project, params))

  def associate(conn, %{"project_id" => project} = params),
    do:
      respond(
        conn,
        GitHub.associate(conn.assigns.samgita_principal, project, params,
          client: Application.get_env(:samgita, :github_client, GitHub.Client)
        )
      )

  def update(conn, %{"project_id" => project, "id" => id} = params),
    do: respond(conn, GitHub.set_mapping(conn.assigns.samgita_principal, project, id, params))

  def facts(conn, %{"project_id" => project, "id" => id} = params),
    do: respond(conn, GitHub.facts(conn.assigns.samgita_principal, project, id, params))

  def observation(conn, %{"project_id" => project, "id" => id, "observation_id" => observation}),
    do:
      respond(conn, GitHub.observation(conn.assigns.samgita_principal, project, id, observation))

  def delivery(conn, %{"project_id" => project, "id" => id, "delivery_id" => delivery}),
    do: respond(conn, GitHub.delivery(conn.assigns.samgita_principal, project, id, delivery))

  def reconcile(conn, %{"project_id" => project, "id" => id} = params),
    do: respond(conn, GitHub.reconcile(conn.assigns.samgita_principal, project, id, params))

  defp respond(conn, {:ok, result}),
    do: conn |> put_resp_header("cache-control", "no-store") |> json(result)

  defp respond(conn, {:error, %GitHub.Failure{} = error}) do
    status =
      case error.class do
        :rate_limited -> 429
        :authentication -> 502
        :permission -> 403
        :retryable -> 503
        :permanent -> 422
      end

    conn =
      if error.retry_after,
        do: put_resp_header(conn, "retry-after", to_string(error.retry_after)),
        else: conn

    conn |> put_status(status) |> json(%{errors: %{code: error.code}})
  end

  defp respond(conn, error), do: SamgitaWeb.FallbackController.call(conn, error)
end
