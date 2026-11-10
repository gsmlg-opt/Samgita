defmodule Samgita.Repo.Migrations.AddCodexHostLocalTransport do
  use Ecto.Migration

  # `local` reaches the Codex daemon on the machine Samgita runs on through its
  # control socket; it needs no address or SSH settings.
  def up do
    drop constraint(:codex_hosts, :codex_host_transport)

    create constraint(:codex_hosts, :codex_host_transport,
             check:
               "(transport = 'websocket' AND url IS NOT NULL) OR (transport = 'ssh' AND ssh_host IS NOT NULL AND (known_hosts IS NOT NULL OR use_ssh_config)) OR transport = 'local'"
           )
  end

  def down do
    drop constraint(:codex_hosts, :codex_host_transport)

    create constraint(:codex_hosts, :codex_host_transport,
             check:
               "(transport = 'websocket' AND url IS NOT NULL) OR (transport = 'ssh' AND ssh_host IS NOT NULL AND (known_hosts IS NOT NULL OR use_ssh_config))"
           )
  end
end
