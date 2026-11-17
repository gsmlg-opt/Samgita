defmodule Samgita.Repo.Migrations.AddAgentRemoval do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :removed_at, :utc_datetime_usec
    end

    create constraint(:agents, :removed_agents_disabled,
             check: "removed_at IS NULL OR NOT enabled"
           )
  end
end
