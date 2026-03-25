# Ensure the samgita application (and its Repo) is started before tests run
{:ok, _} = Application.ensure_all_started(:samgita)

ExUnit.start()

# Exclude e2e tests by default; run with: mix test --include e2e
ExUnit.configure(exclude: [:e2e])

Ecto.Adapters.SQL.Sandbox.mode(Samgita.Repo, :manual)

# Global stub: all unit tests get {:ok, "mock response"} from the provider
# unless a specific test overrides it with Mox.expect/4 or Mox.stub/3.
Mox.stub(SamgitaProvider.MockProvider, :query, fn _prompt, _opts -> {:ok, "mock response"} end)

# Global stub: ObanClient delegates to real Oban by default.
# Individual tests can override with Mox.expect/4 or Mox.stub/3 to inject failures.
Mox.stub(Samgita.MockOban, :insert, fn job -> Oban.insert(job) end)
