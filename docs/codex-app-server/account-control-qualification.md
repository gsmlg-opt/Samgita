# Synthetic account control qualification

Status: scoped synthetic-backend native profile passed at both required seeds.
This document records
only the bounded credit-consumption and nudge unit. Gateway OAuth, OS keyrings,
user verification, real account effects, release/publication, and A11 remain
outside this unit. No full-compatibility claim follows from these scenarios.

## Pin and production handlers

Target: Codex `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, Linux x86_64 musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Both fixture and test check that executable digest before starting it.

The actual native handlers are
`app-server/src/request_processors/account_processor/rate_limit_resets.rs:46`
and `app-server/src/request_processors/account_processor.rs:1490` in the pinned
Rust source. `backend-client/src/client/rate_limit_resets.rs` builds consumption
POSTs; `backend-client/src/client.rs:426` builds nudges. Protocol declarations
in `app-server-protocol/src/protocol/common.rs:1347,1365` require initialization,
serialize under the global account-auth scope and have no experimentalApi gate.
The profile therefore initializes without experimental capability opt-in.

Only the immutable native executable emits app-server messages. The Python
fixture supplies HTTP responses for two explicitly synthetic endpoints. No mail
is sent and no real credit is redeemed; native `sent` and `reset` results are
acceptance of synthetic backend responses. They do not establish service effects.

## Owned implementation and isolation

- [Native scenarios](../../apps/samgita_codex_driver/test/native_account_control_profile.exs)
  use independent driver Session/Stdio with native ID correlation and complete
  response/error envelopes.
- [Synthetic backend](../../scripts/codex/isolated_account_control_fixture.py)
  execs a private user/network namespace, activates only loopback, verifies no
  IPv4/IPv6 default route or nonloopback route/interface, and records the parent
  and child namespace identities.
- Each case starts with fresh private home, CODEX_HOME, workspace and tmp paths,
  file-only primary auth and a fresh synthetic ChatGPT identity, synthetic API
  key or no auth. Both launcher and native process environments are allowlisted.
  Inherited account keys, proxy credentials, host HOME/CODEX_HOME, DBus and other
  ambient credentials are absent. No gateway credential store is configured.
- A static model catalog avoids discovery traffic. Apps/plugins/search/shell
  snapshots are disabled. The native input allowlist contains only handshake,
  the two account methods and `thread/loaded/list`. No turn, shell command, tool
  execution or inference is authorized. Unexpected HTTP/native input fails the
  scenario; native loaded-thread inventory must stay empty.
- The backend binds an ephemeral `127.0.0.1` listener inside the namespace. It
  bounds bodies, compares exact decoded JSON with the scenario's expected body,
  validates Authorization, ChatGPT-Account-ID, Host and Content-Type, and records
  only header-verification booleans. It rejects all other methods/routes/queries.
  Three exact startup metadata GET routes may return inert synthetic metadata.
  There is no generic success handler or redirect destination.
- Cleanup closes/reaps the native process, joins its output reader, shuts down
  and joins the backend, and confirms controller/native/namespace owner PIDs
  disappear before deleting the scratch directory. A final journal marker and
  synthetic-secret scans of journal/stderr are required. Existing processes are
  never selected or stopped.

`chatgpt_base_url` is either a bare owned origin or that origin plus
`/backend-api`. Native backend-client routing must produce exactly:

| Operation | Bare-origin profile | `/backend-api` profile |
| --- | --- | --- |
| Consume | `/api/codex/rate-limit-reset-credits/consume` | `/backend-api/wham/rate-limit-reset-credits/consume` |
| Nudge | `/api/codex/accounts/send_add_credits_nudge_email` | `/backend-api/wham/accounts/send_add_credits_nudge_email` |

## Scenario assertions

The profile contains 11 ExUnit scenarios. The first three groups repeat for both
base URL profiles; the remaining five use fresh bare-origin profiles.

| Group | Required native behavior and fixture evidence |
| --- | --- |
| Consume success, two profiles | Four exact backend codes map to `reset`, `nothingToReset`, `noCredit`, `alreadyRedeemed`. Selected Unicode credit/key bytes survive JSON forwarding. Omitted and null `creditId` omit backend `credit_id`. Four exact POSTs; backend `windows_reset` is absent from the native result. |
| Nudge success, two profiles | Both `credits` and `usage_limit` forward as backend `credit_type`. 200 and bodyless 204 produce `sent`; 429 produces `cooldown_active`. Four exact POSTs with corresponding bodies/statuses. |
| Backend failure, two profiles | Consume 500, unknown code, missing code and invalid JSON produce native -32603. Nudge 500 produces native -32603. Exact prefixes and absent error data are checked, with exactly one POST for each request. |
| Native value validation | Empty `idempotencyKey` and empty selected `creditId` produce exact native -32600 messages before any corresponding HTTP POST. |
| No account | Both methods return their exact native account-authentication errors, with zero POSTs. |
| API-only account | Both methods return their exact native ChatGPT-authentication errors, with zero POSTs. |
| Malformed native parameters | Six missing/wrong-type/wrong-enum cases first fail client schema validation without dispatch. Explicit `validation: :wire` independently reaches the native parser and gets -32600 `Invalid request:` with correlated response ID; zero POSTs. |
| POST ambiguity | Backend receives one consume POST and holds its response. A 1s local driver deadline returns `deadline_exceeded`, `uncertain: true`. Explicit fixture release produces the real native late `reset` result. Uncertainty remains recorded and request count stays one; no retry or automatic reconciliation occurs. |

The success loop intentionally forwards the same synthetic key twice to observe
different configured backend outcomes. This proves forwarding, not backend
idempotency. The ambiguity case does not assert rollback or cessation from local
timeout. Real service reconciliation is outside this synthetic profile.

Native credit error rendering interpolates backend errors; this unit does not
claim universal credential redaction for arbitrary backend error bodies. All
responses and error canaries are synthetic. Nudge's native field names are
camelCase, but its enum values are snake_case: `usage_limit` and
`cooldown_active` are deliberate pinned spellings.

## Checks and limitations

Source-only checks passed: Python 3.10 AST parsing without importing the
fixture, fixed-method/one-native-process source assertions, and newline/trailing
whitespace checks on all three owned files. After exclusive runtime ownership was
granted, the namespace preflight, scoped formatter, standalone test-environment
compile, both native seeds and positional root strict Credo passed. These are
selected Linux synthetic-backend results, not complete account-service acceptance.

Required local prerequisites: Linux user/network namespaces, `unshare`, `ip`,
Python 3, exact pinned executable, and the independent driver's verified Elixir
environment. Unavailable prerequisites must fail as BLOCKED_ENV. Do not weaken
namespace checks or run on shared/production resources.

The following commands ran serially through `devenv shell --no-tui -- bash -c`;
driver commands use `cd apps/samgita_codex_driver` first and `MIX_ENV=test`:

```sh
mix format test/native_account_control_profile.exs
mix compile --warnings-as-errors
CODEX_BINARY=/absolute/path/to/pinned/codex mix test test/native_account_control_profile.exs --seed 501432
CODEX_BINARY=/absolute/path/to/pinned/codex mix test test/native_account_control_profile.exs --seed 987654
```

The actual CODEX_BINARY was
`/home/gao/Workspace/gsmlg-opt/Samgita/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl`;
its digest matched the pin. From repository root,
`python3 scripts/codex/check_namespace_prerequisites.py` passed with changed user
and network namespaces, loopback UP and no IPv4/IPv6 default routes.
`MIX_ENV=test mix credo --strict apps/samgita_codex_driver/test/native_account_control_profile.exs`
checked exactly one file with 69 checks and found no issues. A scoped final
`mix format --check-formatted test/native_account_control_profile.exs` passed;
the second repair's formatting and standalone compile also passed.

Initial seed 501432 exposed one observation race (11 tests, one failure): the
asynchronously forwarded `initialized` notification changed the input count
between a malformed request's baseline and no-dispatch assertion. Repair one
added an explicit fixture-observation barrier for that handshake notification;
both seeds then passed 11/0. Strict Credo found the existing combined proof
helper's complexity 10 against maximum 9. Repair two extracted the unchanged
POST-proof loop into a helper. No timeout, no-retry rule, header/body assertion
or cleanup check was weakened. The final code passed both complete seeds again.
Cumulative Sol repair rounds: 2; Astra rounds: 0.

Final native evidence logs are
`/tmp/samgita-account-control-501432-final.log` (11/0, 20.9s),
`/tmp/samgita-account-control-987654-final.log` (11/0, 22.6s),
`/tmp/samgita-account-control-credo-repair2.log`, and
`/tmp/samgita-account-control-repair2-format-compile.log`.
Earlier failure evidence is retained in
`/tmp/samgita-account-control-501432-initial.log` and
`/tmp/samgita-account-control-credo-initial.log`; the successful intermediate
seeds are `/tmp/samgita-account-control-{501432,987654}-repair1.log`.

Final fixture SHA256:
`6a5348d05351969f987b4eb2019b203305ea2a3a74402b0898767b10446772e4`.
Final native profile SHA256:
`8e593f939ca260532c82a0220141606928ef5fc2c156202c43fd6783fa3e4948`.
The final runs checked exact HTTP count/path/body/header proofs, no unexpected
HTTP/native operations, no loaded threads or server interactions, synthetic-secret
absence in journals/stderr, and teardown/reaping of every owned controller,
native process and namespace owner. No shared manifest/workflow or Git change was
made by this unit's owner.

Parent owns aggregate integration, manifest/field promotions, workflow
installation, Git and publication. This `.exs` profile is explicitly invoked;
adding it does not place it in default `_test.exs` discovery.

Uncovered here: native 10s consume timeout, transport disconnect during a POST,
real service reset/deduplication/cooldown/email behavior, real credentials,
non-Linux/native deployment profiles and all gateway/verification families.

| Check | Result |
| --- | --- |
| Python AST/static assertions | PASS: Python 3.10 AST; bounded-method/one-native-process and file-whitespace assertions |
| Namespace preflight | PASS: private user/network namespaces, only loopback, no IPv4/IPv6 default routes |
| Scoped formatter | PASS: formatted and final scoped check |
| Standalone compile | PASS: test environment, warnings as errors |
| Native account-control profile | PASS: final seed 501432, 11 tests, 0 failures |
| Repeated native seed | PASS: final seed 987654, 11 tests, 0 failures |
| Root strict Credo | PASS: one owned test file, 69 checks, no issues |
| Integrated gates | Parent-owned; no claim |
