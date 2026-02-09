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

  def category_color("Git Operations"), do: "bg-orange-100 text-orange-800"
  def category_color("Code Quality"), do: "bg-blue-100 text-blue-800"
  def category_color("CI/CD"), do: "bg-green-100 text-green-800"
  def category_color("Design"), do: "bg-purple-100 text-purple-800"
  def category_color("Automation"), do: "bg-red-100 text-red-800"
  def category_color(_), do: "bg-zinc-100 text-zinc-800"

  def status_icon(:active) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5 text-green-600" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def status_icon(:inactive) do
    assigns = %{}

    ~H"""
    <svg class="w-5 h-5 text-zinc-400" fill="currentColor" viewBox="0 0 20 20">
      <path
        fill-rule="evenodd"
        d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end
end
