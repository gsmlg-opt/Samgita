defmodule Samgita.Repo.Migrations.AddGitHubPatLabelColors do
  use Ecto.Migration

  def change do
    alter table(:github_pat_items) do
      add :label_colors, :map, null: false, default: %{}
    end
  end
end
