defmodule Samgita.Domain.NativeRuntimeBinding do
  @moduledoc false
  use Samgita.Schema

  schema "native_runtime_bindings" do
    field :project_id, :binary_id
    field :task_id, :binary_id
    field :attempt_id, :binary_id
    field :agent_id, :binary_id
    field :session_id, :binary_id
    field :connection_id, :binary_id
    field :connection_generation, :integer
    field :fence, :integer
    field :execution_epoch, :integer
    field :runtime_ref, Ecto.UUID
    field :instance_id, Ecto.UUID
    field :driver_generation, :integer
    field :driver, :string, default: "codex"
    field :driver_version, :string, default: "0.163.0"
    field :fingerprint_key_id, :string
    field :experimental, :boolean, default: false
    field :state, :string, default: "open"
    field :source_sequence, :integer, default: 0
    field :notification_gap, :boolean, default: false
    field :version, :integer, default: 1
    timestamps()
  end
end
