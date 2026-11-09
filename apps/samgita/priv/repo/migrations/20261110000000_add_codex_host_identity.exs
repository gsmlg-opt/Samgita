defmodule Samgita.Repo.Migrations.AddCodexHostIdentity do
  use Ecto.Migration

  # The Codex installation identity reported by `remoteControl/status/read`.
  # One machine (one Codex home) should be one Agent; equal installation IDs
  # reveal duplicates. Observed facts only; they grant nothing.
  def change do
    alter table(:codex_hosts) do
      add :installation_id, :text
      add :machine_name, :text
    end

    create index(:codex_hosts, [:installation_id])
  end
end
