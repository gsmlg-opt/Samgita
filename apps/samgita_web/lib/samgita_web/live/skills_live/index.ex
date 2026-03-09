defmodule SamgitaWeb.SkillsLive.Index do
  use SamgitaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Skills",
       skills: list_skills()
     )}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, skills: list_skills())}
  end

  defp list_skills do
    # TODO: Implement actual skills listing
    # This should read from ~/.claude/skills/ directory
    [
      %{
        name: "git-commit",
        description: "Stage and commit changes with conventional commit message",
        category: "Git Operations",
        status: :active
      },
      %{
        name: "code-review",
        description: "Comprehensive code review with best practices",
        category: "Code Quality",
        status: :active
      },
      %{
        name: "fix-github-actions",
        description: "Fix GitHub Actions failures iteratively",
        category: "CI/CD",
        status: :active
      },
      %{
        name: "frontend-design",
        description: "Create production-grade frontend interfaces",
        category: "Design",
        status: :active
      },
      %{
        name: "loki-mode",
        description: "Multi-agent autonomous startup system",
        category: "Automation",
        status: :active
      }
    ]
  end

  def category_badge_color("Git Operations"), do: "tertiary"
  def category_badge_color("Code Quality"), do: "primary"
  def category_badge_color("CI/CD"), do: "success"
  def category_badge_color("Design"), do: "secondary"
  def category_badge_color("Automation"), do: "error"
  def category_badge_color(_), do: ""

  def status_icon(:active) do
    assigns = %{}

    ~H"""
    <.dm_mdi name="check-circle" class="w-5 h-5 text-success" />
    """
  end

  def status_icon(:inactive) do
    assigns = %{}

    ~H"""
    <.dm_mdi name="close-circle" class="w-5 h-5 text-on-surface-variant" />
    """
  end
end
