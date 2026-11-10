defmodule Samgita.Domain.CodexHost do
  @moduledoc false
  use Samgita.Schema

  schema "codex_hosts" do
    field :agent_id, :binary_id
    field :transport, :string
    field :url, :string
    field :connect_address, :string
    field :token_ref, :string
    field :allow_insecure, :boolean, default: false
    field :ssh_user, :string
    field :ssh_host, :string
    field :ssh_port, :integer
    field :ssh_key_ref, :string
    field :known_hosts, :string
    field :remote_codex_path, :string
    field :remote_socket_path, :string
    field :ensure_daemon, :boolean, default: false
    field :use_ssh_config, :boolean, default: false
    field :enabled, :boolean, default: false
    field :generation, :integer, default: 0
    field :server_version, :string
    field :installation_id, :string
    field :machine_name, :string
    field :last_connected_at, :utc_datetime_usec
    field :version, :integer, default: 1
    timestamps()
  end
end
