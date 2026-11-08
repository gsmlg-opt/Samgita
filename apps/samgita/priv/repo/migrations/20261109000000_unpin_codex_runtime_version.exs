defmodule Samgita.Repo.Migrations.UnpinCodexRuntimeVersion do
  use Ecto.Migration

  # Codex is no longer pinned (design §11, version policy). Existing rows keep
  # their recorded versions; the constraints now accept any well-formed version.
  @version_check "~ '^[0-9A-Za-z][0-9A-Za-z.+-]{0,63}$'"

  def up do
    drop constraint(:agents, :known_native_runtime)

    create constraint(:agents, :known_native_runtime,
             check:
               "(runtime_driver IS NULL AND runtime_version IS NULL) OR (runtime_driver = 'codex' AND runtime_version #{@version_check})"
           )

    drop constraint(:native_runtime_bindings, :native_runtime_contract)

    create constraint(:native_runtime_bindings, :native_runtime_contract,
             check:
               "driver = 'codex' AND driver_version #{@version_check} AND driver_generation > 0 AND state IN ('open','closed') AND source_sequence >= 0"
           )

    execute "ALTER TABLE native_runtime_bindings ALTER COLUMN driver_version DROP DEFAULT"
  end

  def down do
    execute "ALTER TABLE native_runtime_bindings ALTER COLUMN driver_version SET DEFAULT '0.163.0'"

    drop constraint(:native_runtime_bindings, :native_runtime_contract)

    create constraint(:native_runtime_bindings, :native_runtime_contract,
             check:
               "driver = 'codex' AND driver_version = '0.163.0' AND driver_generation > 0 AND state IN ('open','closed') AND source_sequence >= 0"
           )

    drop constraint(:agents, :known_native_runtime)

    create constraint(:agents, :known_native_runtime,
             check:
               "(runtime_driver IS NULL AND runtime_version IS NULL) OR (runtime_driver IS NOT NULL AND runtime_version IS NOT NULL AND runtime_driver = 'codex' AND runtime_version = '0.163.0')"
           )
  end
end
