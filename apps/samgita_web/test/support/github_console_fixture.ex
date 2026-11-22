defmodule SamgitaWeb.GitHubConsoleFixture do
  @moduledoc false

  @repositories [
    %{id: 101, owner_id: 1, owner: "samgita-demo", name: "notes"},
    %{id: 201, owner_id: 11, owner: "demo-tools", name: "samgita"},
    %{id: 202, owner_id: 11, owner: "demo-tools", name: "backplane"},
    %{id: 301, owner_id: 22, owner: "demo-apps", name: "dashboard"}
  ]

  def user(_token), do: {:ok, %{id: 1, login: "samgita-demo"}}

  def workflow_runs(_token, repository) do
    notify({:github_fixture_workflows, repository.id})
    runs = Process.get({__MODULE__, :workflow_runs}, [workflow_run()])
    {:ok, %{repository: Map.take(repository, [:id, :owner_id, :owner, :name]), runs: runs}}
  end

  defp workflow_run do
    %{
      "id" => 7001,
      "name" => "CI",
      "title" => "Check repository",
      "number" => 41,
      "branch" => "main",
      "event" => "push",
      "status" => "completed",
      "conclusion" => "success",
      "actor" => "samgita-demo",
      "updated_at" => "2026-11-20T09:00:00Z"
    }
  end

  def cached_items(repository), do: items(repository, :issues) ++ items(repository, :pulls)

  def prepare(_token, repository, action, number, expected_sha)
      when action in [:close_issue, :reopen_issue, :merge_pull, :rebase_pull] do
    kind = if action in [:merge_pull, :rebase_pull], do: "pull_request", else: "issue"
    item = Enum.find(cached_items(repository), &(&1.number == number))

    {:ok,
     %{
       repository: repository,
       action: action,
       number: number,
       expected_sha: expected_sha,
       item: Map.put(item, :kind, kind)
     }}
  end

  def execute(_token, prepared) do
    state = %{
      close_issue: "closed",
      reopen_issue: "open",
      merge_pull: "merged",
      rebase_pull: "merged"
    }

    {:ok, %{prepared.item | state: Map.fetch!(state, prepared.action)}}
  end

  def sync_repository(_token, repository) do
    notify({:github_fixture_sync, repository.id})

    items =
      repository
      |> cached_items()
      |> Enum.filter(&(&1.state == "open"))
      |> Enum.map(fn item ->
        kind = if String.contains?(item.url, "/pull/"), do: "pull_request", else: "issue"
        Map.put(item, :kind, kind)
      end)

    {:ok, %{repository: Map.take(repository, [:id, :owner_id, :owner, :name]), items: items}}
  end

  def catalog(_token) do
    notify(:github_fixture_catalog)

    case Process.get({__MODULE__, :catalog_error}) do
      nil ->
        {:ok,
         %{
           owners: [
             %{id: 1, login: "samgita-demo"},
             %{id: 11, login: "demo-tools"},
             %{id: 22, login: "demo-apps"},
             %{id: 33, login: "demo-library"},
             %{id: 44, login: "demo-empty"}
           ],
           repositories:
             @repositories ++
               paginated_repositories() ++ Process.get({__MODULE__, :extra_repositories}, []),
           memberships_available: true
         }}

      reason ->
        {:error, reason}
    end
  end

  defp paginated_repositories do
    for number <- 1..27 do
      %{
        id: 1000 + number,
        owner_id: 33,
        owner: "demo-library",
        name: "library-" <> String.pad_leading(Integer.to_string(number), 2, "0")
      }
    end
  end

  def feed(_token, repositories, filters, cursor) do
    notify({:github_fixture_feed, Enum.map(repositories, & &1.id), filters})

    offset = cursor || 0

    items =
      repositories
      |> Enum.flat_map(&items(&1, filters.kind))
      |> Enum.filter(&(&1.state == "open"))
      |> Enum.sort_by(&{&1.updated_at, &1.repository_id, &1.number}, :desc)

    {:ok,
     %{
       items: Enum.slice(items, offset, 2),
       cursor: if(offset + 2 < length(items), do: offset + 2),
       failed: %{},
       retry_at: nil
     }}
  end

  defp notify(message) do
    if observer = Application.get_env(:samgita, :github_console_fixture_observer) do
      send(observer, message)
    end
  end

  defp items(repository, :issues) do
    [
      item(repository, 1, "open", "Review repository setup", "2026-11-20T08:00:00Z"),
      item(repository, 2, "closed", "Update repository overview", "2026-11-19T08:00:00Z")
    ]
  end

  defp items(repository, :pulls) do
    [
      item(repository, 3, "open", "Improve repository navigation", "2026-11-20T09:00:00Z"),
      item(repository, 4, "merged", "Add repository status", "2026-11-19T09:00:00Z")
    ]
  end

  defp item(repository, number, state, title, updated_at) do
    path = if number <= 2, do: "issues", else: "pull"

    %{
      repository_id: repository.id,
      full_name: repository.owner <> "/" <> repository.name,
      number: number,
      title: title,
      state: state,
      author: "samgita-demo",
      issue_type: if(path == "issues", do: "Bug"),
      labels: if(path == "issues", do: ["triage"], else: ["enhancement"]),
      label_colors: %{},
      head_sha: if(path == "pull", do: String.duplicate("a", 40)),
      updated_at: updated_at,
      url: "https://github.com/#{repository.owner}/#{repository.name}/#{path}/#{number}"
    }
  end
end
