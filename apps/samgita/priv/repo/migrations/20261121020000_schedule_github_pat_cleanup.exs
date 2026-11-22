defmodule Samgita.Repo.Migrations.ScheduleGitHubPatCleanup do
  use Ecto.Migration

  def change do
    alter table(:github_pat_connections) do
      add :next_cleanup_at, :utc_datetime_usec,
        null: false,
        default: fragment("(CURRENT_TIMESTAMP AT TIME ZONE 'UTC') + interval '15 days'")
    end
  end
end
