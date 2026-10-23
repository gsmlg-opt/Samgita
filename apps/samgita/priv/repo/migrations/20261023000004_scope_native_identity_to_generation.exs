defmodule Samgita.Repo.Migrations.ScopeNativeIdentityToGeneration do
  use Ecto.Migration

  def up do
    # A Session keeps its instance identity across reconnects, while upstream
    # request IDs may repeat in each connection generation. Retain every journal
    # row and establish the replacement constraints before removing the old ones.
    create unique_index(
             :native_runtime_events,
             [:runtime_id, :instance_id, :driver_generation, :source_sequence],
             name: :native_event_source_identity
           )

    create unique_index(
             :native_runtime_events,
             [:runtime_id, :instance_id, :driver_generation, :request_id_digest],
             where: "kind = 'server_request'",
             name: :native_server_request_identity
           )

    create unique_index(
             :native_runtime_operations,
             [:runtime_id, :instance_id, :driver_generation, :direction, :wire_id_digest],
             name: :native_runtime_request_generation_identity
           )

    drop index(:native_runtime_events, [:runtime_id, :instance_id, :source_sequence])
    drop index(:native_runtime_events, [:runtime_id, :instance_id, :request_id_digest])

    drop index(
           :native_runtime_operations,
           [:runtime_id, :instance_id, :direction, :wire_id_digest],
           name: :native_runtime_request_identity
         )
  end

  def down do
    raise "Native journals retain generation-specific history; use a compatible binary"
  end
end
