Postgrex.Types.define(
  SamgitaMemory.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
