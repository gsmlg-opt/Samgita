defmodule Samgita.Repo.Migrations.AddActivePrdIdToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :active_prd_id, references(:prds, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:projects, [:active_prd_id])
  end
end
