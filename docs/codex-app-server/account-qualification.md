# Native local account state and credential boundaries

Eight actual-binary cases in
`apps/samgita_codex_driver/test/native_account_state_test.exs` cover local account
state in immutable Codex `rust-v0.163.0`. Credentials are synthetic canaries;
all configured destinations remain an owned loopback fixture, plugin sync is
disabled, and every case requires zero model requests and zero loaded threads.
This is not acceptance of a real account, token service or paid provider.

The selected behavior includes:

- Unauthenticated account/default/refresh reads expose explicit absence.
  Idempotent logout with omitted and null params emits exact account updates.
- API-key login and replacement persist in the isolated file store with `0600`
  permissions. A new native process reads the same state; logout removes it and
  remains effective after another restart, without remote OAuth revocation.
- V2 account/login/read results, notifications and ordinary status hide the
  canary. Legacy `getAuthStatus` intentionally exports an API key only when
  `includeToken: true`; missing/null/false retain redacted results. Consumers must
  handle that explicit native response as sensitive data. Neither driver logging
  nor Samgita safe metadata may expose it.
- Missing/malformed login cancellation IDs preserve existing credentials and
  return exact not-found/validation errors. A forced API policy rejects browser,
  device-code and external-token modes before starting them; a forced ChatGPT
  policy rejects API-key login. Malformed external JWTs preserve prior API state.
- A provider declaring no OpenAI authentication suppresses both account and
  legacy token exports according to native behavior.

The initial run passed six of eight cases; two fixtures supplied `{}` to logout,
which the official protocol defines as omitted/null (`Option<()>`). Correcting
the fixtures tests both supported forms without disabling schema validation.
All **8 tests passed** at each seed `501432` and `987654`, with compilation
warnings as errors, formatting and whitespace checks. Logs:
`/tmp/samgita-native-account-state-{initial,repair-1}.log`.

Source evidence, relative to the immutable commit's `codex-rs/`:

- `app-server/src/request_processors/account_processor.rs:442,482,585,818,856,1080,1118`:
  API login, policy validation, cancellation, logout, account and auth-status APIs.
- `app-server-protocol/src/protocol/common.rs:1335,3544`: unit logout parameters
  and serialization that omits them.
- `login/src/auth/manager.rs:1022,1733,2845,2956` and
  `model-provider/src/provider.rs:510`: local persistence and provider behavior.
- `login/src/auth/revoke.rs:55,68,80`: API-key logout has no OAuth revocation token.
- `login/src/server.rs:178,637`: browser startup owns a fixed default listener;
  address collision handling may send `/cancel` to an existing listener on
  port `1455` before trying a fallback.

Positive browser/device-code login is deliberately not initiated on this shared
host. It needs an owned isolated network namespace/ports and an approved local
auth fixture or separately authorized real-service profile. Otherwise the
native collision handler could cancel someone else's flow. External-token
success may reload cloud configuration and contact a backend; local JWT parsing
alone cannot certify it. Those positive profiles, cancellation of an active flow,
managed refresh/revocation/routing and other deployment profiles remain
unverified. No mock, schema-only test or successful malformed-token rejection
is counted as those successes. The five method entries and two notifications
have selected implementation evidence with these limits.
