defmodule Samgita.Repo do
  use Ecto.Repo,
    otp_app: :samgita,
    adapter: Ecto.Adapters.Postgres
end
