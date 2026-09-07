{:ok, _} = Application.ensure_all_started(:samgita)
ExUnit.start()
ExUnit.configure(exclude: [:e2e])
Ecto.Adapters.SQL.Sandbox.mode(Samgita.Repo, :manual)
