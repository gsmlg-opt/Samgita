# Independent Elixir consumer

This example depends on `samgita_codex_driver` and its reusable native schema,
neutral protocol and Mint dependencies. It needs no Samgita Repo, database,
Phoenix endpoint, umbrella configuration or running Samgita service.

Use Elixir 1.18.5 / OTP 27, Python 3.11+, Linux `/proc`, `/bin/sh`, and the
official pinned Linux musl Codex **rust-v0.163.0**. `Workflows.run/4` verifies the
binary SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Missing prerequisites fail; tests never skip them.

From this directory in the repository's Devenv environment:

```sh
export CODEX_BINARY=/absolute/path/to/pinned/codex-x86_64-unknown-linux-musl
export CODEX_MODEL_FIXTURE_SCRIPT=/absolute/path/to/scripts/codex/ordinary_consumer_provider.py
mix deps.get
mix compile --warnings-as-errors
mix test
mix run run.exs
```

The streaming companion imports the adjacent, unchanged `model_fixture.py`.
Keep both scripts together when copying them. The provider speaks the Responses
model API over loopback; the app-server is the actual official Codex executable.
Task inputs and model-provider responses are synthetic; app-server responses
come from actual Codex. No external model or paid task is used.
The owned launches explicitly select `approval_policy="never"` and
`sandbox_mode="danger-full-access"`; no policy behavior is tested.

`run.exs` creates fresh disposable HOME, CODEX_HOME and workspace directories.
It runs the following flows through `StandaloneCodex.Workflows.run/4`:

1. Initialize, create a persistent thread, and submit text with one declared pure
   `fixture_lookup`. Receive the genuine `item/tool/call`, explicitly respond
   using its opaque handle, reconstruct incremental text, observe `turn/completed`
   and read history under the original thread/turn/item IDs.
2. Explicitly reconnect the owned stdio process, initialize generation 2, read the
   original thread, resume it, then read again. Compare original history and the
   provider journal. Retain the notification gap; request no additional turn.
3. With a separate provider/process, hold the turn at an unanswered genuine tool
   callback. Interrupt that exact turn, distinguish the response from the
   separately observed interrupted terminal event, and read its history. This
   proves interruption of a pure callback wait, not termination of a command or
   its descendants.

Complete native request/response envelopes, ordered event maps and interaction
handles remain available in the returned report. The callback `on_event` can
consume each event as it is drained; the example's default does not log payloads.
Collection has a five-second absolute deadline, 256-event/1-MiB bounds, and no
sleep or retry loop. A request response never substitutes for turn completion.

Every successfully started Session closes in `after`, even if the consumer
callback fails. Initialization errors close the newly owned process before
returning; cleanup failure is returned explicitly. Provider processes close in
`after` using the same ownership facilities. Normal completion verifies Session
termination, closed fixture Ports and disappeared native PIDs before removing
disposable files. Failures preserve the scratch evidence. `start_cleanup_test`
uses a clearly labeled scripted peer to cover the initialization-error leak.

`StandaloneCodex.start/5` is an example-owned launcher; its optional capabilities
argument preserves `start/4`. Use `initialize/2` explicitly after reconnect.
`events/1` retains full messages/handles, `respond/3` sends one explicit response,
and `notify/2` reports only local `sent_unconfirmed`, with no remote ACK claim.
A possibly executed mutation requires reconciliation; never automatically retry
it after a disconnect. The example does not implement an Agent host or platform
task acceptance.

From the repository root, run:

```sh
ERL_FLAGS='+S 2:2' devenv shell --no-tui -- \
  python3 -B scripts/codex/verify_consumer.py
```

The verifier copies only the three reusable packages and the two fixture scripts
into a new directory outside the umbrella, clears Mix path/config inheritance,
then gets dependencies, compiles, runs these three reviewed functional tests,
checks formatting and executes `run.exs`. Root config and platform dependencies
are absent. Existing borrowed-endpoint and controlled uncertainty tests are
mapped separately in the [milestone record](../../../../docs/codex-app-server/ordinary-functional-delivery.md).
Ordinary success does not establish full native compatibility, package
publication, real provider integration or platform production readiness.
