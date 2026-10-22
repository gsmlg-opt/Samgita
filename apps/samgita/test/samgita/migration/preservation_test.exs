defmodule Samgita.Migration.PreservationTest do
  use ExUnit.Case, async: false
  alias Samgita.MigrationRepo
  @root Path.expand("../../../../..", __DIR__)
  @migrations Path.join(@root, "apps/samgita/priv/repo/migrations")
  @neutral_projects ~w(description state version event_sequence migration_metadata)
  @neutral_tasks ~w(title description state version adopted execution_hold required_capabilities migration_metadata accepted_at fence_counter)
  @history ~w(projects tasks agent_runs artifacts memories snapshots webhooks prds chat_messages features notifications task_dependencies agent_messages sm_memories)

  test "restored migration sources match the pinned revision including memory provenance" do
    manifest =
      @root
      |> Path.join("test/fixtures/redesign/migration-sources.json")
      |> File.read!()
      |> Jason.decode!()

    assert manifest["source_revision"] == "2bc3765ac94e1faea50f061b6938c0ef51e6f92b"
    assert length(manifest["files"]) == 21

    for file <- manifest["files"] do
      path =
        if file["active"],
          do: file["source"],
          else: "test/fixtures/redesign/memory_migrations/" <> Path.basename(file["source"])

      bytes = File.read!(Path.join(@root, path))
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == file["sha256"], path
    end
  end

  test "additive expansion preserves populated legacy records, references, chronology and opaque memory data" do
    suffix = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    database = "samgita_redesign_p3_migration_#{suffix}_test"

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

    assert :ok = Ecto.Adapters.Postgres.storage_up(opts)
    start_supervised!({MigrationRepo, opts})
    migrations = migration_modules()
    # No platform is started against this database. The migration Repo is the
    # sole client; the preserved database remains a named rehearsal artifact.
    Ecto.Migrator.run(MigrationRepo, migrations, :up, to: 20_260_907_000_000, log: false)
    p = Ecto.UUID.generate()
    t = Ecto.UUID.generate()
    a = Ecto.UUID.generate()

    query(
      "INSERT INTO projects (id,name,git_url,status,phase,config,inserted_at,updated_at) VALUES ($1,'history','git@github.com:old/repo.git','running','planning','{\"opaque\":\"keep\"}', '2026-01-02 03:04:05','2026-02-03 04:05:06')",
      [uuid(p)]
    )

    query(
      "INSERT INTO tasks (id,project_id,type,status,agent_id,attempts,payload,result,inserted_at,updated_at) VALUES ($1,$2,'legacy','completed','worker-17',9,'{\"nested\":[1,2]}','{\"outcome\":\"old\"}','2026-01-03','2026-02-04')",
      [uuid(t), uuid(p)]
    )

    query(
      "INSERT INTO artifacts (id,project_id,task_id,type,path,metadata,inserted_at,updated_at) VALUES ($1,$2,$3,'report','old/path','{\"retain\":true}','2026-01-04','2026-02-05')",
      [uuid(a), uuid(p), uuid(t)]
    )

    query(
      "INSERT INTO notifications (title,message,project_id,inserted_at,updated_at) VALUES ('historical','preserve integer key',$1,'2026-01-01','2026-01-01')",
      [uuid(p)]
    )

    # An opaque memory-table sentinel verifies the expansion never touches the
    # removed Repo's data. Full pgvector/dual-Repo cutover remains a live gate.
    query(
      "CREATE TABLE sm_memories (id uuid PRIMARY KEY, scope_id text, source_id text, payload jsonb)"
    )

    query("INSERT INTO sm_memories VALUES ($1,$2,$3,'{\"opaque\":\"memory\"}')", [
      uuid(Ecto.UUID.generate()),
      p,
      t
    ])

    before = manifest()
    versions = query("SELECT version FROM schema_migrations ORDER BY version").rows
    Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false)
    assert manifest() == before

    assert versions ==
             query(
               "SELECT version FROM schema_migrations WHERE version < 20261022000001 ORDER BY version"
             ).rows

    assert query("SELECT state, adopted, agent_id, attempts FROM tasks WHERE id = $1", [uuid(t)]).rows ==
             [[nil, false, "worker-17", 9]]

    assert query("SELECT owner,admission_open FROM platform_authority").rows == [["none", false]]
    assert query("SELECT count(*) FROM task_attempts").rows == [[0]]
    Ecto.Migrator.run(MigrationRepo, migrations, :up, all: true, log: false)
    assert manifest() == before

    assert query(
             "SELECT data_type FROM information_schema.columns WHERE table_name = 'notifications' AND column_name = 'id'"
           ).rows == [["bigint"]]
  end

  defp migration_modules do
    @migrations
    |> Path.join("[0-9]*_*.exs")
    |> Path.wildcard()
    |> Enum.map(fn path ->
      [version, _] = path |> Path.basename() |> String.split("_", parts: 2)
      [_, name] = Regex.run(~r/^defmodule ([\w.]+) do/, File.read!(path))
      module = Module.concat(String.split(name, "."))
      # The umbrella test alias may already have loaded these same modules.
      unless Code.ensure_loaded?(module), do: Code.compile_file(path)
      {String.to_integer(version), module}
    end)
  end

  defp manifest do
    Map.new(@history, fn table ->
      excluded =
        case table do
          "projects" -> @neutral_projects
          "tasks" -> @neutral_tasks
          _ -> []
        end

      rows =
        query("SELECT to_jsonb(t) - $1::text[] FROM " <> table <> " t ORDER BY id", [excluded]).rows

      {table, :crypto.hash(:sha256, :erlang.term_to_binary(rows))}
    end)
  end

  defp query(sql, params \\ []),
    do: Ecto.Adapters.SQL.query!(MigrationRepo, sql, params, log: false)

  defp uuid(id), do: Ecto.UUID.dump!(id)
end
