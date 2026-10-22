defmodule Samgita.MigrationRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :samgita, adapter: Ecto.Adapters.Postgres
end
