defmodule Samgita.GitHub.PatActionsFunctionalTest do
  use Samgita.DataCase, async: false

  alias Samgita.Domain.{
    GitHubPatConnection,
    GitHubPatItem,
    GitHubPatRepositorySync,
    GitHubPatSelection
  }

  alias Samgita.GitHub.{Console, HTTP, PatActionClient, PatActions, PatCipher, PatSync}
  alias Samgita.Workers.GitHubPatActionWorker

  defmodule FixtureClient do
    def prepare(_token, repository, action, number, expected_sha) do
      state = if action == :reopen_issue, do: "closed", else: "open"
      kind = if action in [:close_issue, :reopen_issue], do: "issue", else: "pull_request"
      path = if kind == "issue", do: "issues", else: "pull"

      {:ok,
       %{
         repository: repository,
         action: action,
         number: number,
         expected_sha: expected_sha,
         item: %{
           kind: kind,
           number: number,
           title: "Item #{number}",
           state: state,
           author: "sample",
           updated_at: "2026-11-22T00:00:00Z",
           head_sha: nil,
           labels: [],
           issue_type: nil,
           url: "https://github.com/sample/one/#{path}/#{number}"
         }
       }}
    end

    def execute(_token, prepared) do
      Process.put(:action_writes, Process.get(:action_writes, 0) + 1)

      case Process.get(:action_outcome) do
        callback when is_function(callback, 0) ->
          callback.()

        {:error, _} = error ->
          error

        nil ->
          {:ok,
           %{
             prepared.item
             | state: if(prepared.action == :reopen_issue, do: "open", else: "closed")
           }}
      end
    end
  end

  defmodule FixtureHTTP do
    def request(:get, url, _headers, nil, _opts) do
      uri = URI.parse(url)
      raw = Process.get(:action_read_reply).(uri.path)
      {:ok, %{status: 200, headers: [], body: Jason.encode!(raw)}}
    end

    def pat_action(action, repository, number, _headers, body, _opts) do
      Process.put(:action_http_write, {action, repository, number, Jason.decode!(body)})

      case Process.get(:action_http_response) do
        :disconnect -> {:error, :timeout}
        raw -> {:ok, %{status: 200, headers: [], body: Jason.encode!(raw)}}
      end
    end
  end

  setup do
    for {key, value} <- [
          github_pat_action_client: FixtureClient,
          github_pat_key_base: String.duplicate("action-fixture", 4)
        ] do
      original = Application.fetch_env(:samgita, key)
      Application.put_env(:samgita, key, value)

      on_exit(fn ->
        case original do
          {:ok, previous} -> Application.put_env(:samgita, key, previous)
          :error -> Application.delete_env(:samgita, key)
        end
      end)
    end

    id = Ecto.UUID.generate()
    {:ok, ciphertext} = PatCipher.seal("synthetic-action-fixture", id, 5)

    row =
      Repo.insert!(%GitHubPatConnection{
        id: id,
        github_id: 5,
        login: "sample",
        ciphertext: ciphertext,
        credential_version: Ecto.UUID.generate(),
        version: Ecto.UUID.generate()
      })

    Repo.insert!(%GitHubPatSelection{
      connection_id: id,
      github_id: 41,
      owner_id: 7,
      owner: "sample",
      name: "one"
    })

    Repo.insert!(%GitHubPatItem{
      connection_id: id,
      credential_version: row.credential_version,
      repository_id: 41,
      kind: "issue",
      number: 1,
      title: "Issue 1",
      state: "open",
      author: "sample",
      labels: [],
      github_updated_at: ~U[2026-11-21 00:00:00.000000Z],
      url: "https://github.com/sample/one/issues/1"
    })

    Process.put(:action_writes, 0)
    Process.delete(:action_outcome)
    {:ok, row: row}
  end

  test "close requests coalesce and the successful action updates the item and replaces the read job",
       %{row: row} do
    assert :ok = PatSync.request_repository(row, 41)
    old_sync = Repo.get_by!(GitHubPatRepositorySync, connection_id: row.id, repository_id: 41)
    assert {:ok, id} = PatActions.request(row, 41, :close_issue, 1)
    assert {:ok, ^id} = PatActions.request(row, 41, :close_issue, 1)
    assert Process.get(:action_writes) == 0
    Console.subscribe_repository(41)
    Phoenix.PubSub.subscribe(Samgita.PubSub, "github:console")
    assert :ok = GitHubPatActionWorker.perform(Repo.get!(Styx.Job, id))
    assert item(row, 1).state == "closed"

    assert Repo.get_by!(GitHubPatRepositorySync, connection_id: row.id, repository_id: 41).job_id !=
             old_sync.job_id

    assert_receive {:github_pat_action, 41, ^id, :close_issue, 1, :ok}
    assert_receive :github_feed_changed
    assert Process.get(:action_writes) == 1
  end

  test "reopen can insert an issue absent from the local open snapshot", %{row: row} do
    assert item(row, 17) == nil
    assert {:ok, id} = PatActions.request(row, 41, :reopen_issue, 17)
    assert :ok = GitHubPatActionWorker.perform(Repo.get!(Styx.Job, id))
    assert %{kind: "issue", state: "open", number: 17} = item(row, 17)
  end

  test "repeated execution of a completed close job sends only one write", %{row: row} do
    {:ok, id} = PatActions.request(row, 41, :close_issue, 1)
    job = Repo.get!(Styx.Job, id)
    assert :ok = GitHubPatActionWorker.perform(job)
    assert :ok = GitHubPatActionWorker.perform(job)
    assert Process.get(:action_writes) == 1
    assert Repo.get!(Styx.Job, id).meta["pat_action_result"] == "ok"
  end

  test "a persisted send marker reconciles an interrupted action without repeating it", %{
    row: row
  } do
    {:ok, id} = PatActions.request(row, 41, :close_issue, 1)
    job = Repo.get!(Styx.Job, id)
    Repo.update!(change(job, meta: %{"pat_action_began" => true}))
    assert {:cancel, :ambiguous} = GitHubPatActionWorker.perform(job)
    assert Process.get(:action_writes) == 0
    assert item(row, 1).state == "open"
    assert Repo.get_by!(GitHubPatRepositorySync, connection_id: row.id, repository_id: 41).job_id
  end

  test "a disconnected write retains the local item and queues a fresh read", %{row: row} do
    {:ok, id} = PatActions.request(row, 41, :close_issue, 1)
    Process.put(:action_outcome, {:error, :ambiguous})
    job = Repo.get!(Styx.Job, id)
    assert {:cancel, :ambiguous} = GitHubPatActionWorker.perform(job)
    assert item(row, 1).state == "open"
    assert Process.get(:action_writes) == 1
    assert {:cancel, :ambiguous} = GitHubPatActionWorker.perform(job)
    assert Process.get(:action_writes) == 1
  end

  test "a duplicate while the first action is sending cannot send a second write", %{row: row} do
    {:ok, id} = PatActions.request(row, 41, :close_issue, 1)
    job = Repo.get!(Styx.Job, id)

    Process.put(:action_outcome, fn ->
      assert Repo.get!(Styx.Job, id).meta["pat_action_began"]
      assert {:cancel, :ambiguous} = GitHubPatActionWorker.perform(job)

      {:ok,
       %{
         kind: "issue",
         number: 1,
         title: "Issue 1",
         state: "closed",
         author: "sample",
         updated_at: "2026-11-22T00:00:00Z",
         head_sha: nil,
         issue_type: nil,
         labels: [],
         url: "https://github.com/sample/one/issues/1"
       }}
    end)

    assert :ok = GitHubPatActionWorker.perform(job)
    assert Process.get(:action_writes) == 1
    assert item(row, 1).state == "closed"
    assert Repo.get!(Styx.Job, id).meta["pat_action_result"] == "ok"
  end

  test "the close client confirms the issue kind and serializes only its state change" do
    Process.put(:action_read_reply, fn
      "/repositories/41" -> raw_repository()
      "/repos/sample/one/issues/1" -> raw_issue(1, "open")
    end)

    Process.put(:action_http_response, raw_issue(1, "closed"))

    assert {:ok, prepared} =
             PatActionClient.prepare(
               "synthetic-action-fixture",
               repository(),
               :close_issue,
               1,
               nil,
               opts()
             )

    assert {:ok, %{state: "closed"}} =
             PatActionClient.execute("synthetic-action-fixture", prepared, opts())

    assert {:close_issue, %{id: 41}, 1, %{"state" => "closed"}} = Process.get(:action_http_write)
  end

  test "the reopen client retrieves an uncached issue number and sends open" do
    Process.put(:action_read_reply, fn
      "/repositories/41" -> raw_repository()
      "/repos/sample/one/issues/17" -> raw_issue(17, "closed")
    end)

    Process.put(:action_http_response, raw_issue(17, "open"))

    assert {:ok, prepared} =
             PatActionClient.prepare(
               "synthetic-action-fixture",
               repository(),
               :reopen_issue,
               17,
               nil,
               opts()
             )

    assert {:ok, %{state: "open", number: 17}} =
             PatActionClient.execute("synthetic-action-fixture", prepared, opts())

    assert {:reopen_issue, _, 17, %{"state" => "open"}} = Process.get(:action_http_write)
  end

  test "confirmed state changes persist, replace and remove label colors with names", %{row: row} do
    for {action, raw_labels, names, colors} <- [
          {:close_issue,
           [
             %{"name" => "priority", "color" => "D73A4A"},
             %{"name" => "backend", "color" => "0075CA"}
           ], ["priority", "backend"], %{"priority" => "d73a4a", "backend" => "0075ca"}},
          {:reopen_issue, [%{"name" => "priority", "color" => "00FF7F"}], ["priority"],
           %{"priority" => "00ff7f"}},
          {:close_issue, [], [], %{}},
          {:reopen_issue, [%{"name" => "neutral", "color" => "invalid"}, "legacy"],
           ["neutral", "legacy"], %{}}
        ] do
      before_state = if action == :reopen_issue, do: "closed", else: "open"
      after_state = if action == :reopen_issue, do: "open", else: "closed"

      Process.put(:action_read_reply, fn
        "/repositories/41" -> raw_repository()
        "/repos/sample/one/issues/1" -> raw_issue(1, before_state)
      end)

      Process.put(:action_http_response, Map.put(raw_issue(1, after_state), "labels", raw_labels))

      Process.put(:action_outcome, fn ->
        {:ok, prepared} =
          PatActionClient.prepare(
            "synthetic-action-fixture",
            repository(),
            action,
            1,
            nil,
            opts()
          )

        PatActionClient.execute("synthetic-action-fixture", prepared, opts())
      end)

      assert {:ok, id} = PatActions.request(row, 41, action, 1)
      job = Repo.get!(Styx.Job, id)
      assert :ok = GitHubPatActionWorker.perform(job)
      assert item(row, 1).labels == names
      assert item(row, 1).label_colors == colors
      Repo.update!(change(job, state: "completed"))
    end
  end

  test "a failed transport leaves the mutation result ambiguous" do
    Process.put(:action_read_reply, fn
      "/repositories/41" -> raw_repository()
      "/repos/sample/one/issues/1" -> raw_issue(1, "open")
    end)

    Process.put(:action_http_response, :disconnect)

    assert {:ok, prepared} =
             PatActionClient.prepare(
               "synthetic-action-fixture",
               repository(),
               :close_issue,
               1,
               nil,
               opts()
             )

    assert {:error, :ambiguous} =
             PatActionClient.execute("synthetic-action-fixture", prepared, opts())
  end

  test "merge and rebase use the visible head SHA and their explicit merge method" do
    sha = String.duplicate("a", 40)

    Process.put(:action_read_reply, fn
      "/repositories/41" -> raw_repository()
      "/repos/sample/one/pulls/2" -> raw_pull(2, "open", sha)
    end)

    Process.put(:action_http_response, %{"merged" => true})

    for {action, method} <- [{:merge_pull, "merge"}, {:rebase_pull, "rebase"}] do
      assert {:ok, prepared} =
               PatActionClient.prepare(
                 "synthetic-action-fixture",
                 repository(),
                 action,
                 2,
                 sha,
                 opts()
               )

      assert {:ok, %{state: "merged"}} =
               PatActionClient.execute("synthetic-action-fixture", prepared, opts())

      assert {^action, _, 2, %{"sha" => ^sha, "merge_method" => ^method}} =
               Process.get(:action_http_write)
    end
  end

  test "a merge response with merged false remains a failed merge" do
    sha = String.duplicate("b", 40)

    Process.put(:action_read_reply, fn
      "/repositories/41" -> raw_repository()
      "/repos/sample/one/pulls/2" -> raw_pull(2, "open", sha)
    end)

    Process.put(:action_http_response, %{
      "merged" => false,
      "message" => "Pull request is not mergeable"
    })

    for action <- [:merge_pull, :rebase_pull] do
      assert {:ok, prepared} =
               PatActionClient.prepare(
                 "synthetic-action-fixture",
                 repository(),
                 action,
                 2,
                 sha,
                 opts()
               )

      assert {:error, :merge_blocked} =
               PatActionClient.execute("synthetic-action-fixture", prepared, opts())
    end
  end

  test "closing an already merged PR preserves its terminal state without another write" do
    Process.delete(:action_http_write)

    Process.put(:action_read_reply, fn
      "/repositories/41" ->
        raw_repository()

      "/repos/sample/one/pulls/2" ->
        Map.put(
          raw_pull(2, "closed", String.duplicate("a", 40)),
          "merged_at",
          "2026-11-22T00:00:00Z"
        )
    end)

    assert {:ok, prepared} =
             PatActionClient.prepare(
               "synthetic-action-fixture",
               repository(),
               :close_pull,
               2,
               nil,
               opts()
             )

    assert {:ok, %{state: "merged"}} =
             PatActionClient.execute("synthetic-action-fixture", prepared, opts())

    assert Process.get(:action_http_write) == nil
  end

  test "a late close response preserves a PR already recorded as merged", %{row: row} do
    pull =
      Repo.insert!(%GitHubPatItem{
        connection_id: row.id,
        credential_version: row.credential_version,
        repository_id: 41,
        kind: "pull_request",
        number: 2,
        title: "PR 2",
        state: "open",
        author: "sample",
        labels: [],
        head_sha: String.duplicate("a", 40),
        github_updated_at: ~U[2026-11-21 00:00:00.000000Z],
        url: "https://github.com/sample/one/pull/2"
      })

    {:ok, id} = PatActions.request(row, 41, :close_pull, 2)

    Process.put(:action_outcome, fn ->
      Repo.update!(change(pull, state: "merged"))

      {:ok,
       %{
         kind: "pull_request",
         number: 2,
         title: "PR 2",
         state: "closed",
         author: "sample",
         updated_at: "2026-11-22T00:00:00Z",
         head_sha: pull.head_sha,
         labels: [],
         issue_type: nil,
         url: "https://github.com/sample/one/pull/2"
       }}
    end)

    assert :ok = GitHubPatActionWorker.perform(Repo.get!(Styx.Job, id))

    assert Repo.get_by!(GitHubPatItem,
             connection_id: row.id,
             repository_id: 41,
             kind: "pull_request",
             number: 2
           ).state == "merged"
  end

  test "older close and reopen responses preserve newer Issue state and metadata", %{row: row} do
    for {action, newer_state, response_state} <- [
          {:close_issue, "open", "closed"},
          {:reopen_issue, "closed", "open"}
        ] do
      {:ok, id} = PatActions.request(row, 41, action, 1)
      newer_date = ~U[2026-11-23 00:00:00.000000Z]

      Process.put(:action_outcome, fn ->
        Repo.update!(
          change(item(row, 1),
            state: newer_state,
            title: "Newer observation",
            labels: ["current"],
            label_colors: %{"current" => "123abc"},
            github_updated_at: newer_date
          )
        )

        {:ok,
         %{
           kind: "issue",
           number: 1,
           title: "Earlier response",
           state: response_state,
           author: "sample",
           updated_at: "2026-11-22T00:00:00Z",
           head_sha: nil,
           issue_type: nil,
           labels: [],
           url: "https://github.com/sample/one/issues/1"
         }}
      end)

      assert :ok = GitHubPatActionWorker.perform(Repo.get!(Styx.Job, id))
      current = item(row, 1)
      assert current.state == newer_state
      assert current.github_updated_at == newer_date
      assert current.title == "Newer observation"
      assert current.labels == ["current"]
      assert current.label_colors == %{"current" => "123abc"}
    end
  end

  test "the real PAT transport sends a PATCH issue close with its JSON body" do
    {destination, server} = wire_server()

    assert {:ok, %{status: 200}} =
             HTTP.pat_action(:close_issue, repository(), 1, [], Jason.encode!(%{state: "closed"}),
               destination: destination
             )

    {line, body} = Task.await(server)
    assert line == "PATCH /repos/sample/one/issues/1 HTTP/1.1"
    assert Jason.decode!(body) == %{"state" => "closed"}
  end

  test "the real PAT transport sends PUT rebase with the expected SHA" do
    {destination, server} = wire_server()
    sha = String.duplicate("c", 40)

    assert {:ok, %{status: 200}} =
             HTTP.pat_action(
               :rebase_pull,
               repository(),
               2,
               [],
               Jason.encode!(%{sha: sha, merge_method: "rebase"}),
               destination: destination
             )

    {line, body} = Task.await(server)
    assert line == "PUT /repos/sample/one/pulls/2/merge HTTP/1.1"
    assert Jason.decode!(body) == %{"sha" => sha, "merge_method" => "rebase"}
  end

  defp wire_server do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {address, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)

        try do
          request = wire_request(socket, "")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: close\r\n\r\n{}"
            )

          request
        after
          :gen_tcp.close(socket)
          :gen_tcp.close(listener)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server.pid), do: Task.shutdown(server, :brutal_kill)
    end)

    {%{api_url: base, uri: URI.parse(base), address: address}, server}
  end

  defp wire_request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [head, body] ->
        [line | headers] = String.split(head, "\r\n")

        size =
          Enum.find_value(headers, fn header ->
            case String.split(header, ":", parts: 2) do
              [name, value] ->
                if String.downcase(name) == "content-length",
                  do: value |> String.trim() |> String.to_integer()

              _ ->
                nil
            end
          end)

        assert is_integer(size)
        {line, wire_body(socket, body, size)}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
        wire_request(socket, buffer <> bytes)
    end
  end

  defp wire_body(_socket, body, size) when byte_size(body) >= size, do: binary_part(body, 0, size)

  defp wire_body(socket, body, size) do
    {:ok, bytes} = :gen_tcp.recv(socket, 0, 5_000)
    wire_body(socket, body <> bytes, size)
  end

  defp item(row, number),
    do:
      Repo.get_by(GitHubPatItem,
        connection_id: row.id,
        repository_id: 41,
        kind: "issue",
        number: number
      )

  defp repository,
    do: %{id: 41, owner_id: 7, owner: "sample", name: "one", required_owner_id: nil}

  defp raw_repository,
    do: %{"id" => 41, "owner" => %{"id" => 7, "login" => "sample"}, "name" => "one"}

  defp raw_issue(number, state),
    do: %{
      "number" => number,
      "title" => "Issue #{number}",
      "state" => state,
      "user" => %{"login" => "sample"},
      "updated_at" => "2026-11-22T00:00:00Z",
      "labels" => []
    }

  defp raw_pull(number, state, sha),
    do:
      raw_issue(number, state)
      |> Map.put("base", %{"repo" => %{"id" => 41}})
      |> Map.put("head", %{"sha" => sha})

  defp opts,
    do: [
      http: FixtureHTTP,
      destination: %{api_url: "https://api.github.com", uri: URI.parse("https://api.github.com")},
      now: 1_800_000_000
    ]
end
