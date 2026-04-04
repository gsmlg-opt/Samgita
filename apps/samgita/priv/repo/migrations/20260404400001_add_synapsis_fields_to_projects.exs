defmodule Samgita.Repo.Migrations.AddSynapsisFieldsToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :synapsis_endpoints, :jsonb, default: "[]"
      add :provider_preference, :string, default: "claude_code", null: false
    end
  end
end
