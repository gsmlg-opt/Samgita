defmodule Samgita.Provider.HealthChecker do
  @moduledoc """
  GenServer that periodically health-checks configured Synapsis endpoints.
  Stores health status in ETS and publishes changes via PubSub.
  """

  use GenServer
  require Logger

  @table_name :samgita_provider_health
  @check_interval_ms 30_000
  @health_timeout_ms 10_000

  # Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Check if a specific endpoint is healthy."
  def healthy?(endpoint_url) do
    case :ets.lookup(@table_name, endpoint_url) do
      [{_, :healthy, _}] -> true
      _ -> false
    end
  end

  @doc "Get all healthy endpoints from a project's synapsis_endpoints list."
  def healthy_endpoints(project) do
    (project.synapsis_endpoints || [])
    |> Enum.filter(fn ep -> healthy?(ep["url"] || ep[:url]) end)
  end

  @doc "Get all tracked endpoint statuses."
  def all_statuses do
    :ets.tab2list(@table_name)
    |> Enum.map(fn {url, status, checked_at} ->
      %{url: url, status: status, checked_at: checked_at}
    end)
  end

  @doc "Register an endpoint for health checking."
  def register_endpoint(endpoint_url) do
    GenServer.cast(__MODULE__, {:register, endpoint_url})
  end

  @doc "Trigger an immediate health check for all endpoints."
  def check_now do
    GenServer.cast(__MODULE__, :check_now)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    schedule_check()
    {:ok, %{table: table, endpoints: MapSet.new()}}
  end

  @impl true
  def handle_cast({:register, endpoint_url}, state) do
    {:noreply, %{state | endpoints: MapSet.put(state.endpoints, endpoint_url)}}
  end

  @impl true
  def handle_cast(:check_now, state) do
    check_all_endpoints(state.endpoints)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_endpoints, state) do
    # Also discover endpoints from all projects
    all_endpoints = discover_endpoints(state.endpoints)
    check_all_endpoints(all_endpoints)
    schedule_check()
    {:noreply, %{state | endpoints: all_endpoints}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp schedule_check do
    Process.send_after(self(), :check_endpoints, @check_interval_ms)
  end

  defp discover_endpoints(known) do
    # Query all projects with synapsis_endpoints
    try do
      import Ecto.Query

      Samgita.Repo.all(
        from p in Samgita.Domain.Project,
          where: not is_nil(p.synapsis_endpoints),
          select: p.synapsis_endpoints
      )
      |> List.flatten()
      |> Enum.map(fn ep -> ep["url"] || ep[:url] end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()
      |> MapSet.union(known)
    rescue
      _ -> known
    end
  end

  defp check_all_endpoints(endpoints) do
    endpoints
    |> Enum.each(fn url ->
      Task.start(fn -> check_endpoint(url) end)
    end)
  end

  defp check_endpoint(url) do
    health_url = url <> "/health"

    old_status =
      case :ets.lookup(@table_name, url) do
        [{_, status, _}] -> status
        [] -> nil
      end

    new_status =
      case do_health_check(health_url) do
        :ok -> :healthy
        {:error, _} -> :unhealthy
      end

    now = DateTime.utc_now()
    :ets.insert(@table_name, {url, new_status, now})

    # Broadcast status change
    if old_status != new_status do
      Phoenix.PubSub.broadcast(
        Samgita.PubSub,
        "samgita:provider:health",
        {:health_changed, url, new_status}
      )

      Logger.info("[HealthChecker] #{url}: #{old_status || :unknown} -> #{new_status}")
    end
  end

  defp do_health_check(url) do
    request = Finch.build(:get, url)

    case Finch.request(request, finch_name(), receive_timeout: @health_timeout_ms) do
      {:ok, %Finch.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Finch.Response{status: status}} -> {:error, "HTTP #{status}"}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp finch_name do
    Application.get_env(:samgita_provider, :finch_name, Samgita.Finch)
  end
end
