defmodule SamgitaWeb.GitHubConsoleFunctionalTest do
  use SamgitaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias Samgita.GitHub.{Console, PatDashboard}

  alias Samgita.Domain.{
    GitHubPatCatalog,
    GitHubPatItem,
    GitHubPatRepositorySync,
    GitHubPatWorkflowSnapshot
  }

  alias Samgita.Repo
  alias Samgita.Workers.{GitHubPatActionWorker, GitHubPatCatalogWorker, GitHubPatWorkflowWorker}
  alias SamgitaWeb.GitHubConsoleFixture, as: Fixture

  setup do
    previous_client = Application.get_env(:samgita, :github_console_client)
    previous_actions = Application.get_env(:samgita, :github_pat_action_client)
    previous_key = Application.get_env(:samgita, :github_pat_key_base)
    previous_observer = Application.get_env(:samgita, :github_console_fixture_observer)
    Application.put_env(:samgita, :github_console_client, SamgitaWeb.GitHubConsoleFixture)
    Application.put_env(:samgita, :github_pat_action_client, Fixture)
    Application.put_env(:samgita, :github_pat_key_base, String.duplicate("fixture-only-key-", 4))
    Application.put_env(:samgita, :github_console_fixture_observer, self())

    on_exit(fn ->
      restore_env(:github_console_client, previous_client)
      restore_env(:github_pat_action_client, previous_actions)
      restore_env(:github_pat_key_base, previous_key)
      restore_env(:github_console_fixture_observer, previous_observer)
    end)

    :ok
  end

  test "an unconfigured console links to GitHub settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/github")
    assert has_element?(view, "#github-setup a[href='/settings?section=github']")
    assert has_element?(view, "nav.appbar-actions a[href='/github']")
  end

  test "selection spans owners and survives saving and reopening settings", %{conn: conn} do
    seed_connection()
    assert_received :github_fixture_catalog
    initial_job = catalog_job()
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    render_async(view)

    assert has_element?(view, "#github-account", "samgita-demo")
    assert has_element?(view, "button#github-save-selection[type=button]")
    assert has_element?(view, "#github-repository-101")
    view |> element("#github-repository-101") |> render_click()
    view |> element("#github-owner-11") |> render_click()
    view |> element("#github-select-owner") |> render_click()

    view |> form("#github-repository-search", search: "backplane") |> render_change()
    assert has_element?(view, "#github-repository-202[checked]")
    refute has_element?(view, "#github-repository-201")

    view |> element("#github-owner-22") |> render_click()
    view |> element("#github-repository-301") |> render_click()
    view |> element("#github-save-selection") |> render_click()
    render_async(view)

    assert Enum.map(Console.settings().repositories, & &1.id) |> Enum.sort() == [
             101,
             201,
             202,
             301
           ]

    assert has_element?(view, "#github-selected-count", "4 repositories selected")
    assert Enum.sort(Console.settings().repository_ids) == [101, 301]
    assert Console.settings().selected_owners == [%{id: 11, login: "demo-tools"}]

    {:ok, reopened, _html} = live(conn, ~p"/settings?section=github")
    render_async(reopened)
    assert has_element?(reopened, "#github-repository-101[checked]")
    assert catalog_job().id == initial_job.id
    refute_received :github_fixture_catalog
  end

  test "overview counts only open cached rows alongside zero and pending repositories", %{
    conn: conn
  } do
    seed_connection([101, 202, 301])
    cache_repository(101)
    repository = Enum.find(Console.settings().repositories, &(&1.id == 202))

    cache_repository(202,
      items: Enum.reject(Fixture.cached_items(repository), &(&1.state == "open"))
    )

    {:ok, view, _html} = live(conn, ~p"/github")

    assert has_element?(view, "#github-tab-overview[aria-current=page]")
    assert has_element?(view, "#github-overview-scope", "Open only")
    assert has_element?(view, "#github-issues-count-101", "1")
    assert has_element?(view, "#github-pulls-count-101", "1")
    assert has_element?(view, "#github-issues-count-202", "0")
    assert has_element?(view, "#github-pulls-count-202", "0")
    assert has_element?(view, "#github-repository-summary-301", "Not synced")
    assert has_element?(view, "#github-issues-count-301", "—")

    view |> element("#github-pulls-count-101") |> render_click()
    assert has_element?(view, "#github-tab-pulls[aria-current=page]")
    refute has_element?(view, "#github-state-filter")
    assert has_element?(view, "#github-open-scope", "Open only")
    assert has_element?(view, "#github-item-101-3", "Improve repository navigation")
    refute has_element?(view, "#github-item-101-4")
    refute has_element?(view, "#github-tabs a[href*='state=']")
  end

  test "local issue pages preserve filters without requesting remote data or jobs", %{conn: conn} do
    seed_connection([101])
    repository = hd(Console.settings().repositories)
    template = hd(Fixture.cached_items(repository))

    items =
      for number <- 1..31 do
        %{
          template
          | number: number,
            title: "Cached issue #{number}",
            updated_at: DateTime.add(~U[2026-11-20 08:00:00Z], number) |> DateTime.to_iso8601(),
            url: "https://github.com/#{repository.owner}/#{repository.name}/issues/#{number}"
        }
      end

    cache_repository(101, items: items)
    assert_received :github_fixture_catalog
    jobs_before = Repo.aggregate(Styx.Job, :count)
    {:ok, view, _html} = live(conn, ~p"/github/issue?repository=101")

    assert has_element?(view, "table#github-items tbody tr#github-item-101-31")
    refute has_element?(view, "#github-item-101-1")
    view |> element("#github-next") |> render_click()
    assert has_element?(view, "#github-item-101-1")
    refute has_element?(view, "#github-item-101-31")
    assert has_element?(view, "#github-repository-filter option[value='101'][selected]")

    view |> element("#github-tab-pulls") |> render_click()
    assert has_element?(view, "#github-feed-empty")
    view |> element("#github-tab-overview") |> render_click()
    assert has_element?(view, "#github-issues-count-101", "31")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received :github_fixture_catalog
    refute_received {:github_fixture_feed, _, _}
    refute_received {:github_fixture_sync, _}
  end

  test "global item tables distinguish repositories and retain label colors and icon tooltips", %{
    conn: conn
  } do
    seed_connection([101, 201])

    for repository <- Console.settings().repositories do
      items =
        Enum.map(Fixture.cached_items(repository), fn item ->
          Map.merge(item, %{labels: ["triage"], label_colors: %{"triage" => "0052cc"}})
        end)

      cache_repository(repository.id, items: items)
    end

    assert_received :github_fixture_catalog
    jobs_before = Repo.aggregate(Styx.Job, :count)
    {:ok, view, _html} = live(conn, ~p"/github/issue?page=1")

    for heading <- ["Repository", "Title", "Author", "Type", "Labels", "Updated", "Actions"] do
      assert has_element?(view, "table#github-items thead th", heading)
    end

    for {id, name} <- [{101, "samgita-demo/notes"}, {201, "demo-tools/samgita"}] do
      row = "table#github-items tbody tr#github-item-#{id}-1"
      assert has_element?(view, row, "Review repository setup")
      assert has_element?(view, row, "samgita-demo")
      assert has_element?(view, row, "Bug")
      assert has_element?(view, "#{row} a[href^='/github/repository/#{id}']", name)
      assert has_element?(view, "#{row} time[datetime^='2026-11-20T08:00:00']")

      assert has_element?(
               view,
               "#{row} .badge[style*='background-color: #0052cc'][style*='color: #ffffff']",
               "triage"
             )

      assert_icon_tooltip(
        view,
        "github-copy-issues-#{id}-1",
        "github-copy-help-issues-#{id}-1-tooltip"
      )

      assert has_element?(
               view,
               "#github-copy-issues-#{id}-1[data-copy-text='https://github.com/#{name}/issues/1']"
             )

      assert_icon_tooltip(
        view,
        "github-action-close_issue-#{id}-1",
        "github-action-help-close_issue-#{id}-1-tooltip"
      )

      refute has_element?(view, "#github-item-#{id}-2")
    end

    view |> element("#github-tab-pulls") |> render_click()
    assert has_element?(view, "table#github-items thead th", "Repository")
    refute has_element?(view, "table#github-items thead th", "Type")

    for {id, name} <- [{101, "samgita-demo/notes"}, {201, "demo-tools/samgita"}] do
      row = "table#github-items tbody tr#github-item-#{id}-3"
      assert has_element?(view, row, "Improve repository navigation")

      assert has_element?(
               view,
               "#{row} a[href^='/github/repository/#{id}'][href*='tab=pulls']",
               name
             )

      assert_icon_tooltip(
        view,
        "github-copy-pulls-#{id}-3",
        "github-copy-help-pulls-#{id}-3-tooltip"
      )

      assert has_element?(
               view,
               "#github-copy-pulls-#{id}-3[data-copy-text='https://github.com/#{name}/pull/3']"
             )

      for action <- [:close_pull, :approve_pull, :merge_pull] do
        assert_icon_tooltip(
          view,
          "github-action-#{action}-#{id}-3",
          "github-action-help-#{action}-#{id}-3-tooltip"
        )
      end

      refute has_element?(view, "#github-action-rebase_pull-#{id}-3")
      refute has_element?(view, "#github-item-#{id}-4")
    end

    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received {:github_fixture_feed, _, _}
    refute_received {:github_fixture_sync, _}
  end

  test "global issue close and reopen target the correct repository with the same item number", %{
    conn: conn
  } do
    seed_connection([101, 201])
    Enum.each([101, 201], &cache_repository/1)
    {:ok, view, _html} = live(conn, ~p"/github/issue?page=1")

    view |> element("#github-action-close_issue-201-1-confirm") |> render_click()
    job = action_job(:close_issue, 1)
    assert job.args["repository_id"] == 201
    assert has_element?(view, "#github-action-close_issue-201-1[disabled]")
    assert has_element?(view, "#github-action-close_issue-101-1:not([disabled])")

    assert :ok = GitHubPatActionWorker.perform(job)
    assert cached_item(201, "issue", 1).state == "closed"
    assert cached_item(101, "issue", 1).state == "open"
    refute has_element?(view, "#github-item-201-1")
    assert has_element?(view, "#github-item-101-1")
    assert has_element?(view, "#github-closed-issue", "demo-tools/samgita")

    view |> element("#github-reopen-closed-issue") |> render_click()
    reopen = action_job(:reopen_issue, 1)
    assert reopen.args["repository_id"] == 201
    assert has_element?(view, "#github-reopen-closed-issue[disabled]")
    assert :ok = GitHubPatActionWorker.perform(reopen)
    assert has_element?(view, "#github-item-201-1")
    assert has_element?(view, "#github-item-101-1")
    refute has_element?(view, "#github-closed-issue")
    refute_received {:github_fixture_sync, _}
  end

  test "closing an issue or pull request from either table requires confirming the selected item",
       %{conn: conn} do
    seed_connection([101, 201])
    Enum.each([101, 201], &cache_repository/1)
    jobs_before = Repo.aggregate(Styx.Job, :count)

    for {action, number, global_path, tab, title} <- [
          {:close_issue, 1, ~p"/github/issue?page=1", :issues, "Review repository setup"},
          {:close_pull, 3, ~p"/github/pull-request?page=1", :pulls,
           "Improve repository navigation"}
        ],
        {path, key} <- [
          {global_path, "201-#{number}"},
          {~p"/github/repository/201?#{[tab: tab]}", number}
        ] do
      {:ok, view, _html} = live(conn, path)
      button_id = "github-action-#{action}-#{key}"
      dialog_id = "confirm-dialog-#{button_id}"
      dialog = "dialog##{dialog_id}"

      assert has_element?(
               view,
               "##{button_id}[command=show-modal][commandfor='#{dialog_id}']:not([phx-click])"
             )

      assert has_element?(view, "#{dialog}[aria-labelledby='#{dialog_id}-title']:not([open])")
      assert has_element?(view, "##{dialog_id}-title", "##{number}")
      assert has_element?(view, dialog, "demo-tools/samgita")
      assert has_element?(view, dialog, title)

      assert has_element?(
               view,
               "#{dialog} button[command=close][commandfor='#{dialog_id}'][autofocus]:not([phx-click])",
               "Cancel"
             )

      assert has_element?(
               view,
               "#{dialog} ##{button_id}-confirm[phx-click=repository_action]" <>
                 "[phx-value-action='#{action}'][phx-value-repository-id='201'][phx-value-number='#{number}']"
             )

      refute has_element?(view, "#{dialog} [phx-click]:not(##{button_id}-confirm)")
    end

    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    {:ok, pulls, _html} = live(conn, ~p"/github/pull-request?page=1")
    pulls |> element("#github-action-close_pull-201-3-confirm") |> render_click()
    job = action_job(:close_pull, 3)
    assert job.args["repository_id"] == 201
    assert job.args["number"] == 3
    assert has_element?(pulls, "#github-action-close_pull-201-3[disabled]")
    assert has_element?(pulls, "#github-action-close_pull-101-3:not([disabled])")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before + 1
    refute_received {:github_fixture_sync, _}
  end

  test "global pull table pagination preserves repository and owner filters", %{conn: conn} do
    seed_connection([101, 201])
    repository = Enum.find(Console.settings().repositories, &(&1.id == 201))
    template = Enum.find(Fixture.cached_items(repository), &(&1.number == 3))

    items =
      for number <- 1..31 do
        %{
          template
          | number: number,
            title: "Cached pull #{number}",
            updated_at: DateTime.add(~U[2026-11-20 09:00:00Z], number) |> DateTime.to_iso8601(),
            url: "https://github.com/#{repository.owner}/#{repository.name}/pull/#{number}"
        }
      end

    cache_repository(101)
    cache_repository(201, items: items)
    jobs_before = Repo.aggregate(Styx.Job, :count)

    {:ok, view, _html} =
      live(conn, ~p"/github/pull-request?owner=11&repository=201&page=1")

    assert has_element?(view, "table#github-items tbody tr#github-item-201-31")
    refute has_element?(view, "#github-item-101-3")
    refute has_element?(view, "#github-item-201-1")
    view |> element("#github-next") |> render_click()
    assert has_element?(view, "table#github-items tbody tr#github-item-201-1")
    refute has_element?(view, "#github-item-201-31")
    assert has_element?(view, "#github-owner-filter option[value='11'][selected]")
    assert has_element?(view, "#github-repository-filter option[value='201'][selected]")
    view |> element("#github-previous") |> render_click()
    assert has_element?(view, "#github-item-201-31")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received {:github_fixture_feed, _, _}
    refute_received {:github_fixture_sync, _}
  end

  test "overview paginates selected repositories even before the first sync", %{conn: conn} do
    seed_connection([101, 201, 202, 301])
    :ok = Console.save_selection(Console.version(), [101, 201, 202, 301], [33])
    jobs_before = Repo.aggregate(Styx.Job, :count)
    {:ok, view, _html} = live(conn, ~p"/github")
    assert has_element?(view, "#github-repository-summary-301")
    refute has_element?(view, "#github-repository-summary-101")
    view |> element("#github-next") |> render_click()
    assert has_element?(view, "#github-repository-summary-101", "Not synced")
    refute has_element?(view, "#github-repository-summary-301")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received {:github_fixture_feed, _, _}
  end

  test "repository tabs show open-item tables and preserve their independent local pages", %{
    conn: conn
  } do
    seed_connection([101, 201])
    repository = Enum.find(Console.settings().repositories, &(&1.id == 101))
    templates = Fixture.cached_items(repository)
    issue = Enum.find(templates, &String.contains?(&1.url, "/issues/"))
    pull = Enum.find(templates, &String.contains?(&1.url, "/pull/"))

    issues =
      for number <- 1..32 do
        %{
          issue
          | number: number,
            title: "Repository issue #{number}",
            state: if(number == 30, do: "closed", else: "open"),
            updated_at: DateTime.add(~U[2026-11-20 08:00:00Z], number) |> DateTime.to_iso8601(),
            url: "https://github.com/#{repository.owner}/#{repository.name}/issues/#{number}"
        }
      end

    pulls =
      for number <- 101..132 do
        %{
          pull
          | number: number,
            title: "Repository pull #{number}",
            state: if(number == 130, do: "merged", else: "open"),
            updated_at: DateTime.add(~U[2026-11-20 08:00:00Z], number) |> DateTime.to_iso8601(),
            url: "https://github.com/#{repository.owner}/#{repository.name}/pull/#{number}"
        }
      end

    cache_repository(101, items: issues ++ pulls)
    cache_repository(201)
    assert_received :github_fixture_catalog
    jobs_before = Repo.aggregate(Styx.Job, :count)
    {:ok, overview, _html} = live(conn, ~p"/github")
    assert has_element?(overview, "#github-issues-count-101", "31")
    assert has_element?(overview, "#github-pulls-count-101", "31")

    assert has_element?(
             overview,
             "#github-repository-link-101[href='/github/repository/101']",
             "samgita-demo/notes"
           )

    {:ok, detail, _html} =
      overview
      |> element("#github-repository-link-101")
      |> render_click()
      |> follow_redirect(conn)

    assert has_element?(detail, "#github-repository-title", "samgita-demo/notes")
    assert has_element?(detail, "nav.appbar-actions a[href='/github'][aria-current='page']")
    assert has_element?(detail, "#github-repository-issues-item-32", "Repository issue 32")
    refute has_element?(detail, "#github-repository-issues-item-30")
    assert has_element?(detail, "#github-repository-tab-issues[aria-current=page]")
    assert has_element?(detail, "#github-repository-issues table th", "Type")
    assert has_element?(detail, "#github-repository-issues-item-32", "Bug")
    assert has_element?(detail, "#github-repository-issues-item-32", "triage")

    assert has_element?(
             detail,
             "#github-copy-issues-32[phx-hook=GitHubClipboard][data-copy-text='https://github.com/samgita-demo/notes/issues/32']"
           )

    refute has_element?(detail, "#github-repository-pulls")
    refute has_element?(detail, "#github-repository-detail a[href*='demo-tools/samgita']")

    detail |> element("#github-repository-issues-next") |> render_click()
    assert has_element?(detail, "#github-repository-issues-item-1")
    refute has_element?(detail, "#github-repository-issues-item-32")
    detail |> element("#github-repository-tab-pulls") |> render_click()
    assert has_element?(detail, "#github-repository-pulls-item-132", "Repository pull 132")
    refute has_element?(detail, "#github-repository-pulls-item-130")
    refute has_element?(detail, "#github-repository-issues")
    detail |> element("#github-repository-pulls-next") |> render_click()
    assert has_element?(detail, "#github-repository-pulls-item-101")
    detail |> element("#github-repository-tab-issues") |> render_click()
    assert has_element?(detail, "#github-repository-issues-item-1")
    refute has_element?(detail, "#github-repository-issues-item-30")
    refute has_element?(detail, "#github-repository-pulls-item-130")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received :github_fixture_catalog
    refute_received {:github_fixture_feed, _, _}
    refute_received {:github_fixture_sync, _}
  end

  test "invalid or deselected repository details show unavailable without other repositories", %{
    conn: conn
  } do
    seed_connection([101, 201])
    Enum.each([101, 201], &cache_repository/1)
    {:ok, detail, _html} = live(conn, ~p"/github/repository/101")
    assert has_element?(detail, "#github-repository-issues-item-1")
    :ok = Console.save_selection(Console.version(), [201], [])
    assert has_element?(detail, "#github-repository-unavailable", "Repository unavailable")
    refute has_element?(detail, "#github-repository-issues")
    assert has_element?(detail, "#github-repository-detail a[href='/github']")

    for id <- ["not-an-id", "999999", "9223372036854775808"] do
      {:ok, invalid, _html} = live(conn, "/github/repository/#{id}")
      assert has_element?(invalid, "#github-repository-unavailable")
      refute has_element?(invalid, "#github-repository-issues")
      refute has_element?(invalid, "#github-repository-pulls")
    end
  end

  test "issue close feedback offers reopen while the table stays open-only", %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101")
    view |> element("#github-action-close_issue-1-confirm") |> render_click()
    close = action_job(:close_issue, 1)
    assert has_element?(view, "#github-action-status", "issue #1")
    assert has_element?(view, "#github-action-close_issue-1[disabled]")

    send(view.pid, {:github_pat_action, 201, close.id, :close_issue, 1, :ok})
    refute has_element?(view, "#github-closed-issue")
    assert :ok = GitHubPatActionWorker.perform(close)
    assert cached_item(101, "issue", 1).state == "closed"
    assert has_element?(view, "#github-action-status", "Issue #1 closed")
    assert has_element?(view, "#github-reopen-closed-issue", "Reopen #1")
    refute has_element?(view, "#github-repository-issues-item-1")

    view |> element("#github-reopen-closed-issue") |> render_click()
    reopen = action_job(:reopen_issue, 1)
    assert :ok = GitHubPatActionWorker.perform(reopen)
    assert has_element?(view, "#github-action-status", "Issue #1 reopened")
    assert has_element?(view, "#github-repository-issues-item-1")
    refute has_element?(view, "#github-closed-issue")

    view |> form("#github-reopen-issue-form", number: "2") |> render_submit()
    by_number = action_job(:reopen_issue, 2)
    assert by_number.args["repository_id"] == 101
    assert has_element?(view, "#github-action-status", "issue #2")
    refute has_element?(view, "#github-repository-issues-item-2")
    assert :ok = GitHubPatActionWorker.perform(by_number)
    assert has_element?(view, "#github-repository-issues-item-2")
    refute_received {:github_fixture_sync, _}
  end

  test "rebase uses the displayed revision and the completed job updates the PR table and count",
       %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    {:ok, overview, _} = live(conn, ~p"/github")
    {:ok, view, _} = live(conn, ~p"/github/repository/101?tab=pulls")
    merge_form = merge_form_selector(view, "github-action-merge_pull-3")
    view |> form(merge_form, action: "rebase_pull") |> render_submit()
    job = action_job(:rebase_pull, 3)
    assert job.args["expected_sha"] == cached_item(101, "pull_request", 3).head_sha
    assert has_element?(view, "#github-action-merge_pull-3[disabled]")
    assert has_element?(view, "#{merge_confirm_selector(merge_form)}[disabled]")
    assert :ok = GitHubPatActionWorker.perform(job)
    assert has_element?(view, "#github-action-status", "Rebase and merge completed")
    refute has_element?(view, "#github-repository-pulls-item-3")
    assert has_element?(overview, "#github-pulls-count-101", "0")
  end

  test "the merge dialog selects a method and submits the displayed repository and revision", %{
    conn: conn
  } do
    seed_connection([101, 201])
    Enum.each([101, 201], &cache_repository/1)
    displayed_sha = cached_item(201, "pull_request", 3).head_sha

    cached_item(101, "pull_request", 3)
    |> Ecto.Changeset.change(head_sha: String.duplicate("b", 40))
    |> Repo.update!()

    jobs_before = Repo.aggregate(Styx.Job, :count)

    for {path, key} <- [
          {~p"/github/pull-request?page=1", "201-3"},
          {~p"/github/repository/201?tab=pulls", "3"}
        ] do
      {:ok, view, _html} = live(conn, path)
      button_id = "github-action-merge_pull-#{key}"
      selector = merge_form_selector(view, button_id)
      dialog_id = selector |> String.trim_leading("#") |> String.trim_trailing("-form")
      dialog = "dialog##{dialog_id}"

      assert String.contains?(dialog_id, displayed_sha)
      assert has_element?(view, "##{button_id}[command=show-modal]:not([phx-click])")
      assert has_element?(view, "#{dialog}[aria-labelledby]:not([open])")
      assert has_element?(view, dialog, "#3")
      assert has_element?(view, dialog, "demo-tools/samgita")
      assert has_element?(view, dialog, "Improve repository navigation")
      assert has_element?(view, "form#{selector}[phx-submit=repository_action]")
      rendered_dialog = view |> element(dialog) |> render() |> LazyHTML.from_fragment()

      assert Enum.count(LazyHTML.query(rendered_dialog, "form[phx-submit=repository_action]")) ==
               1

      assert Enum.count(LazyHTML.query(rendered_dialog, "input[type=radio][name=action]")) == 2

      for {action, label} <- [
            {"merge_pull", "Create a merge commit"},
            {"rebase_pull", "Rebase and merge"}
          ] do
        assert has_element?(
                 view,
                 "#{selector} input[type=radio][name=action][value='#{action}'][required]"
               )

        assert has_element?(view, selector, label)
      end

      refute has_element?(view, "#{selector} input[name=action][checked]")

      for {name, value} <- [
            {"repository-id", "201"},
            {"number", "3"},
            {"head-sha", displayed_sha}
          ] do
        assert has_element?(
                 view,
                 "#{selector} input[type=hidden][name='#{name}'][value='#{value}']"
               )
      end

      assert has_element?(
               view,
               "#{dialog} button[command=close][commandfor='#{dialog_id}']:not([phx-click])",
               "Cancel"
             )

      assert has_element?(view, "#{merge_confirm_selector(selector)}:not([disabled])")
      refute has_element?(view, "#github-action-rebase_pull-#{key}")
    end

    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    {:ok, view, _html} = live(conn, ~p"/github/pull-request?page=1")
    selector = merge_form_selector(view, "github-action-merge_pull-201-3")
    view |> form(selector, action: "merge_pull") |> render_submit()
    job = action_job(:merge_pull, 3)
    assert job.args["repository_id"] == 201
    assert job.args["number"] == 3
    assert job.args["expected_sha"] == displayed_sha
    assert has_element?(view, "#github-action-merge_pull-201-3[disabled]")
    assert has_element?(view, "#{merge_confirm_selector(selector)}[disabled]")
    assert has_element?(view, "#github-action-merge_pull-101-3:not([disabled])")

    assert :ok = GitHubPatActionWorker.perform(job)
    assert cached_item(201, "pull_request", 3).state == "merged"
    assert cached_item(101, "pull_request", 3).state == "open"
    refute has_element?(view, "#github-item-201-3")
    assert has_element?(view, "#github-item-101-3")
    assert has_element?(view, "#github-action-status", "Merge completed")
    refute_received {:github_fixture_sync, _}
  end

  test "a queued merge reports a changed pull head and refreshes its dialog revision", %{
    conn: conn
  } do
    seed_connection([101])
    cache_repository(101)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101?tab=pulls")
    previous_form = merge_form_selector(view, "github-action-merge_pull-3")
    view |> form(previous_form, action: "merge_pull") |> render_submit()
    job = action_job(:merge_pull, 3)
    next_sha = String.duplicate("c", 40)

    cached_item(101, "pull_request", 3)
    |> Ecto.Changeset.change(head_sha: next_sha)
    |> Repo.update!()

    assert {:cancel, :head_changed} = GitHubPatActionWorker.perform(job)
    assert cached_item(101, "pull_request", 3).state == "open"
    assert has_element?(view, "#github-action-error", "has changed")
    assert has_element?(view, "#github-repository-pulls-item-3")
    refute has_element?(view, previous_form)
    current_form = merge_form_selector(view, "github-action-merge_pull-3")
    assert String.contains?(current_form, next_sha)
    assert has_element?(view, "#{current_form} input[name='head-sha'][value='#{next_sha}']")
  end

  test "pull request tables expose separate operations and missing-head feedback", %{conn: conn} do
    seed_connection([101])
    repository = hd(Console.settings().repositories)
    items = Enum.map(Fixture.cached_items(repository), &Map.put(&1, :head_sha, nil))
    cache_repository(101, items: items)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101?tab=pulls")
    assert has_element?(view, "#github-repository-tab-pulls[aria-current=page]")
    assert has_element?(view, "#github-repository-pulls table th", "Author")
    assert has_element?(view, "#github-repository-pulls-item-3", "samgita-demo")

    assert has_element?(
             view,
             "#github-action-close_pull-3:not([disabled])[aria-label*='Close pull request #3']"
           )

    assert has_element?(
             view,
             "#github-action-approve_pull-3[disabled][aria-label*='Approve pull request #3']"
           )

    assert has_element?(
             view,
             "#github-action-merge_pull-3[disabled][aria-label='Merge pull request #3']"
           )

    refute has_element?(view, "#github-action-rebase_pull-3")
    merge_form = merge_form_selector(view, "github-action-merge_pull-3")
    assert has_element?(view, "#{merge_confirm_selector(merge_form)}[disabled]")

    assert has_element?(
             view,
             "#github-repository-pulls-item-3",
             "Sync to load the pull request head"
           )

    assert has_element?(
             view,
             "#github-copy-pulls-3[data-copy-text='https://github.com/samgita-demo/notes/pull/3']"
           )
  end

  test "repository label backgrounds choose readable text and preserve neutral fallbacks", %{
    conn: conn
  } do
    seed_connection([101])
    repository = hd(Console.settings().repositories)
    labels = ["Blue", "Yellow", "Uncolored", "Legacy"]
    colors = %{"Blue" => "0052cc", "Yellow" => "fbca04", "Legacy" => "fff"}

    items =
      Enum.map(
        Fixture.cached_items(repository),
        &Map.merge(&1, %{labels: labels, label_colors: colors})
      )

    cache_repository(101, items: items)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101")

    assert has_element?(
             view,
             "#github-repository-issues-item-1 .badge[style*='background-color: #0052cc'][style*='color: #ffffff']",
             "Blue"
           )

    assert has_element?(
             view,
             "#github-repository-issues-item-1 .badge[style*='background-color: #fbca04'][style*='color: #000000']",
             "Yellow"
           )

    assert has_element?(view, "#github-repository-issues-item-1 .badge:not([style])", "Uncolored")
    assert has_element?(view, "#github-repository-issues-item-1 .badge:not([style])", "Legacy")

    rendered =
      view |> element("#github-repository-issues-item-1") |> render() |> LazyHTML.from_fragment()

    assert Enum.map(LazyHTML.query(rendered, ".badge"), &(LazyHTML.text(&1) |> String.trim())) ==
             labels

    view |> element("#github-repository-tab-pulls") |> render_click()

    assert has_element?(
             view,
             "#github-repository-pulls-item-3 .badge[style*='background-color: #0052cc'][style*='color: #ffffff']",
             "Blue"
           )

    assert has_element?(
             view,
             "#github-repository-pulls-item-3 .badge[style*='background-color: #fbca04'][style*='color: #000000']",
             "Yellow"
           )
  end

  test "Actions use distinct icon-only buttons linked to native hint tooltips", %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101")
    assert_icon_tooltip(view, "github-copy-issues-1", "github-copy-help-issues-1-tooltip")

    assert_icon_tooltip(
      view,
      "github-action-close_issue-1",
      "github-action-help-close_issue-1-tooltip"
    )

    assert has_element?(view, "#github-copy-issues-1[phx-hook=GitHubClipboard][data-copy-text]")
    assert has_element?(view, "#github-repository-issues-item-1 .badge:not([style])", "triage")

    view |> element("#github-repository-tab-pulls") |> render_click()
    assert_icon_tooltip(view, "github-copy-pulls-3", "github-copy-help-pulls-3-tooltip")

    ids = [
      "github-copy-pulls-3"
      | Enum.map(
          [:close_pull, :approve_pull, :merge_pull],
          &"github-action-#{&1}-3"
        )
    ]

    for action <- [:close_pull, :approve_pull, :merge_pull] do
      assert_icon_tooltip(
        view,
        "github-action-#{action}-3",
        "github-action-help-#{action}-3-tooltip"
      )
    end

    paths =
      Enum.map(ids, fn id ->
        view
        |> element("##{id}")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("svg path")
        |> Enum.map(&LazyHTML.attribute(&1, "d"))
      end)

    assert length(Enum.uniq(paths)) == 4
    assert has_element?(view, "#github-action-help-merge_pull-3-tooltip", "pull request #3")
    refute has_element?(view, "#github-action-rebase_pull-3")
    refute has_element?(view, "#github-action-help-rebase_pull-3-tooltip")
    merge_form = merge_form_selector(view, "github-action-merge_pull-3")

    assert has_element?(
             view,
             "#{merge_form} input[name='head-sha'][value='#{String.duplicate("a", 40)}']"
           )

    assert has_element?(
             view,
             "#github-action-help-close_pull-3-tooltip",
             "pull request #3 in samgita-demo/notes"
           )
  end

  test "workflow tab queues its first load once and manual sync remains available", %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    jobs_before = Repo.aggregate(Styx.Job, :count)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    view |> element("#github-repository-tab-workflow-runs") |> render_click()
    assert has_element?(view, "#github-repository-tab-workflow-runs[aria-current=page]")
    assert has_element?(view, "#github-workflow-empty", "Waiting for the first workflow sync")
    assert has_element?(view, "#github-repository-sync[aria-label='Sync workflow runs']")
    snapshot = workflow_snapshot(101)
    assert is_integer(snapshot.job_id)
    assert Repo.aggregate(Styx.Job, :count) == jobs_before + 1
    assert repository_assigns(view).workflow_timer == nil

    render_patch(view, "/github/repository/101?tab=workflow-runs")
    view |> element("#github-repository-sync") |> render_click()
    assert workflow_snapshot(101).job_id == snapshot.job_id
    assert Repo.aggregate(Styx.Job, :count) == jobs_before + 1
    assert has_element?(view, "#github-repository-sync-status", "Sync queued")
    refute_received {:github_fixture_workflows, _}
    assert :ok = GitHubPatWorkflowWorker.perform(Repo.get!(Styx.Job, snapshot.job_id))
    assert_received {:github_fixture_workflows, 101}
    assert has_element?(view, "#github-workflow-run-7001", "success")
    refute has_element?(view, "#github-repository-sync-status")
    view |> element("#github-repository-sync") |> render_click()
    assert workflow_snapshot(101).job_id != snapshot.job_id
  end

  test "workflow rows are capped and a single active timer stops on tab changes or completion", %{
    conn: conn
  } do
    seed_connection([101])
    cache_repository(101)
    runs = for number <- 1..21, do: workflow_run(number, "in_progress")
    cache_workflows(101, runs)
    {:ok, view, _html} = live(conn, ~p"/github/repository/101?tab=workflow-runs")

    rows =
      view
      |> element("#github-workflow-runs table")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("tbody tr")

    assert Enum.count(rows) == 20
    assert has_element?(view, "#github-workflow-runs", "in progress")
    assert has_element?(view, "#github-workflow-runs a[href*='/actions/runs/']")
    first = repository_assigns(view)
    assert is_reference(first.workflow_timer)
    assert Process.read_timer(first.workflow_timer) in 8_000..10_000

    send(view.pid, {:github_workflow_runs_changed, 101})
    render(view)
    assert repository_assigns(view).workflow_timer == first.workflow_timer
    view |> element("#github-repository-tab-issues") |> render_click()
    assert repository_assigns(view).workflow_timer == nil
    assert Process.read_timer(first.workflow_timer) == false
    jobs_before = Repo.aggregate(Styx.Job, :count)
    send(view.pid, {:github_workflow_poll, first.workflow_poll_token})
    render(view)
    assert Repo.aggregate(Styx.Job, :count) == jobs_before

    view |> element("#github-repository-tab-workflow-runs") |> render_click()
    active = repository_assigns(view)
    send(view.pid, {:github_workflow_poll, active.workflow_poll_token})
    render(view)
    assert is_integer(workflow_snapshot(101).job_id)
    assert repository_assigns(view).workflow_timer == nil

    snapshot = workflow_snapshot(101)
    Repo.update!(Ecto.Changeset.change(snapshot, job_id: nil, synced_at: DateTime.utc_now()))
    send(view.pid, {:github_workflow_runs_changed, 101})
    render(view)
    assert is_reference(repository_assigns(view).workflow_timer)
    assert Process.read_timer(repository_assigns(view).workflow_timer) <= 10_000

    snapshot = workflow_snapshot(101)

    Repo.update!(
      Ecto.Changeset.change(snapshot,
        runs: [workflow_run(1, "completed")],
        job_id: nil,
        error_code: nil
      )
    )

    send(view.pid, {:github_workflow_runs_changed, 101})
    assert has_element?(view, "#github-workflow-runs", "success")
    assert repository_assigns(view).workflow_timer == nil
    Repo.update!(Ecto.Changeset.change(workflow_snapshot(101), runs: []))
    send(view.pid, {:github_workflow_runs_changed, 101})
    assert has_element?(view, "#github-workflow-empty", "No workflow runs")
    assert repository_assigns(view).workflow_timer == nil
    refute_received {:github_fixture_workflows, _}
  end

  test "repository pages preserve selections and select an entire owner", %{conn: conn} do
    seed_connection()
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    render_async(view)
    view |> element("#github-repository-101") |> render_click()
    view |> element("#github-owner-33") |> render_click()

    assert has_element?(view, "#github-repository-1001")
    refute has_element?(view, "#github-repository-1026")
    view |> element("#github-repository-1001") |> render_click()
    view |> element("#github-repositories-next") |> render_click()
    assert has_element?(view, "#github-repository-1026")
    view |> element("#github-repository-1026") |> render_click()
    view |> element("#github-repositories-previous") |> render_click()
    assert has_element?(view, "#github-repository-1001[checked]")

    view |> element("#github-select-owner") |> render_click()
    assert has_element?(view, "#github-selected-count", "28 repositories selected")
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert length(Console.settings().repositories) == 28
  end

  test "a repository removed from the catalog can be kept or deselected", %{conn: conn} do
    seed_connection([101])
    %{connection: connection} = Console.settings()

    Samgita.Repo.insert!(%Samgita.Domain.GitHubPatSelection{
      connection_id: connection.id,
      github_id: 401,
      owner_id: 11,
      owner: "demo-tools",
      name: "retired"
    })

    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    render_async(view)
    assert has_element?(view, "#github-unlisted-selections", "demo-tools/retired")
    assert has_element?(view, "#github-repository-401[checked]")

    view |> element("#github-owner-11") |> render_click()
    view |> element("#github-repository-201") |> render_click()
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert Enum.sort(Enum.map(Console.settings().repositories, & &1.id)) == [101, 201, 401]

    view |> element("#github-repository-401") |> render_click()
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert Enum.sort(Enum.map(Console.settings().repositories, & &1.id)) == [101, 201]
    refute has_element?(view, "#github-unlisted-selections")
  end

  test "another operator's saved selection preserves an unsaved local draft", %{conn: conn} do
    seed_connection([101])
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    render_async(view)
    view |> element("#github-owner-11") |> render_click()
    view |> element("#github-repository-201") |> render_click()

    assert :ok = Console.save_selection(Console.settings().version, [301], [])
    assert has_element?(view, "#github-settings-error", "Your unsaved selection is preserved")
    assert has_element?(view, "#github-repository-201[checked]")
    assert has_element?(view, "#github-save-selection[disabled]")
    assert has_element?(view, "#github-selected-count", "2 repositories selected")

    view |> element("#github-reload") |> render_click()
    render_async(view)
    assert has_element?(view, "#github-selected-count", "1 repository selected")
    view |> element("#github-owner-22") |> render_click()
    assert has_element?(view, "#github-repository-301[checked]")
    refute has_element?(view, "#github-settings-error")
  end

  test "an unlisted explicit repository can be removed while its owner is selected", %{conn: conn} do
    seed_connection([101])
    %{connection: connection} = Console.settings()

    Repo.insert!(%Samgita.Domain.GitHubPatSelection{
      connection_id: connection.id,
      github_id: 401,
      owner_id: 11,
      owner: "demo-tools",
      name: "retired"
    })

    :ok = Console.save_selection(Console.version(), [101, 401], [11])
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    assert has_element?(view, "#github-repository-401[checked]:not([disabled])")
    view |> element("#github-repository-401") |> render_click()
    assert has_element?(view, "#github-repository-401:not([checked]):not([disabled])")
    assert has_element?(view, "#github-selected-count", "3 repositories selected")
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert Console.settings().repository_ids == [101]
    assert Console.settings().selected_owners == [%{id: 11, login: "demo-tools"}]
    refute has_element?(view, "#github-unlisted-selections")
  end

  test "a catalog notification after pruning reconciles the saved settings version", %{conn: conn} do
    seed_connection([101, 301])
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    view |> element("#github-owner-22") |> render_click()
    view |> form("#github-repository-search", search: "dashboard") |> render_change()
    %{connection: connection} = Console.settings()

    Repo.get_by!(Samgita.Domain.GitHubPatSelection, connection_id: connection.id, github_id: 301)
    |> Repo.delete!()

    current = bump_settings_version(connection.id)
    Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_catalog_changed)

    assert has_element?(view, "#github-pat-form[data-version='#{current.version}']")
    assert has_element?(view, "#github-owner-22[aria-pressed=true]")
    assert has_element?(view, "#github-repository-query[value=dashboard]")
    assert has_element?(view, "#github-repository-301:not([checked])")
    view |> element("#github-repository-301") |> render_click()
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    refute has_element?(view, "#github-settings-error")
    assert Enum.sort(Console.settings().repository_ids) == [101, 301]
  end

  test "a changed catalog version preserves a draft while showing newly discovered rows", %{
    conn: conn
  } do
    seed_connection([101])
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    view |> element("#github-owner-11") |> render_click()
    view |> element("#github-repository-201") |> render_click()
    :ok = Console.refresh_catalog(Console.version())
    bump_settings_version(Console.settings().connection.id)

    Process.put({Fixture, :extra_repositories}, [
      %{id: 203, owner_id: 11, owner: "demo-tools", name: "new-library"}
    ])

    :ok = run_catalog_job()

    assert has_element?(view, "#github-settings-error", "Your unsaved selection is preserved")
    assert has_element?(view, "#github-repository-201[checked]")
    assert has_element?(view, "#github-repository-203")
    assert has_element?(view, "#github-save-selection[disabled]")
  end

  test "owner filters and legacy state URLs only expose open cached issues and PRs", %{
    conn: conn
  } do
    seed_connection([101, 201, 202, 301])
    Enum.each([101, 201, 202, 301], &cache_repository/1)
    {:ok, view, _html} = live(conn, ~p"/github/issue")
    jobs_before = Repo.aggregate(Styx.Job, :count)

    view
    |> form("#github-filters", %{owner: "11", repository: "201"})
    |> render_change()

    assert has_element?(view, "#github-open-scope", "Open only")
    assert has_element?(view, "#github-item-201-1", "Review repository setup")
    refute has_element?(view, "#github-item-201-2")
    refute has_element?(view, "#github-item-301-1")
    refute has_element?(view, "#github-state-filter")

    for url <- [
          "/github/issue?owner=11&repository=201&state=closed",
          "/github/issue?owner=11&repository=201&state=all"
        ] do
      render_patch(view, url)
      assert has_element?(view, "#github-item-201-1")
      refute has_element?(view, "#github-item-201-2")
    end

    for url <- [
          "/github/pull-request?owner=11&repository=201&state=closed",
          "/github/pull-request?owner=11&repository=201&state=all"
        ] do
      render_patch(view, url)
      assert has_element?(view, "#github-open-scope", "Open only")
      assert has_element?(view, "#github-item-201-3", "Improve repository navigation")
      refute has_element?(view, "#github-item-201-4")
      refute has_element?(view, "#github-tabs a[href*='state=']")
    end

    assert has_element?(
             view,
             "#github-items a[href='https://github.com/demo-tools/samgita/pull/3']"
           )

    refute has_element?(view, "#github-item-201-2")

    result =
      PatDashboard.read(Console.settings(), :issues, %{
        owner_id: 11,
        repository_id: 201,
        state: :closed
      })

    assert Enum.map(result.rows, &{&1.number, &1.state}) == [{1, "open"}]
    {:ok, repository, _html} = live(conn, "/github/repository/201?state=all")
    assert has_element?(repository, "#github-repository-issues-item-1")
    refute has_element?(repository, "#github-repository-issues-item-2")
    repository |> element("#github-repository-tab-pulls") |> render_click()
    assert has_element?(repository, "#github-repository-pulls-item-3")
    refute has_element?(repository, "#github-repository-pulls-item-4")
    assert Repo.aggregate(Styx.Job, :count) == jobs_before
    refute_received {:github_fixture_feed, _, _}
  end

  test "saved selection changes update an open local GitHub list", %{conn: conn} do
    seed_connection([101, 301])
    Enum.each([101, 301], &cache_repository/1)
    {:ok, view, _html} = live(conn, ~p"/github/issue")
    assert has_element?(view, "#github-item-301-1")

    assert :ok = Console.save_selection(Console.settings().version, [101], [])
    assert has_element?(view, "#github-item-101-1")
    refute has_element?(view, "#github-item-301-1")
    refute_received {:github_fixture_feed, _, _}
  end

  test "whole-owner rules preserve explicit picks when removed", %{conn: conn} do
    seed_connection([201])
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    view |> element("#github-owner-11") |> render_click()
    view |> element("#github-select-owner") |> render_click()
    assert has_element?(view, "#github-repository-201[checked][disabled]")
    assert has_element?(view, "#github-repository-202[checked][disabled]")
    view |> element("#github-save-selection") |> render_click()
    render_async(view)

    assert has_element?(view, "#github-owner-11[aria-pressed=true]")
    assert Console.settings().repository_ids == [201]
    view |> element("#github-select-owner") |> render_click()
    assert has_element?(view, "#github-repository-201[checked]:not([disabled])")
    assert has_element?(view, "#github-repository-202:not([checked]):not([disabled])")
    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert Enum.map(Console.settings().repositories, & &1.id) == [201]
    assert Console.settings().selected_owners == []
  end

  test "manual directory refresh preserves a paged draft and reads only in the job", %{conn: conn} do
    seed_connection([101])
    assert_received :github_fixture_catalog
    {:ok, view, _html} = live(conn, ~p"/settings?section=github")
    view |> element("#github-owner-33") |> render_click()
    view |> element("#github-repositories-next") |> render_click()
    view |> element("#github-repository-1026") |> render_click()
    Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_feed_changed)
    assert has_element?(view, "#github-repository-1026[checked]")
    refute_received :github_fixture_catalog

    assert has_element?(view, "#github-refresh-catalog[title][aria-label]")
    view |> element("#github-refresh-catalog") |> render_click()
    assert has_element?(view, "#github-catalog-loading")
    assert has_element?(view, "#github-repository-1026[checked]")
    refute_received :github_fixture_catalog

    assert :ok = run_catalog_job()
    assert_received :github_fixture_catalog
    assert has_element?(view, "#github-owner-33[aria-pressed=true]")
    assert has_element?(view, "#github-repository-1026[checked]")
    refute has_element?(view, "#github-repository-1001")
    refute has_element?(view, "#github-catalog-loading")

    view |> element("#github-save-selection") |> render_click()
    render_async(view)
    assert has_element?(view, "#github-repository-1026[checked]")
    refute_received :github_fixture_catalog
    assert Enum.sort(Console.settings().repository_ids) == [101, 1026]
  end

  test "new organization repositories stay pending until their cached issue and PR sync arrives",
       %{conn: conn} do
    seed_connection()
    :ok = Console.save_selection(Console.version(), [], [11])
    Enum.each([201, 202], &cache_repository/1)
    {:ok, view, _html} = live(conn, ~p"/github?owner=11")
    refute has_element?(view, "#github-repository-summary-203")

    Process.put({Fixture, :extra_repositories}, [
      %{id: 203, owner_id: 11, owner: "demo-tools", name: "new-library"}
    ])

    :ok = Console.refresh_catalog(Console.version())
    assert :ok = run_catalog_job()
    assert has_element?(view, "#github-repository-summary-203", "Not synced")
    assert has_element?(view, "#github-issues-count-203", "—")

    cache_repository(203)
    Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_feed_changed)
    assert has_element?(view, "#github-issues-count-203", "1")
    view |> element("#github-issues-count-203") |> render_click()
    assert has_element?(view, "#github-item-203-1", "demo-tools/new-library")
    view |> element("#github-tab-pulls") |> render_click()

    assert has_element?(
             view,
             "#github-item-203-3 a[href='https://github.com/demo-tools/new-library/pull/3']"
           )

    assert Console.settings().repository_ids == []
    assert Enum.sort(Enum.map(Console.settings().repositories, & &1.id)) == [201, 202, 203]
    refute_received {:github_fixture_feed, _, _}
  end

  test "a selected empty owner keeps the local dashboard and lists within that owner", %{
    conn: conn
  } do
    seed_connection([101])
    cache_repository(101)
    :ok = Console.save_selection(Console.version(), [101], [44])
    {:ok, view, _html} = live(conn, ~p"/github?owner=44")
    assert has_element?(view, "#github-owner-filter option[value='44'][selected]", "demo-empty")
    assert has_element?(view, "#github-feed-empty")
    refute has_element?(view, "#github-repository-summary-101")

    view |> element("#github-tab-issues") |> render_click()
    assert has_element?(view, "#github-feed-empty")
    refute has_element?(view, "#github-item-101-1")
    :ok = Console.save_selection(Console.version(), [], [44])
    refute has_element?(view, "#github-setup")
    assert has_element?(view, "#github-feed-empty")
  end

  test "directory failure notifications preserve cached rows and local issue data", %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    {:ok, view, _html} = live(conn, ~p"/github/issue")
    assert has_element?(view, "#github-item-101-1")
    {:ok, settings, _html} = live(conn, ~p"/settings?section=github")

    Process.put({Fixture, :catalog_error}, :unavailable)
    settings |> element("#github-refresh-catalog") |> render_click()
    assert has_element?(settings, "#github-repository-101[checked]")
    assert has_element?(view, "#github-item-101-1")
    job = catalog_job()

    assert {:cancel, :unavailable} =
             GitHubPatCatalogWorker.perform(%{job | attempt: job.max_attempts})

    assert has_element?(settings, "#github-catalog-error")
    assert has_element?(settings, "#github-repository-101[checked]")
    assert has_element?(view, "#github-item-101-1")
    refute_received {:github_fixture_feed, _, _}
  end

  test "sync queues a full refresh without performing a remote read in the page", %{conn: conn} do
    seed_connection([101])
    cache_repository(101)
    assert_received :github_fixture_catalog
    {:ok, view, _html} = live(conn, ~p"/github")

    assert has_element?(view, "#github-sync[title][aria-label]")
    view |> element("#github-sync") |> render_click()
    assert has_element?(view, "#github-sync-status", "Sync queued.")

    assert Enum.any?(
             Repo.all(Styx.Job),
             &(&1.worker == "Samgita.Workers.GitHubPatSyncWorker" && &1.args["mode"] == "open")
           )

    assert has_element?(view, "#github-issues-count-101", "1")
    refute_received :github_fixture_catalog
    refute_received {:github_fixture_feed, _, _}
    refute_received {:github_fixture_sync, _}
  end

  test "pending and failed repository syncs are distinguished from empty local results", %{
    conn: conn
  } do
    seed_connection([101, 201])
    cache_repository(101, error_code: "unavailable")
    {:ok, view, _html} = live(conn, ~p"/github/issue")
    assert has_element?(view, "#github-item-101-1")
    assert has_element?(view, "#github-feed-pending", "1 repository awaiting sync")
    assert has_element?(view, "#github-feed-failures", "Sync failed for 1 repository")

    render_patch(view, "/github/issue?repository=201")
    assert has_element?(view, "#github-feed-pending")
    refute has_element?(view, "#github-feed-empty")
    refute has_element?(view, "#github-item-101-1")
    cache_repository(201)
    Phoenix.PubSub.broadcast(Samgita.PubSub, "github:console", :github_feed_changed)
    assert has_element?(view, "#github-item-201-1")
    refute has_element?(view, "#github-feed-pending")
    refute_received {:github_fixture_feed, _, _}
  end

  defp seed_connection(ids \\ []) do
    :ok = Console.connect("disposable-fixture", nil)
    :ok = run_catalog_job()
    if ids != [], do: :ok = Console.save_selection(Console.settings().version, ids, [])
  end

  defp cache_repository(id, opts \\ []) do
    settings = Console.settings()
    repository = Enum.find(settings.repositories, &(&1.id == id))
    connection = settings.connection

    Repo.insert!(%GitHubPatRepositorySync{
      connection_id: connection.id,
      repository_id: id,
      credential_version: connection.credential_version,
      owner_id: repository.owner_id,
      synced_at: DateTime.utc_now(),
      error_code: Keyword.get(opts, :error_code)
    })

    items = Keyword.get_lazy(opts, :items, fn -> Fixture.cached_items(repository) end)

    Enum.each(items, fn item ->
      {:ok, updated_at, _offset} = DateTime.from_iso8601(item.updated_at)
      updated_at = %{updated_at | microsecond: {elem(updated_at.microsecond, 0), 6}}

      Repo.insert!(%GitHubPatItem{
        connection_id: connection.id,
        repository_id: id,
        credential_version: connection.credential_version,
        kind: if(String.contains?(item.url, "/pull/"), do: "pull_request", else: "issue"),
        number: item.number,
        title: item.title,
        state: item.state,
        author: item.author,
        issue_type: Map.get(item, :issue_type),
        labels: Map.get(item, :labels, []),
        label_colors: Map.get(item, :label_colors, %{}),
        head_sha: Map.get(item, :head_sha),
        github_updated_at: updated_at,
        url: item.url
      })
    end)
  end

  defp run_catalog_job, do: GitHubPatCatalogWorker.perform(catalog_job())

  defp action_job(action, number) do
    job =
      Enum.find(Repo.all(Styx.Job), fn job ->
        job.worker == "Samgita.Workers.GitHubPatActionWorker" &&
          job.args["action"] == Atom.to_string(action) && job.args["number"] == number
      end)

    assert job
    job
  end

  defp cached_item(id, kind, number) do
    Repo.get_by!(GitHubPatItem,
      connection_id: Console.settings().connection.id,
      repository_id: id,
      kind: kind,
      number: number
    )
  end

  defp cache_workflows(id, runs) do
    settings = Console.settings()
    repository = Enum.find(settings.repositories, &(&1.id == id))

    Repo.insert!(%GitHubPatWorkflowSnapshot{
      connection_id: settings.connection.id,
      credential_version: settings.connection.credential_version,
      repository_id: id,
      owner_id: repository.owner_id,
      runs: runs,
      synced_at: DateTime.add(DateTime.utc_now(), -20, :second)
    })
  end

  defp workflow_snapshot(id),
    do:
      Repo.get_by!(GitHubPatWorkflowSnapshot,
        connection_id: Console.settings().connection.id,
        repository_id: id
      )

  defp workflow_run(number, status) do
    %{
      "id" => 7000 + number,
      "name" => "CI",
      "title" => "Run #{number}",
      "number" => number,
      "branch" => "main",
      "event" => "push",
      "actor" => "samgita-demo",
      "status" => status,
      "conclusion" => if(status == "completed", do: "success"),
      "updated_at" => "2026-11-20T09:00:00Z"
    }
  end

  defp repository_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp merge_form_selector(view, button_id) do
    trigger =
      view
      |> element("##{button_id}")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("button")

    [dialog_id] = LazyHTML.attribute(trigger, "commandfor")
    "##{dialog_id}-form"
  end

  defp merge_confirm_selector(form_selector),
    do: "button[type=submit][form='#{String.trim_leading(form_selector, "#")}']"

  defp assert_icon_tooltip(view, button_id, tooltip_id) do
    assert has_element?(
             view,
             "##{button_id}[aria-label][title][aria-describedby='#{tooltip_id}'][interestfor='#{tooltip_id}']"
           )

    assert has_element?(view, "##{button_id} svg[aria-hidden=true] path")

    assert has_element?(
             view,
             "##{tooltip_id}.tooltip-multiline[role=tooltip][popover=hint][phx-hook=DuskmoonPopover]"
           )

    button = view |> element("##{button_id}") |> render() |> LazyHTML.from_fragment()
    assert button |> LazyHTML.text() |> String.trim() == ""
  end

  defp catalog_job do
    %{connection: connection} = Console.settings()
    snapshot = Repo.get!(GitHubPatCatalog, connection.id)
    Repo.get!(Styx.Job, snapshot.job_id)
  end

  defp bump_settings_version(id) do
    Repo.get!(Samgita.Domain.GitHubPatConnection, id)
    |> Ecto.Changeset.change(version: Ecto.UUID.generate())
    |> Repo.update!()
  end

  defp restore_env(key, nil), do: Application.delete_env(:samgita, key)
  defp restore_env(key, value), do: Application.put_env(:samgita, key, value)
end
