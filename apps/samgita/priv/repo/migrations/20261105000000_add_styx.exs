defmodule Samgita.Repo.Migrations.AddStyx do
  use Ecto.Migration

  def up, do: Styx.Migration.up(version: 1)

  # Rollback switches application versions; job history must remain available.
  def down, do: :ok
end
