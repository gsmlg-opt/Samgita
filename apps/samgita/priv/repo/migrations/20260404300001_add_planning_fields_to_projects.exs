defmodule Samgita.Repo.Migrations.AddPlanningFieldsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :start_mode, :string, default: "from_prd", null: false
      add :planning_auto_advance, :boolean, default: false
    end
  end
end
