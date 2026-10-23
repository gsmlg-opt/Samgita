defmodule SamgitaWeb.TelemetryConfidentialityTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Samgita.DomainFixtures
  import ExUnit.CaptureLog

  test "credential canary stays out of logs and metric projections but raw upstream metadata remains exposed",
       %{conn: conn} do
    owner = self()
    handler = {__MODULE__, make_ref()}

    events = [
      [:phoenix, :live_view, :handle_event, :start],
      [:phoenix, :live_view, :handle_event, :stop],
      [:samgita, :repo, :query]
    ]

    :ok = :telemetry.attach_many(handler, events, &__MODULE__.capture/4, owner)
    on_exit(fn -> :telemetry.detach(handler) end)
    previous_level = Logger.level()
    on_exit(fn -> Logger.configure(level: previous_level) end)
    agent = agent_fixture()
    canary = "synthetic-telemetry-canary-#{Ecto.UUID.generate()}"
    {:ok, view, _} = live(conn, ~p"/agents/#{agent["id"]}")

    params = %{
      "credential" => canary,
      "reference" => "canary-v1",
      "expires_at" => "",
      "command_id" => input(view, "credential[command_id]"),
      "expected_version" => input(view, "credential[expected_version]")
    }

    logs =
      capture_log([level: :debug], fn ->
        Logger.configure(level: :debug)
        html = view |> form("#agent-credential", credential: params) |> render_submit()
        refute html =~ canary
        Logger.configure(level: previous_level)
      end)

    refute logs =~ canary

    observations = observations([])
    raw_events = Enum.filter(observations, fn {event, _, _} -> event in Enum.take(events, 2) end)
    assert length(raw_events) == 2
    # This assertion documents the blocking upstream exposure, not a passing A11
    # confidentiality gate. In-process raw handlers see parameters before our code.
    assert Enum.all?(raw_events, fn {_, _, metadata} ->
             get_in(metadata, [:params, "credential", "credential"]) == canary
           end)

    projections =
      for {event, measurements, metadata} <- observations,
          metric <- SamgitaWeb.Telemetry.metrics(),
          metric.event_name == event do
        value = measurement(metric.measurement, measurements, metadata)

        %{
          name: metric.name,
          value: value,
          tags: Map.take(metric.tag_values.(metadata), metric.tags)
        }
      end

    refute projections == []
    refute inspect(projections, limit: :infinity) =~ canary
  end

  def capture(event, measurements, metadata, owner),
    do: send(owner, {:canary_observation, event, measurements, metadata})

  defp measurement(fun, measurements, metadata) when is_function(fun, 2),
    do: fun.(measurements, metadata)

  defp measurement(fun, measurements, _) when is_function(fun, 1), do: fun.(measurements)
  defp measurement(key, measurements, _), do: measurements[key]

  defp observations(acc) do
    receive do
      {:canary_observation, event, measurements, metadata} ->
        observations([{event, measurements, metadata} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp input(view, name) do
    view
    |> element("input[name='#{name}']")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("value")
    |> hd()
  end
end
