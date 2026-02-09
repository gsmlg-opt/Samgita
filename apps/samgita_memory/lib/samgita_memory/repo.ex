defmodule SamgitaMemory.Repo do
  use Ecto.Repo,
    otp_app: :samgita_memory,
    adapter: Ecto.Adapters.Postgres
end
