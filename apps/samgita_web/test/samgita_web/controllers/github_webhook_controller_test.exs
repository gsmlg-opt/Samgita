defmodule SamgitaWeb.GitHubWebhookControllerTest do
  use SamgitaWeb.ConnCase, async: false
  import Ecto.Query
  alias Samgita.{GitHubFixtures, Repo}
  alias Samgita.Domain.{DomainEvent, GitHubDelivery}

  setup %{conn: conn} do
    previous = Map.new([:api_keys, :github_secrets], &{&1, Application.fetch_env(:samgita, &1)})
    Application.put_env(:samgita, :api_keys, ["github-web-operator"])
    Application.put_env(:samgita, :github_secrets, %{"test-hook-v1" => GitHubFixtures.secret()})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:samgita, key, value)
          :error -> Application.delete_env(:samgita, key)
        end
      end
    end)

    {project, connection, mapping} = GitHubFixtures.mapping_fixture()
    n = System.unique_integer([:positive])
    conn = %{conn | remote_ip: {127, 43, rem(div(n, 256), 256), rem(n, 256)}}
    {:ok, conn: conn, project: project, connection: connection, mapping: mapping}
  end

  test "the webhook requires its signature and accepts exact raw bytes without an operator key",
       %{
         conn: conn,
         connection: connection,
         project: project
       } do
    raw =
      " {\n  \"repository\": {\"id\":30}, \"installation\": {\"id\":20}," <>
        "\n  \"issue\": " <>
        Jason.encode!(GitHubFixtures.issue_fixture()) <> ", \"action\": \"opened\"\n}\n"

    {^raw, signature} = GitHubFixtures.signed(raw)
    delivery = Ecto.UUID.generate()
    response = conn |> headers(delivery, "issues", signature) |> post(path(connection), raw)
    receipt = json_response(response, 202)
    assert receipt["state"] == "accepted"
    assert receipt["event_count"] == 1
    assert get_req_header(response, "x-api-key") == []
    stored = Repo.get!(GitHubDelivery, receipt["id"])
    assert stored.body_digest == Base.encode16(:crypto.hash(:sha256, raw), case: :lower)
    event = Repo.one!(from e in DomainEvent, where: e.source_id == ^delivery)
    assert event.project_id == project["id"]
    assert event.source == "github"
    refute response.resp_body =~ GitHubFixtures.secret()
    refute response.resp_body =~ "Untrusted source text"

    changed = Jason.encode!(Jason.decode!(raw))
    assert changed != raw

    rejected =
      conn
      |> headers(Ecto.UUID.generate(), "issues", signature)
      |> post(path(connection), changed)

    assert json_response(rejected, 401)["errors"]["code"] == "unauthorized"
    assert delivery_count(connection) == 1
  end

  test "missing and duplicate event, delivery or signature headers fail before persistence", %{
    conn: conn,
    connection: connection
  } do
    {raw, signature} = GitHubFixtures.signed(GitHubFixtures.body_fixture())
    signed = headers(conn, Ecto.UUID.generate(), "issues", signature)

    for header <- ~w(x-github-event x-github-delivery x-hub-signature-256) do
      missing = signed |> delete_req_header(header) |> post(path(connection), raw)
      assert json_response(missing, 400)["errors"]["code"] == "invalid"
      [value] = get_req_header(signed, header)
      duplicate = %{signed | req_headers: [{header, value} | signed.req_headers]}
      assert duplicate |> post(path(connection), raw) |> json_response(400)
    end

    assert delivery_count(connection) == 0
  end

  test "operator credentials cannot substitute for a valid signature", %{
    conn: conn,
    connection: connection
  } do
    {raw, _} = GitHubFixtures.signed(GitHubFixtures.body_fixture())
    conn = put_req_header(conn, "x-api-key", "github-web-operator")

    for signature <- ["sha256=" <> String.duplicate("0", 64), "sha1=bad", ""] do
      response =
        conn |> headers(Ecto.UUID.generate(), "issues", signature) |> post(path(connection), raw)

      assert json_response(response, 401)["errors"]["code"] == "unauthorized"
    end

    assert delivery_count(connection) == 0
  end

  test "signature verification precedes JSON parsing and malformed nested shapes are rejected", %{
    conn: conn,
    connection: connection
  } do
    malformed = "{not JSON"
    {^malformed, signature} = GitHubFixtures.signed(malformed)

    assert conn
           |> headers(Ecto.UUID.generate(), "issues", signature)
           |> post(path(connection), malformed)
           |> json_response(400)

    assert conn
           |> headers(Ecto.UUID.generate(), "issues", "sha256=" <> String.duplicate("0", 64))
           |> post(path(connection), malformed)
           |> json_response(401)

    for body <- [
          [],
          %{},
          GitHubFixtures.body_fixture(%{"installation" => 1}),
          GitHubFixtures.body_fixture(%{"repository" => "invalid"}),
          GitHubFixtures.body_fixture(%{"issue" => []})
        ] do
      {raw, signature} = GitHubFixtures.signed(Jason.encode!(body))

      response =
        conn |> headers(Ecto.UUID.generate(), "issues", signature) |> post(path(connection), raw)

      assert response.status in [400, 403]
      assert json_response(response, response.status)["errors"]
    end

    assert delivery_count(connection) == 0
  end

  test "accepts at most one MiB of raw data and rejects excess bytes with 413", %{
    conn: conn,
    connection: connection
  } do
    empty = GitHubFixtures.body_fixture(%{"padding" => ""})
    padding = String.duplicate("x", 1_048_576 - byte_size(Jason.encode!(empty)))
    {raw, signature} = GitHubFixtures.signed(Map.put(empty, "padding", padding))
    assert byte_size(raw) == 1_048_576

    assert conn
           |> headers(Ecto.UUID.generate(), "issues", signature)
           |> post(path(connection), raw)
           |> json_response(202)

    {large, signature} = GitHubFixtures.signed(raw <> " ")

    response =
      conn |> headers(Ecto.UUID.generate(), "issues", signature) |> post(path(connection), large)

    assert json_response(response, 413)["errors"]["code"] == "payload_too_large"
    assert delivery_count(connection) == 1
  end

  test "replay, conflicting delivery IDs and unsupported events have durable outcomes", %{
    conn: conn,
    connection: connection
  } do
    {raw, signature} = GitHubFixtures.signed(GitHubFixtures.body_fixture())
    delivery = Ecto.UUID.generate()

    first =
      conn
      |> headers(delivery, "issues", signature)
      |> post(path(connection), raw)
      |> json_response(202)

    replay =
      conn
      |> headers(delivery, "issues", signature)
      |> post(path(connection), raw)
      |> json_response(200)

    assert replay["id"] == first["id"]
    assert replay["duplicate"] == true

    conflict =
      conn |> headers(delivery, "issue_comment", signature) |> post(path(connection), raw)

    assert json_response(conflict, 409)["errors"]["code"] == "conflict"
    unsupported_id = Ecto.UUID.generate()

    unsupported =
      conn
      |> headers(unsupported_id, "deployment", signature)
      |> post(path(connection), raw)
      |> json_response(202)

    assert unsupported["state"] == "unsupported"
    assert unsupported["reason"] == "unsupported_event"
    assert unsupported["event_count"] == 0

    assert conn
           |> headers(unsupported_id, "deployment", signature)
           |> post(path(connection), raw)
           |> json_response(200)

    assert delivery_count(connection) == 2
    actor = "github:" <> connection.id

    assert Repo.aggregate(
             from(e in DomainEvent, where: e.source == "github" and e.actor == ^actor),
             :count
           ) == 1
  end

  test "missing runtime secret is retryable without exposing the reference or value", %{
    conn: conn,
    connection: connection
  } do
    {raw, signature} = GitHubFixtures.signed(GitHubFixtures.body_fixture())
    Application.put_env(:samgita, :github_secrets, %{})

    response =
      conn |> headers(Ecto.UUID.generate(), "issues", signature) |> post(path(connection), raw)

    assert json_response(response, 503)["errors"]["code"] == "secret_unavailable"
    refute response.resp_body =~ "test-hook-v1"
    refute response.resp_body =~ GitHubFixtures.secret()
    assert delivery_count(connection) == 0
  end

  defp delivery_count(connection),
    do:
      Repo.aggregate(from(d in GitHubDelivery, where: d.connection_id == ^connection.id), :count)

  defp path(connection), do: "/api/github/webhooks/#{connection.id}"

  defp headers(conn, delivery, event, signature) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-delivery", delivery)
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-hub-signature-256", signature)
  end
end
