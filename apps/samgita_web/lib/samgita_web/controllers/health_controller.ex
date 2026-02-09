defmodule SamgitaWeb.HealthController do
  use SamgitaWeb, :controller

  def index(conn, _params) do
    checks = %{
      samgita_repo: check_repo(Samgita.Repo),
      samgita_memory_repo: check_repo(SamgitaMemory.Repo)
    }

    all_healthy = Enum.all?(checks, fn {_, v} -> v == :ok end)
    status = if all_healthy, do: :ok, else: :service_unavailable

    json(conn |> put_status(status), %{
      status: if(all_healthy, do: "healthy", else: "degraded"),
      version: Application.spec(:samgita, :vsn) |> to_string(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      uptime_seconds: uptime_seconds(),
      checks: Map.new(checks, fn {k, v} -> {k, to_string(v)} end)
    })
  end

  defp check_repo(repo) do
    repo.query!("SELECT 1")
    :ok
  rescue
    _ -> :error
  end

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
