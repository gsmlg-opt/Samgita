defmodule Samgita.Migration.StyxPreservationTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.{Postgres, SQL}
  alias Samgita.MigrationRepo

  @migrations Path.expand("../../../priv/repo/migrations", __DIR__)

  test "fresh Styx migration and rollback preserve stored jobs" do
    database =
      "samgita_redesign_styx_#{Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)}_test"

    opts =
      Samgita.Repo.config()
      |> Keyword.drop([:name, :pool])
      |> Keyword.merge(
        database: database,
        pool: DBConnection.ConnectionPool,
        pool_size: 2,
        template: "template0",
        encoding: "UTF8",
        log: false
      )

    assert :ok = Postgres.storage_up(opts)
    start_supervised!({MigrationRepo, opts})

    modules =
      Path.wildcard(Path.join(@migrations, "[0-9]*_*.exs"))
      |> Enum.map(fn path ->
        [version, _] = Path.basename(path) |> String.split("_", parts: 2)
        [_, name] = Regex.run(~r/^defmodule ([\w.]+) do/, File.read!(path))
        module = Module.concat(String.split(name, "."))
        unless Code.ensure_loaded?(module), do: Code.compile_file(path)
        {String.to_integer(version), module}
      end)

    Ecto.Migrator.run(MigrationRepo, modules, :up, to: 20_261_023_000_004, log: false)

    assert SQL.query!(MigrationRepo, "SELECT to_regclass('public.styx_jobs')", [], log: false).rows ==
             [[nil]]

    Ecto.Migrator.run(MigrationRepo, modules, :up, all: true, log: false)

    assert SQL.query!(MigrationRepo, "SELECT count(*) FROM styx_jobs", [], log: false).rows == [
             [0]
           ]

    SQL.query!(
      MigrationRepo,
      "INSERT INTO styx_jobs (worker,queue,args,state) VALUES ($1,$2,$3,'scheduled')",
      ["Samgita.Workers.ScheduleTickWorker", "hub_schedules", %{"retained" => true}],
      log: false
    )

    before = SQL.query!(MigrationRepo, "SELECT * FROM styx_jobs ORDER BY id", [], log: false).rows
    Ecto.Migrator.run(MigrationRepo, modules, :down, step: 1, log: false)
    Ecto.Migrator.run(MigrationRepo, modules, :up, all: true, log: false)

    assert SQL.query!(MigrationRepo, "SELECT * FROM styx_jobs ORDER BY id", [], log: false).rows ==
             before

    assert SQL.query!(MigrationRepo, "SELECT count(*) FROM styx_jobs", [], log: false).rows == [
             [1]
           ]
  end
end
