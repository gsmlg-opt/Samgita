defmodule Samgita.Release do
  @moduledoc """
  Migration tasks for the Agent Hub's single repository.

      bin/samgita eval "Samgita.Release.migrate()"

  Select the intended database through DATABASE_URL before running a release task.
  """

  @doc "Runs pending migrations for the authoritative repository."
  def migrate do
    Application.load(:samgita)
    {:ok, _, _} = Ecto.Migrator.with_repo(Samgita.Repo, &Ecto.Migrator.run(&1, :up, all: true))
    :ok
  end

  @doc "Rolls back the main repository to a migration version."
  def rollback(version) when is_integer(version) do
    Application.load(:samgita)

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Samgita.Repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end
end
