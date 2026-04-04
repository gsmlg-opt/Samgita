ExUnit.start()

# Exclude e2e tests by default; run with: mix test --include e2e
ExUnit.configure(exclude: [:e2e, :benchmark])

Ecto.Adapters.SQL.Sandbox.mode(Samgita.Repo, :manual)

# Global stub: all unit tests get {:ok, "mock response"} from the provider
# unless a specific test overrides it with Mox.expect/4 or Mox.stub/3.
Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

# Session callbacks: return errors by default so the Worker falls back to query/2.
# Individual tests can override with Mox.expect/4 or Mox.stub/3 to test session paths.
Mox.stub(SamgitaProvider.MockProvider, :start_session, fn _prompt, _opts ->
  {:error, :not_available}
end)

Mox.stub(SamgitaProvider.MockProvider, :send_message, fn _session, _message ->
  {:error, :no_session}
end)

Mox.stub(SamgitaProvider.MockProvider, :close_session, fn _session -> :ok end)

# Global stub: ObanClient delegates to real Oban by default.
# Individual tests can override with Mox.expect/4 or Mox.stub/3 to inject failures.
Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)
