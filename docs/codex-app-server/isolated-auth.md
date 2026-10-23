# Isolated synthetic authentication profile

This profile exercises the immutable Codex `rust-v0.163.0` native authentication
implementation through `SamgitaCodexDriver.Session`. Its OAuth issuer and backend
are an owned loopback fixture. It does not establish authentication against a real
OpenAI account, live provider integration, other operating systems, or deployment.

Run explicitly from `apps/samgita_codex_driver`, in the verified Elixir environment:

```sh
MIX_ENV=test CODEX_BINARY=/absolute/path/to/pinned/codex \
  mix test test/native_auth_flow_profile.exs --seed 501432
```

The file deliberately does not match the default `*_test.exs` discovery pattern.
Independent consumers and ordinary driver tests need no Linux namespace tools.
This profile must be invoked separately on a supported Linux runner; default-suite
success does not qualify it. Missing tools, denied namespaces, startup failure or
an unexpected route fail the profile. There is no skip or host-network fallback.

`scripts/codex/isolated_auth_fixture.py` starts a private user and network namespace
with `unshare --user --map-root-user --net --fork --kill-child=TERM`. It enables only
loopback and verifies a distinct network namespace, exactly one `lo` interface,
and no default or non-loopback route before starting any fixture or Codex process.
The fixture, callback controller and native process share that namespace. Native
JSONL messages pass unchanged over the owned stdio transport. Only the fixture's
allowlisted observations use its atomic journal. All processes and credentials
belong to a disposable test root; no host callbacks, live secrets or model calls
are used.

The browser scenario parses the native `authUrl`, verifies its owned issuer and
callback destination, observes rejection of an incorrect state, then follows the
actual native callback/token-exchange/local-success-page path. The fixture checks
the native PKCE verifier against its advertised challenge. Device scenarios use
the native user-code and polling pipeline. Cancellation waits for an observed
held device poll and cancels the actual native login; a fixture barrier releases
the held response only after the native cancellation receipt. Other cases cover
disabled device login and polling failure. Success must come from native
`account/login/completed`, `account/updated`, persisted credentials and cold reads.
No fixture scripts a native success response or notification. Explicit close and
session-owner death must reap the native process, controller and namespace owner.
The existing stdio owner retains its process-group identity, signals that owned
group and reaps orphaned descendants before acknowledging cleanup. The controller
forwards termination to its native child and waits for it before fixture cleanup;
the namespace owner sends TERM on its exit. Journal assertions exclude synthetic
token and credential canaries.

The production-source controls are:

| Control | Pinned source and use |
| --- | --- |
| `CODEX_APP_SERVER_LOGIN_ISSUER` | `app-server/src/request_processors/account_processor.rs:36,618`; release-supported issuer for browser and device login. |
| `CODEX_APP_SERVER_LOGIN_CLIENT_ID` | `login/src/auth/manager.rs:216,1721`; synthetic client ID. |
| `CODEX_REFRESH_TOKEN_URL_OVERRIDE` | `login/src/auth/manager.rs:214,1728`; pins managed refresh to the owned issuer. |
| `CODEX_REVOKE_TOKEN_URL_OVERRIDE` | `login/src/auth/manager.rs:215` and `auth/revoke.rs:134`; pins logout revocation to the owned issuer. |
| `chatgpt_base_url` and provider URL | Pins configuration, workspace routing and provider destinations to the owned backend. Plugins and recommended plugins are disabled; the model catalog is local. |

The app-server sets `open_browser: false`. Its login constructor fixes callback
port `1455`, with fallback `1457`; no app-server callback-port override exists in
that production construction path. On collision, `login/src/server.rs:637` may
send `/cancel` to a previous listener. The private network namespace is therefore
required for browser qualification. The debug-only
`CODEX_APP_SERVER_DEV_OPEN_APP_URL` is not used by this release-binary profile.

Sources are commit `83086188ae0614bd882818ff1aa23f3194962012`:
`login/src/device_code_auth.rs:165-236`, `login/src/server.rs:178-320,365-533`,
`app-server/src/request_processors/account_processor.rs:656-835,967-990`.
Official analogous native tests are in
`app-server/tests/suite/v2/account.rs:2194,2548,2627,2688`; cloud/backend fixture
contracts are in `app-server/tests/common/test_app_server.rs:1991-2027`.

The initial namespace prerequisite probe passed locally with a distinct namespace,
only loopback routes, and clean exit. The explicit profile then exercised seven
actual-binary cases: browser success and cancellation, device success and
cancellation, device polling failure, disabled device login, and session-owner
death during login. Its first run had one fixture assertion failure: an
independently spawned cold-start `account/updated` snapshot could precede logout's
update. Pinned `account_processor/workspace_routing.rs:149-181` spawns that startup
update, while `account_processor.rs:1080` sends logout's update. The assertion now
retains both observations and requires the actual null-auth logout update without
inventing an ordering between those tasks. No runtime behavior, timeout or process
cleanup was changed to repair that assertion.

Final local validation used the binary with SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`:

```sh
devenv shell --no-tui -- env MIX_ENV=test \
  CODEX_BINARY="$PWD/tmp/codex/0.163.0/codex-x86_64-unknown-linux-musl" \
  sh -c 'cd apps/samgita_codex_driver &&
    mix format test/native_auth_flow_profile.exs &&
    mix compile --warnings-as-errors &&
    mix test test/native_auth_flow_profile.exs --seed 501432 &&
    mix test test/native_auth_flow_profile.exs --seed 987654'
```

Formatting and compilation passed; each seed passed **7 tests, 0 failures**.
The final log is `/tmp/samgita-native-auth-flow-final.log`; the initial failure is
retained in `/tmp/samgita-native-auth-flow-initial.log`. This qualifies this local
synthetic-backend native profile. Live identity verification, real managed
credentials, production keyrings and other platform profiles remain unverified.
