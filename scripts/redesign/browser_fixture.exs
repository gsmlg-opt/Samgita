# Explicit local qualification driver, never a platform worker or provider integration.
# Run with MIX_ENV=test mix run --no-start on a fresh samgita_redesign_*_test DB.
if Mix.env() != :test ||
     !Regex.match?(
       ~r/^samgita_redesign_[a-z0-9_]+_test$/,
       System.fetch_env!("SAMGITA_TEST_DATABASE")
     ) do
  raise "browser fixture requires MIX_ENV=test and an explicit isolated scratch database"
end

defmodule Samgita.BrowserFixture do
  alias Samgita.{Agents, EventDelivery, Principal, Repo}
  alias Samgita.Domain.EventDelivery, as: Delivery
  import Ecto.Query
  @token "browser-only-machine-credential-0001"
  @service "browser-only-service-credential"

  def boot do
    port = String.to_integer(System.get_env("PORT", "3119"))
    endpoint = Application.fetch_env!(:samgita_web, SamgitaWeb.Endpoint)
    repo = Application.fetch_env!(:samgita, Repo)
    # A long-lived browser uses ordinary connections, not ExUnit's timed owners.
    Application.put_env(:samgita, Repo, Keyword.put(repo, :pool, DBConnection.ConnectionPool))

    Application.put_env(
      :samgita_web,
      SamgitaWeb.Endpoint,
      Keyword.merge(endpoint,
        server: true,
        http: [ip: {127, 0, 0, 1}, port: port],
        check_origin: ["//127.0.0.1:#{port}", "//localhost:#{port}"]
      )
    )

    Application.put_env(:samgita, :api_keys, ["browser-only-operator-key"])
    Application.put_env(:samgita, :event_credentials, %{"browser-service-v1" => @service})
    {:ok, _} = Application.ensure_all_started(:samgita_web)
    {:ok, _} = Application.ensure_all_started(:inets)
    Logger.configure(level: :warning)
    Samgita.DomainFixtures.activate_fixture()
    path = System.fetch_env!("SAMGITA_FAKE_JOURNAL")

    {:ok, fake} =
      SamgitaWeb.FakeAgent.start_link(
        journal: path,
        token: @service,
        port: String.to_integer(System.get_env("SAMGITA_FAKE_PORT", "0"))
      )

    url = SamgitaWeb.FakeAgent.url(fake)

    IO.puts(
      Jason.encode!(%{
        endpoint: "http://127.0.0.1:#{port}",
        agent_endpoint: url,
        credential_reference: "browser-service-v1",
        driver: "stdin JSON: action=work, project_id, agent_id"
      })
    )

    %{fake: fake, url: url, base: "http://127.0.0.1:#{port}"}
  end

  def work(%{"project_id" => project_id, "agent_id" => agent_id} = attrs, state) do
    {:ok, agent} = Agents.get(Principal.operator(), agent_id)

    if agent["endpoint_metadata"]["url"] != state.url,
      do: raise("registered endpoint must match this explicitly started fake")

    Application.put_env(:samgita, :event_destinations, %{
      agent_id => %{url: state.url, addresses: [{127, 0, 0, 1}], allow_insecure: true}
    })

    deliveries =
      Repo.all(
        from(d in Delivery,
          where: d.project_id == ^project_id and d.agent_id == ^agent_id and d.state == "pending"
        )
      )

    if deliveries == [], do: raise("emit an explicitly routed event before the fake action")

    Enum.each(deliveries, fn d -> {:ok, _} = EventDelivery.dispatch(d.id) end)
    connection = api(state, :post, "/api/agent/connect", nil, command())
    api_base = "/api/agent/projects/#{project_id}"

    Enum.each(deliveries, fn d ->
      current = Repo.get!(Delivery, d.id)

      api(
        state,
        :post,
        api_base <> "/deliveries/#{d.id}/report",
        connection["id"],
        command(%{
          "expected_version" => current.version,
          "operation_id" => d.operation_id,
          "fence" => current.fence,
          "decision_id" => Ecto.UUID.generate(),
          "processing_status" => "completed",
          "result" => %{"summary" => "Fake Agent chose bounded evidence collection"}
        })
      )
    end)

    task =
      api(
        state,
        :post,
        api_base <> "/tasks",
        connection["id"],
        command(%{"title" => "Fake Agent evidence for operator review"})
      )

    child =
      api(
        state,
        :post,
        api_base <> "/tasks",
        connection["id"],
        command(%{"title" => "Delegated fake evidence", "parent_task_id" => task["id"]})
      )

    session =
      api(
        state,
        :post,
        api_base <> "/sessions",
        connection["id"],
        command(%{"external_id" => "browser-" <> task["id"]})
      )

    attempt =
      api(
        state,
        :post,
        api_base <> "/tasks/#{task["id"]}/claim",
        connection["id"],
        command(%{"expected_version" => task["version"], "session_id" => session["id"]})
      )

    proof =
      api(state, :get, api_base <> "/attempts/#{attempt["id"]}/proof", connection["id"], nil)[
        "proof"
      ]

    :started = SamgitaWeb.FakeAgent.start_once(state.fake, attempt["id"])

    started =
      api(
        state,
        :post,
        api_base <> "/attempts/#{attempt["id"]}/start",
        connection["id"],
        command(%{"expected_version" => attempt["version"], "proof" => proof})
      )

    progressed =
      api(
        state,
        :post,
        api_base <> "/attempts/#{attempt["id"]}/progress",
        connection["id"],
        command(%{
          "expected_version" => started["version"],
          "proof" => proof,
          "payload" => %{"summary" => "Fake execution recorded a deterministic report"}
        })
      )

    current = api(state, :get, api_base <> "/tasks/#{task["id"]}", connection["id"], nil)

    unless attrs["leave_running"] do
      api(
        state,
        :post,
        api_base <> "/tasks/#{task["id"]}/artifacts",
        connection["id"],
        command(%{
          "expected_version" => current["version"],
          "attempt_id" => attempt["id"],
          "kind" => "qualification-report",
          "locator" => "artifact:fake-browser/report"
        })
      )

      api(
        state,
        :post,
        api_base <> "/attempts/#{attempt["id"]}/report",
        connection["id"],
        command(%{
          "expected_version" => progressed["version"],
          "proof" => proof,
          "outcome" => "succeeded",
          "effects_resolved" => true,
          "result" => %{"summary" => "Simulation finished, awaiting operator review"}
        })
      )
    end

    %{
      "task_id" => task["id"],
      "child_task_id" => child["id"],
      "task_url" => state.base <> "/projects/#{project_id}/tasks/#{task["id"]}",
      "deliveries" => length(deliveries),
      "state" => if(attrs["leave_running"], do: "in_progress", else: "awaiting_review")
    }
  end

  defp command(attrs \\ %{}), do: Map.put(attrs, "command_id", Ecto.UUID.generate())

  defp api(state, method, path, connection, body) do
    headers = [{~c"authorization", String.to_charlist("Bearer " <> @token)}]

    headers =
      if connection,
        do: [{~c"x-agent-connection", String.to_charlist(connection)} | headers],
        else: headers

    url = String.to_charlist(state.base <> path)

    request =
      if body, do: {url, headers, ~c"application/json", Jason.encode!(body)}, else: {url, headers}

    {:ok, {{_, status, _}, _, response}} =
      :httpc.request(method, request, [timeout: 5000], body_format: :binary)

    if status not in [200, 201], do: raise("fake callback rejected: #{status} #{response}")
    Jason.decode!(response)["data"]
  end
end

state = Samgita.BrowserFixture.boot()

Enum.each(IO.stream(:stdio, :line), fn line ->
  try do
    case Jason.decode!(String.trim(line)) do
      %{"action" => "work"} = attrs ->
        IO.puts(Jason.encode!(Samgita.BrowserFixture.work(attrs, state)))
    end
  rescue
    _ -> IO.puts("{\"error\":\"fake action rejected; inspect persisted state before retry\"}")
  end
end)
