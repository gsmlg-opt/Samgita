defmodule Samgita.Migration.CoordinationPreservationTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.{Postgres, SQL}
  alias Samgita.MigrationRepo
  @migrations Path.expand("../../../priv/repo/migrations", __DIR__)

  test "P3 events, references, times and intents survive P4 without becoming sends" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    database = "samgita_redesign_p4_preservation_#{suffix}_test"

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

    Ecto.Migrator.run(MigrationRepo, modules, :up, to: 20_261_022_000_001, log: false)
    [p, a, event, subscription, delivery, command] = for _ <- 1..6, do: Ecto.UUID.generate()

    query(
      "INSERT INTO projects (id,name,git_url,state,inserted_at,updated_at) VALUES ($1,'retained','git@github.com:old/identity.git','active','2026-01-01','2026-01-02')",
      [uuid(p)]
    )

    query(
      "INSERT INTO agents (id,name,protocol,protocol_version,inserted_at,updated_at) VALUES ($1,'ordinary','samgita','1.0','2026-01-01','2026-01-02')",
      [uuid(a)]
    )

    query(
      "INSERT INTO domain_events (id,project_id,sequence,type,schema_version,actor,command_id,resource_type,resource_id,data,created_at,inserted_at,updated_at) VALUES ($1,$2,1,'project.updated','1.0','operator',$3,'project',$2,'{\"retain\":true}','2026-02-03 04:05:06.123456','2026-02-03','2026-02-03')",
      [uuid(event), uuid(p), uuid(command)]
    )

    query(
      "INSERT INTO event_subscriptions (id,project_id,agent_id,inserted_at,updated_at) VALUES ($1,$2,$3,'2026-02-03','2026-02-03')",
      [uuid(subscription), uuid(p), uuid(a)]
    )

    query(
      "INSERT INTO event_deliveries (id,event_id,subscription_id,subscription_revision,inserted_at,updated_at) VALUES ($1,$2,$3,1,'2026-02-03','2026-02-03')",
      [uuid(delivery), uuid(event), uuid(subscription)]
    )

    before =
      query(
        "SELECT id,project_id,sequence,type,command_id,resource_id,data,created_at,inserted_at,updated_at FROM domain_events"
      ).rows

    legacy = query("SELECT id,git_url,name,inserted_at,updated_at FROM projects").rows
    Ecto.Migrator.run(MigrationRepo, modules, :up, all: true, log: false)

    assert query(
             "SELECT id,project_id,sequence,type,command_id,resource_id,data,created_at,inserted_at,updated_at FROM domain_events"
           ).rows == before

    assert query("SELECT id,git_url,name,inserted_at,updated_at FROM projects").rows == legacy

    assert query("SELECT id,event_id,subscription_id,state,operation_id FROM event_deliveries").rows ==
             [[uuid(delivery), uuid(event), uuid(subscription), "legacy_unreviewed", nil]]

    assert query("SELECT correlation_id FROM domain_events").rows == [[uuid(command)]]
    assert query("SELECT count(*) FROM oban_jobs").rows == [[0]]
    Ecto.Migrator.run(MigrationRepo, modules, :up, all: true, log: false)
    assert query("SELECT count(*) FROM event_deliveries").rows == [[1]]

    migration_module =
      Enum.find_value(modules, fn {version, module} ->
        if version == 20_261_022_000_002, do: module
      end)

    assert_raise RuntimeError, ~r/forward-only/, fn -> migration_module.down() end
  end

  defp query(sql, args \\ []), do: SQL.query!(MigrationRepo, sql, args, log: false)
  defp uuid(id), do: Ecto.UUID.dump!(id)
end
