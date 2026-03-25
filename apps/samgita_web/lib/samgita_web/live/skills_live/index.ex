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
    Samgita.Agent.Types.all()
    |> Enum.map(fn {id, description, _model} ->
      category = agent_category(id)

      %{
        name: id,
        description: description,
        category: category,
        status: :active
      }
    end)
  end

  defp agent_category(id) do
    cond do
      String.starts_with?(id, "eng-") -> "Engineering"
      String.starts_with?(id, "ops-") -> "Operations"
      String.starts_with?(id, "biz-") -> "Business"
      String.starts_with?(id, "data-") -> "Data"
      String.starts_with?(id, "prod-") -> "Product"
      String.starts_with?(id, "growth-") -> "Growth"
      String.starts_with?(id, "review-") -> "Review"
      true -> "Other"
    end
  end

  def category_badge_color("Engineering"), do: "primary"
  def category_badge_color("Operations"), do: "success"
  def category_badge_color("Business"), do: "secondary"
  def category_badge_color("Data"), do: "tertiary"
  def category_badge_color("Product"), do: "error"
  def category_badge_color("Growth"), do: "warning"
  def category_badge_color("Review"), do: "info"
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
