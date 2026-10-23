# Independent Elixir consumer

This example depends on `samgita_codex_driver`, which brings only the reusable
native Codex/schema, neutral protocol and Mint transport dependencies. It uses no
Samgita Repo, Web application, service or umbrella configuration.

Select the exact pinned official binary and run:

```sh
export CODEX_BINARY=/absolute/path/to/qualified/codex
mix deps.get
mix compile --warnings-as-errors
mix test
```

The test creates disposable HOME, CODEX_HOME and workspace directories, initializes
the actual process and lists threads. It performs no model call or authentication.
A missing binary is a failed prerequisite, never a skipped compatibility claim.

`StandaloneCodex.start/4` starts an owned process. `events/1` returns full native
messages and opaque server-interaction handles. Decide and authorize each approval
or tool response in your application before calling `respond/3`; this example
never approves a request automatically. A sent response is not confirmed upstream
processing. Examine driver interaction outcomes and subsequent native events.

Run `scripts/codex/verify_consumer.py` from the repository to repeat this proof in
a temporary directory outside the umbrella. This verifies independent consumption
and a real process round trip, not the entire upstream feature matrix.
