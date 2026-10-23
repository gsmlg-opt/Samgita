defmodule Samgita.Migration.GitHubPreservationTest do
  use ExUnit.Case, async: false
  alias Ecto.Adapters.{Postgres, SQL}
  alias Samgita.MigrationRepo
  @migrations Path.expand("../../../priv/repo/migrations", __DIR__)
  @p4 20_261_022_000_002
  @github 20_261_023_000_001
  @history ~w(projects tasks artifacts domain_events event_subscriptions event_deliveries task_attempts platform_authority)
  @github_tables ~w(github_connections github_repositories github_project_mappings github_deliveries github_objects github_observations github_syncs)

  test "GitHub expansion preserves P4 history and references without scheduling or destructive rollback" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    database = "samgita_redesign_github_preservation_#{suffix}_test"

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
    modules = migration_modules()
    Ecto.Migrator.run(MigrationRepo, modules, :up, to: @p4, log: false)
    [project, task, artifact, event, command] = for _ <- 1..5, do: Ecto.UUID.generate()

    query(
      ~s|INSERT INTO projects (id,name,git_url,status,phase,config,state,event_sequence,inserted_at,updated_at) VALUES ($1,'preserved project','git@github.com:old/provenance.git','running','planning','{"opaque":"keep"}','active',1,'2026-01-02 03:04:05','2026-02-03 04:05:06')|,
      [uuid(project)]
    )

    query(
      ~s|INSERT INTO tasks (id,project_id,type,status,agent_id,attempts,payload,result,inserted_at,updated_at) VALUES ($1,$2,'legacy','completed','historical-worker',9,'{"nested":[1,2]}','{"result":"retained"}','2026-01-03 01:02:03','2026-02-04 04:05:06')|,
      [uuid(task), uuid(project)]
    )

    query(
      "INSERT INTO artifacts (id,project_id,task_id,type,path,metadata,inserted_at,updated_at) VALUES ($1,$2,$3,'report','historical/path','{\"retain\":true}','2026-01-04','2026-02-05')",
      [uuid(artifact), uuid(project), uuid(task)]
    )

    query(
      "INSERT INTO domain_events (id,project_id,sequence,type,schema_version,actor,command_id,correlation_id,source,resource_type,resource_id,data,created_at,inserted_at,updated_at) VALUES ($1,$2,1,'task.updated','1.0','operator',$3,$3,'domain','task',$4,'{\"retained\":true}','2026-02-03 04:05:06.123456','2026-02-03','2026-02-03')",
      [uuid(event), uuid(project), uuid(command), uuid(task)]
    )

    before = manifest()
    versions = query("SELECT version FROM schema_migrations ORDER BY version").rows
    assert query("SELECT count(*) FROM oban_jobs").rows == [[0]]
    assert Ecto.Migrator.run(MigrationRepo, modules, :up, to: @github, log: false) == [@github]
    assert manifest() == before

    assert query("SELECT version FROM schema_migrations WHERE version <= $1 ORDER BY version", [
             @p4
           ]).rows == versions

    assert query("SELECT id,project_id,task_id FROM artifacts WHERE id = $1", [uuid(artifact)]).rows ==
             [[uuid(artifact), uuid(project), uuid(task)]]

    assert query(
             "SELECT id,project_id,resource_id,correlation_id FROM domain_events WHERE id = $1",
             [uuid(event)]
           ).rows == [[uuid(event), uuid(project), uuid(task), uuid(command)]]

    assert_no_side_effects()

    assert Ecto.Migrator.run(MigrationRepo, modules, :up, to: @github, log: false) == []
    assert manifest() == before
    assert_no_side_effects()

    migration =
      Enum.find_value(modules, fn {version, module} -> if version == @github, do: module end)

    assert_raise RuntimeError, ~r/forward-only/, fn ->
      Ecto.Migrator.down(MigrationRepo, @github, migration, log: false)
    end

    assert query("SELECT version FROM schema_migrations WHERE version = $1", [@github]).rows == [
             [@github]
           ]

    assert manifest() == before
    assert_no_side_effects()
  end

  defp migration_modules do
    @migrations
    |> Path.join("[0-9]*_*.exs")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      [version, _] = path |> Path.basename() |> String.split("_", parts: 2)
      [_, name] = Regex.run(~r/^defmodule ([\w.]+) do/, File.read!(path))
      module = Module.concat(String.split(name, "."))
      unless Code.ensure_loaded?(module), do: Code.compile_file(path)
      {String.to_integer(version), module}
    end)
  end

  defp manifest do
    Map.new(@history, fn table ->
      {table, query("SELECT to_jsonb(t) FROM " <> table <> " t ORDER BY id").rows}
    end)
  end

  defp assert_no_side_effects do
    assert query("SELECT count(*) FROM oban_jobs").rows == [[0]]
    for table <- @github_tables, do: assert(query("SELECT count(*) FROM " <> table).rows == [[0]])
    assert query("SELECT count(*) FROM task_attempts").rows == [[0]]
    assert query("SELECT owner,admission_open FROM platform_authority").rows == [["none", false]]
  end

  defp query(sql, args \\ []), do: SQL.query!(MigrationRepo, sql, args, log: false)
  defp uuid(id), do: Ecto.UUID.dump!(id)
end
