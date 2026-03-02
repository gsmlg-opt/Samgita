defmodule Samgita.Release do
  @moduledoc """
  Release tasks for production deployment.

  These tasks are used when running migrations and other release-time operations
  in production environments where Mix is not available.

  ## Usage

      # Run migrations
      bin/samgita eval "Samgita.Release.migrate()"

      # Rollback migrations
      bin/samgita eval "Samgita.Release.rollback()"

      # Rollback to specific version
      bin/samgita eval "Samgita.Release.rollback(20240101000000)"
  """

  @app :samgita

  require Logger

  @doc """
  Run all pending migrations for both Samgita.Repo and SamgitaMemory.Repo.
  """
  def migrate do
    load_app()

    Logger.info("Running migrations for #{@app}...")

    # Migrate main repo
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    Logger.info("Migrations completed successfully!")
  end

  @doc """
  Rollback migrations for a specific repo.

  When given an integer version, rolls back to that version.
  When given a keyword list with `:step`, rolls back N migrations.
  """
  def rollback(repo, version) when is_integer(version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def rollback(repo, opts) when is_list(opts) do
    load_app()
    step = Keyword.fetch!(opts, :step)
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, step: step))
  end

  @doc """
  Rollback all migrations for a repo.
  """
  def rollback_all(repo) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, all: true))
  end

  @doc """
  Create the database for all repos.
  """
  def create do
    load_app()

    for repo <- repos() do
      case repo.__adapter__.storage_up(repo.config) do
        :ok ->
          Logger.info("Database created for #{inspect(repo)}")

        {:error, :already_up} ->
          Logger.info("Database already exists for #{inspect(repo)}")

        {:error, term} ->
          Logger.error("Failed to create database for #{inspect(repo)}: #{inspect(term)}")
          {:error, term}
      end
    end
  end

  @doc """
  Drop the database for all repos.
  """
  def drop do
    load_app()

    for repo <- repos() do
      case repo.__adapter__.storage_down(repo.config) do
        :ok ->
          Logger.info("Database dropped for #{inspect(repo)}")

        {:error, :already_down} ->
          Logger.info("Database already dropped for #{inspect(repo)}")

        {:error, term} ->
          Logger.error("Failed to drop database for #{inspect(repo)}: #{inspect(term)}")
          {:error, term}
      end
    end
  end

  @doc """
  Check migration status for all repos.
  """
  def migration_status do
    load_app()

    for repo <- repos() do
      Logger.info("\nMigration status for #{inspect(repo)}:")
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :status, []))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
    Application.load(:samgita_memory)
  end
end
