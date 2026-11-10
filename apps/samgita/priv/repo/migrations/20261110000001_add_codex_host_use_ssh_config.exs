defmodule Samgita.Repo.Migrations.AddCodexHostUseSshConfig do
  use Ecto.Migration

  # An SSH host may use the operator's own OpenSSH configuration (host aliases,
  # key files and known_hosts) instead of Samgita's isolated settings; such a
  # host stores no known_hosts of its own.
  def up do
    alter table(:codex_hosts) do
      add :use_ssh_config, :boolean, null: false, default: false
    end

    drop constraint(:codex_hosts, :codex_host_transport)

    create constraint(:codex_hosts, :codex_host_transport,
             check:
               "(transport = 'websocket' AND url IS NOT NULL) OR (transport = 'ssh' AND ssh_host IS NOT NULL AND (known_hosts IS NOT NULL OR use_ssh_config))"
           )
  end

  def down do
    drop constraint(:codex_hosts, :codex_host_transport)

    create constraint(:codex_hosts, :codex_host_transport,
             check:
               "(transport = 'websocket' AND url IS NOT NULL) OR (transport = 'ssh' AND ssh_host IS NOT NULL AND known_hosts IS NOT NULL)"
           )

    alter table(:codex_hosts) do
      remove :use_ssh_config
    end
  end
end
