defmodule Samgita.GitHub.PatReaderFunctionalTest do
  use ExUnit.Case, async: true
  alias Samgita.GitHub.PatClient

  defmodule FixtureHTTP do
    def request(:get, url, _headers, nil, _opts) do
      uri = URI.parse(url)
      params = URI.decode_query(uri.query || "")

      Process.put(:pat_reader_requests, [
        {uri.path, params} | Process.get(:pat_reader_requests, [])
      ])

      reply = Process.get(:pat_reader_fixture).(uri.path, params)

      case reply do
        {:status, status} ->
          {:ok, %{status: status, headers: [], body: "{}"}}

        {:rate_limit, retry} ->
          {:ok, %{status: 429, headers: [{"retry-after", to_string(retry)}], body: "{}"}}

        {items, :next} ->
          next = Map.put(params, "page", to_string(String.to_integer(params["page"]) + 1))
          link = "<https://api.github.com#{uri.path}?#{URI.encode_query(next)}>; rel=\"next\""
          {:ok, %{status: 200, headers: [{"link", link}], body: Jason.encode!(items)}}

        {items, {:next_path, path}} ->
          next = Map.put(params, "page", to_string(String.to_integer(params["page"]) + 1))
          link = "<https://api.github.com#{path}?#{URI.encode_query(next)}>; rel=\"next\""
          {:ok, %{status: 200, headers: [{"link", link}], body: Jason.encode!(items)}}

        {:link, items, link} ->
          {:ok, %{status: 200, headers: [{"link", link}], body: Jason.encode!(items)}}

        body ->
          {:ok, %{status: 200, headers: [], body: Jason.encode!(body)}}
      end
    end
  end

  setup do
    Process.put(:pat_reader_requests, [])

    {:ok,
     opts: [
       http: FixtureHTTP,
       destination: %{api_url: "https://api.github.com", uri: URI.parse("https://api.github.com")},
       now: 1_800_000_000
     ]}
  end

  test "catalog discovers personal and organization repositories across pages", %{opts: opts} do
    fixture(fn
      "/user", _ ->
        owner(1, "alice")

      "/user/memberships/orgs", %{"page" => "1", "state" => "active"} ->
        {[%{"organization" => owner(2, "studio")}], :next}

      "/user/memberships/orgs", %{"page" => "2"} ->
        [%{"organization" => owner(3, "empty-org")}]

      "/user/repos", %{"page" => "1"} ->
        {[repository(12, "studio", "beta", 2)], :next}

      "/user/repos", %{"page" => "2"} ->
        [repository(11, "alice", "personal", 1), repository(13, "collaborator", "shared", 4)]
    end)

    assert {:ok, catalog} = PatClient.catalog("synthetic-pat", opts)

    assert Enum.map(catalog.owners, & &1.login) == [
             "alice",
             "collaborator",
             "empty-org",
             "studio"
           ]

    assert Enum.map(catalog.repositories, & &1.id) == [11, 13, 12]
    assert [%{owner_id: 1, owner: "alice", name: "personal"} | _] = catalog.repositories
  end

  test "feed merges repository pages with stable global ordering and no duplicated rows", %{
    opts: opts
  } do
    fixture(fn
      "/repositories/11", _ -> repository(11, "studio", "first")
      "/repositories/12", _ -> repository(12, "studio", "second")
      "/repos/studio/first/issues", _ -> Enum.map(1..35, &issue(&1, &1 * 2))
      "/repos/studio/second/issues", _ -> Enum.map(1..35, &issue(&1, &1 * 2 - 1))
    end)

    repositories = [%{id: 11}, %{id: 12}]
    filters = %{kind: :issues, state: :open}
    assert {:ok, first} = PatClient.feed("synthetic-pat", repositories, filters, nil, opts)

    assert {:ok, second} =
             PatClient.feed("synthetic-pat", repositories, filters, first.cursor, opts)

    assert {:ok, third} =
             PatClient.feed("synthetic-pat", repositories, filters, second.cursor, opts)

    assert Enum.map([first, second, third], &length(&1.items)) == [30, 30, 10]
    assert third.cursor == nil
    all = first.items ++ second.items ++ third.items
    assert length(Enum.uniq_by(all, &{&1.repository_id, &1.number})) == 70
    assert Enum.map(all, & &1.updated_at) == Enum.sort(Enum.map(all, & &1.updated_at), :desc)
    assert Enum.all?(all, &String.starts_with?(&1.url, "https://github.com/studio/"))
  end

  test "GitHub after cursors survive numeric links, subsequent cursor changes and numbered fallback",
       %{opts: opts} do
    first_cursor = "Y3Vyc29yOnYyOpLPAAABoTUyZtDPAAAAAVrVli4="
    second_cursor = "Y3Vyc29yOnYyOpLPAAABoTUzZtDPAAAAAVrVli4+/="

    for operation <- [:feed, :sync] do
      Process.put(:pat_reader_requests, [])

      order =
        if operation == :feed,
          do: "sort=updated&direction=desc",
          else: "sort=created&direction=asc"

      base = "https://api.github.com/repositories/16072585/issues?state=open&#{order}&per_page=50"

      fixture(fn
        "/repositories/16072585", _ ->
          repository(16_072_585, "phoenixframework", "phoenix")

        "/repos/phoenixframework/phoenix/issues", %{"page" => "1"} ->
          {:link, [issue(1, 4)],
           "<#{base}&page=2&after=Y3Vyc29yOnYyOpLPAAABoTUyZtDPAAAAAVrVli4%3D>; rel=\"next\""}

        "/repos/phoenixframework/phoenix/issues", %{"page" => "2", "after" => ^first_cursor} ->
          {:link, [issue(2, 3)],
           "<#{base}&page=3&after=#{URI.encode_www_form(second_cursor)}>; rel=\"next\""}

        "/repos/phoenixframework/phoenix/issues", %{"page" => "3", "after" => ^second_cursor} ->
          {:link, [issue(3, 2)], "<#{base}&page=4>; rel=\"next\""}

        "/repos/phoenixframework/phoenix/issues", %{"page" => "4"} = params ->
          refute Map.has_key?(params, "after")
          [issue(4, 1)]

        "/repos/phoenixframework/phoenix/pulls", _ ->
          []
      end)

      result =
        case operation do
          :feed ->
            PatClient.feed(
              "synthetic-pat",
              [%{id: 16_072_585}],
              %{kind: :issues, state: :all},
              nil,
              opts
            )

          :sync ->
            PatClient.sync_repository("synthetic-pat", %{id: 16_072_585}, opts)
        end

      assert {:ok, %{items: items}} = result
      assert items |> Enum.map(& &1.number) |> Enum.sort() == [1, 2, 3, 4]

      issue_calls =
        for {"/repos/phoenixframework/phoenix/issues", params} <-
              Process.get(:pat_reader_requests),
            do: params

      assert length(issue_calls) == 4
    end
  end

  test "account repository discovery preserves the next-page opaque cursor", %{opts: opts} do
    after_cursor = "catalog-cursor+/="

    link =
      "<https://api.github.com/user/repos?sort=full_name&per_page=50&page=2&after=#{URI.encode_www_form(after_cursor)}>; rel=\"next\""

    fixture(fn
      "/user", _ ->
        owner(1, "alice")

      "/user/memberships/orgs", _ ->
        []

      "/user/repos", %{"page" => "1"} ->
        {:link, [repository(11, "alice", "first", 1)], link}

      "/user/repos", %{"page" => "2", "after" => ^after_cursor} ->
        [repository(12, "alice", "second", 1)]
    end)

    assert {:ok, %{repositories: repositories}} = PatClient.catalog("synthetic-pat", opts)
    assert Enum.map(repositories, & &1.id) == [11, 12]
  end

  test "an issues page containing only PRs follows the next page", %{opts: opts} do
    fixture(fn
      "/repositories/11", _ ->
        repository(11, "studio", "first")

      "/repos/studio/first/issues", %{"page" => "1"} ->
        {[Map.put(issue(1, 1), "pull_request", %{})], :next}

      "/repos/studio/first/issues", %{"page" => "2"} ->
        [issue(2, 2)]
    end)

    assert {:ok, %{items: [%{number: 2}], cursor: nil}} =
             PatClient.feed(
               "synthetic-pat",
               [%{id: 11}],
               %{kind: :issues, state: :open},
               nil,
               opts
             )
  end

  test "numeric repository pagination links continue issues and pull requests", %{opts: opts} do
    for kind <- [:issues, :pulls] do
      resource = Atom.to_string(kind)
      named_path = "/repos/studio/first/#{resource}"

      fixture(fn
        "/repositories/11", _ ->
          repository(11, "studio", "first")

        ^named_path, %{"page" => "1"} ->
          {[issue(1, 2)], {:next_path, "/repositories/11/#{resource}"}}

        ^named_path, %{"page" => "2"} ->
          [issue(2, 1)]
      end)

      assert {:ok, %{items: [%{number: 1}, %{number: 2}], cursor: nil}} =
               PatClient.feed(
                 "synthetic-pat",
                 [%{id: 11}],
                 %{kind: kind, state: :open},
                 nil,
                 opts
               )
    end
  end

  test "global ordering continues when both repository streams need their next page", %{
    opts: opts
  } do
    fixture(fn
      "/repositories/11", _ ->
        repository(11, "studio", "first")

      "/repositories/12", _ ->
        repository(12, "studio", "second")

      "/repos/studio/first/issues", %{"page" => "1"} ->
        {Enum.map(1..50, &issue(&1, 104 - &1 * 2)), :next}

      "/repos/studio/first/issues", %{"page" => "2"} ->
        [issue(51, 2)]

      "/repos/studio/second/issues", %{"page" => "1"} ->
        {Enum.map(1..50, &issue(&1, 105 - &1 * 2)), :next}

      "/repos/studio/second/issues", %{"page" => "2"} ->
        [issue(51, 3)]
    end)

    repositories = [%{id: 11}, %{id: 12}]
    filters = %{kind: :issues, state: :open}

    {items, cursor} =
      Enum.reduce(1..4, {[], nil}, fn _, {acc, cursor} ->
        assert {:ok, page} = PatClient.feed("synthetic-pat", repositories, filters, cursor, opts)
        {acc ++ page.items, page.cursor}
      end)

    assert cursor == nil
    assert length(items) == 102
    assert Enum.map(items, & &1.updated_at) == Enum.sort(Enum.map(items, & &1.updated_at), :desc)
    assert length(Enum.uniq_by(items, &{&1.repository_id, &1.number})) == 102
  end

  test "legacy closed feed filters still request only open PRs and use the current repository name",
       %{opts: opts} do
    fixture(fn
      "/repositories/11", _ ->
        repository(11, "studio", "renamed")

      "/repos/studio/renamed/pulls", %{"state" => "open"} ->
        [
          issue(9, 9),
          issue(10, 10)
          |> Map.put("state", "closed")
          |> Map.put("merged_at", "2026-11-20T00:00:00Z")
        ]
    end)

    assert {:ok, %{items: [item]}} =
             PatClient.feed(
               "synthetic-pat",
               [%{id: 11}],
               %{kind: :pulls, state: :closed},
               nil,
               opts
             )

    assert item.state == "open"
    assert item.full_name == "studio/renamed"
    assert item.url == "https://github.com/studio/renamed/pull/9"
  end

  test "an organization feed skips a repository transferred since the catalog refresh", %{
    opts: opts
  } do
    fixture(fn
      "/repositories/11", _ -> repository(11, "new-owner", "transferred", 9)
      "/repositories/12", _ -> repository(12, "studio", "current", 2)
      "/repos/studio/current/issues", _ -> [issue(1, 3)]
    end)

    repos = [%{id: 11, required_owner_id: 2}, %{id: 12, required_owner_id: 2}]

    assert {:ok, result} =
             PatClient.feed("synthetic-pat", repos, %{kind: :issues, state: :open}, nil, opts)

    assert [%{repository_id: 12}] = result.items
    assert result.failed == %{11 => :repository_changed}

    refute Enum.any?(Process.get(:pat_reader_requests), fn {path, _} ->
             path == "/repos/new-owner/transferred/issues"
           end)
  end

  test "temporary repository failure leaves the other repository available", %{opts: opts} do
    fixture(fn
      "/repositories/11", _ -> {:status, 503}
      "/repositories/12", _ -> repository(12, "studio", "second")
      "/repos/studio/second/issues", _ -> [issue(2, 2)]
    end)

    assert {:ok, %{items: [%{repository_id: 12}], failed: %{11 => :unavailable}}} =
             PatClient.feed(
               "synthetic-pat",
               [%{id: 11}, %{id: 12}],
               %{kind: :issues, state: :open},
               nil,
               opts
             )
  end

  test "rate limiting pauses the whole feed and resumes from the same repository page", %{
    opts: opts
  } do
    fixture(fn
      "/repositories/11", _ -> repository(11, "studio", "first")
      "/repos/studio/first/issues", _ -> {:rate_limit, 90}
    end)

    repositories = [%{id: 11}, %{id: 12}]
    filters = %{kind: :issues, state: :open}
    assert {:ok, limited} = PatClient.feed("synthetic-pat", repositories, filters, nil, opts)
    assert limited.items == []
    assert limited.retry_at == opts[:now] + 90
    count = length(Process.get(:pat_reader_requests))

    assert {:ok, waiting} =
             PatClient.feed("synthetic-pat", repositories, filters, limited.cursor, opts)

    assert waiting.retry_at == limited.retry_at
    assert length(Process.get(:pat_reader_requests)) == count

    fixture(fn
      "/repositories/11", _ -> repository(11, "studio", "first")
      "/repositories/12", _ -> repository(12, "studio", "second")
      "/repos/studio/first/issues", _ -> [issue(1, 1)]
      "/repos/studio/second/issues", _ -> [issue(2, 2)]
    end)

    assert {:ok, %{items: items, retry_at: nil}} =
             PatClient.feed(
               "synthetic-pat",
               repositories,
               filters,
               limited.cursor,
               Keyword.put(opts, :now, limited.retry_at)
             )

    assert Enum.map(items, & &1.repository_id) == [12, 11]
  end

  test "request budget retains discovery progress for a large selected repository set", %{
    opts: opts
  } do
    fixture(fn path, _ ->
      case Regex.run(~r/\A\/repositories\/(\d+)\z/, path) do
        [_, id] -> repository(String.to_integer(id), "studio", "repo-#{id}")
        nil -> []
      end
    end)

    repositories = Enum.map(1..60, &%{id: &1})
    filters = %{kind: :issues, state: :open}

    assert {:ok, %{items: [], cursor: cursor}} =
             PatClient.feed("synthetic-pat", repositories, filters, nil, opts)

    assert cursor != nil
    assert length(Process.get(:pat_reader_requests)) == 100

    assert {:ok, %{items: [], cursor: nil}} =
             PatClient.feed("synthetic-pat", repositories, filters, cursor, opts)

    assert length(Process.get(:pat_reader_requests)) == 120
  end

  test "workflow runs keep the latest twenty in GitHub order and unwrap optional fields", %{
    opts: opts
  } do
    fixture(fn
      "/repositories/11", _ ->
        repository(11, "studio", "first")

      "/repos/studio/first/actions/runs", %{"per_page" => "20"} = params ->
        assert map_size(params) == 1

        runs =
          for id <- 25..1//-1 do
            %{
              "id" => id,
              "repository" => %{"id" => 11},
              "name" => "Checks",
              "run_number" => id + 100,
              "display_title" => "Build #{id}",
              "head_branch" => "main",
              "event" => "push",
              "actor" => %{"login" => "alice"},
              "status" => "completed",
              "conclusion" => "success",
              "updated_at" => "2026-11-21T00:00:00Z"
            }
          end

        %{"workflow_runs" => runs}
    end)

    assert {:ok, %{repository: %{id: 11}, runs: [first | _] = runs}} =
             PatClient.workflow_runs("synthetic-pat", %{id: 11}, opts)

    assert Enum.map(runs, & &1["id"]) == Enum.to_list(25..6//-1)

    assert %{
             "id" => 25,
             "name" => "Checks",
             "title" => "Build 25",
             "number" => 125,
             "branch" => "main",
             "actor" => "alice",
             "conclusion" => "success"
           } = first

    assert Enum.map(Process.get(:pat_reader_requests), &elem(&1, 0)) ==
             ["/repositories/11", "/repos/studio/first/actions/runs", "/repositories/11"]
  end

  test "malformed workflow results do not look like an empty successful listing", %{opts: opts} do
    for invalid <- [%{}, %{"workflow_runs" => [%{"id" => 12}]}] do
      fixture(fn
        "/repositories/11", _ -> repository(11, "studio", "first")
        "/repos/studio/first/actions/runs", _ -> invalid
      end)

      assert {:error, :invalid_response} =
               PatClient.workflow_runs("synthetic-pat", %{id: 11}, opts)
    end
  end

  defp fixture(handler), do: Process.put(:pat_reader_fixture, handler)
  defp owner(id, login), do: %{"id" => id, "login" => login}

  defp repository(id, login, name, owner_id \\ 2),
    do: %{"id" => id, "owner" => owner(owner_id, login), "name" => name}

  defp issue(number, minutes) do
    %{
      "number" => number,
      "title" => "Work #{number}",
      "state" => "open",
      "updated_at" => DateTime.to_iso8601(DateTime.add(~U[2026-11-20 00:00:00Z], minutes * 60)),
      "user" => %{"login" => "contributor"}
    }
  end
end
