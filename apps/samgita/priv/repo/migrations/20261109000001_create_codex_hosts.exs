defmodule Samgita.Repo.Migrations.CreateCodexHosts do
  use Ecto.Migration

  # Operator-configured Codex app-server hosts (design §11). Only credential
  # reference names are stored; secret values stay in runtime configuration.
  def change do
    create table(:codex_hosts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_id, references(:agents, type: :uuid, on_delete: :restrict), null: false
      add :transport, :text, null: false
      add :url, :text
      add :connect_address, :text
      add :token_ref, :text
      add :allow_insecure, :boolean, null: false, default: false
      add :ssh_user, :text
      add :ssh_host, :text
      add :ssh_port, :integer
      add :ssh_key_ref, :text
      add :known_hosts, :text
      add :remote_codex_path, :text
      add :remote_socket_path, :text
      add :ensure_daemon, :boolean, null: false, default: false
      add :enabled, :boolean, null: false, default: false
      add :generation, :bigint, null: false, default: 0
      add :server_version, :text
      add :last_connected_at, :utc_datetime_usec
      add :version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:codex_hosts, [:agent_id])

    create constraint(:codex_hosts, :codex_host_transport,
             check:
               "(transport = 'websocket' AND url IS NOT NULL) OR (transport = 'ssh' AND ssh_host IS NOT NULL AND known_hosts IS NOT NULL)"
           )

    create constraint(:codex_hosts, :codex_host_counters,
             check: "generation >= 0 AND version > 0"
           )
  end
end
