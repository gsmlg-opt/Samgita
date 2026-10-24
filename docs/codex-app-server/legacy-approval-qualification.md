# Legacy approval reachability and qualification

The complete target still includes `applyPatchApproval` and
`execCommandApproval`. The pinned source retains their wire contracts, but this
investigation found no production path that emits either request in
`rust-v0.163.0`. Synthetic acceptance of their messages does not establish an
enabled interaction with the real executable. Neither family is excluded or
fully qualified by this finding.

The manifest now records the two `server_request` entries and their two
`client_response` entries as **blocked**, rather than missing: the concrete
enabled-success prerequisite is an absent production emitter in the immutable
target. All four remain required and fail completeness. Their schema contracts
retain missing status where local parameter/variant qualification remains to be
completed; source unreachability does not erase that independent work.

## Exact target and source evidence

Upstream source commit: `83086188ae0614bd882818ff1aa23f3194962012`.
The Linux x86_64 musl binary used by this repository has SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
References below are relative to that commit's `codex-rs/` directory, available
locally under `tmp/codex/0.163.0/codex-<commit>/codex-rs/`.

Reviewable upstream anchors are the immutable
[legacy declarations](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/common.rs#L1850-L1863),
[initialization capabilities](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v1.rs#L46-L73),
[production v2 approval dispatch](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/bespoke_event_handling.rs#L642-L808)
and [test-only legacy construction](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/outgoing_message.rs#L1486).
The table and whole-source search below distinguish retained schemas from actual
production emitters; successful synthetic handler tests do not bridge that gap.

| Source | Finding |
| --- | --- |
| `app-server-protocol/src/protocol/common.rs:1850-1863` | Both legacy server requests remain declared. Comments attribute them to `SendUserTurn` and `SendUserMessage`. |
| `app-server-protocol/src/protocol/v1.rs:46-73` | Initialize capabilities have no API-version selector or legacy approval switch. |
| `app-server-protocol/src/protocol/v1.rs:143-179` | Legacy parameters and their `ReviewDecision` responses remain declared. |
| `app-server/src/message_processor.rs:112-116` | Unknown client enum variants become invalid-request errors. The removed legacy turn methods have no dispatcher arms. |
| `app-server/src/request_processors/thread_lifecycle.rs:379` | Thread events always enter the shared bespoke event handler. |
| `app-server/src/bespoke_event_handling.rs:642-657` | Patch approval events emit `item/fileChange/requestApproval`. |
| `app-server/src/bespoke_event_handling.rs:671-808` | Command approval events emit `item/commandExecution/requestApproval`. |
| `app-server/src/outgoing_message.rs:918,1486` | The sole app-server construction of `ServerRequestPayload::ApplyPatchApproval` is in a `#[cfg(test)]` module. No `ExecCommandApproval` production construction exists. |

The names `SendUserTurn` and `SendUserMessage` occur only in those protocol
comments within the app-server and app-server-protocol Rust sources. The
comments do not provide an executable legacy API. Enabling experimental APIs
does not select a different approval handler. This is a source reachability
finding, not a claim that every possible upstream platform/profile was run.

## Retained decision and parameter contracts

Both legacy responses wrap a `ReviewDecision` in `{"decision": ...}`. The
decision alternatives are:

```json
"approved"
"approved_for_session"
"approved_mcp_policy_amendment"
"timed_out"
"abort"
{"approved_execpolicy_amendment":{"proposed_execpolicy_amendment":["printf"]}}
{"network_policy_amendment":{"network_policy_amendment":{"action":"allow","host":"fixture.invalid"}}}
{"denied":{"rejection":"Synthetic rejection"}}
```

Network policy action also permits `deny`. These spellings differ from the v2
decisions `accept`, `acceptForSession`, `decline` and `cancel`. The authoritative
definition is `protocol/src/protocol.rs:4258-4292`; the unchanged shipped
`ApplyPatchApprovalResponse.json` and `ExecCommandApprovalResponse.json` expose
the same alternatives.

Legacy requests correlate using `conversationId` and `callId`; command requests
can also have `approvalId`. Patch requests carry `fileChanges` with add, delete
and update variants. Command requests carry an argument vector, `cwd` and
`parsedCmd` variants. The driver must preserve these fields, including missing
versus null, instead of rewriting the request into a v2 message.

## Executable evidence and its limits

`apps/samgita_codex_driver/test/legacy_approval_contract_test.exs` adds:

- Clearly labelled synthetic Session scenarios for both request families,
  stable and experimental initialization, all eight decision alternatives
  (both network actions), typed request IDs and exact payload preservation.
- Add/delete/update patch changes; all four parsed command variants; optional
  fields omitted, null and present.
- Rejection of malformed decisions without consuming the pending request,
  duplicate reply rejection and stale handles after reconnect/ID reuse.
- Two real-binary tests sending removed `sendUserTurn` and `sendUserMessage`
  methods directly over stdio after stable or experimental initialization.
  These require upstream invalid-request errors naming the unknown variant and
  verify the same initialized connection still serves `thread/list`.

The negative binary tests use raw transport deliberately: client schema
validation must not intercept the request and be mistaken for upstream
rejection. They require an explicit `CODEX_BINARY` pointing at the pinned
executable, isolated disposable HOME/CODEX_HOME, and no model calls or real
credentials. Existing `server_interactions_test.exs` exercises actual v2 patch
and command approval flows using the real executable and a synthetic model
backend. Those tests are separate from legacy enabled-success evidence.

Run from `apps/samgita_codex_driver/`, using the verified Elixir/OTP environment:

```sh
CODEX_BINARY=/absolute/path/to/pinned/codex mix test test/legacy_approval_contract_test.exs
mix format --check-formatted test/legacy_approval_contract_test.exs
```

Local execution against the binary hash above passed: **6 tests, 0 failures**
(ExUnit seed `476574`). This includes both real-binary negative tests and four
synthetic contract/lifecycle tests. Scoped formatting and
`mix format --check-formatted test/legacy_approval_contract_test.exs` passed in
the same Devenv invocation. Command output is retained locally at
`/tmp/samgita-legacy-approval-tests.log`. These are scoped local results; they do
not establish hosted acceptance or enabled legacy approval success.

## Local contract index

A later source-only audit indexes **52 previously missing property/literal
contracts** from these unchanged tests: 15 under `ApplyPatchApprovalParams`, 24
under `ExecCommandApprovalParams`, 12 under the canonical shared `ReviewDecision`/
`ApplyPatchApprovalResponse` and one under `ExecCommandApprovalResponse`.
Each gains scoped `implemented` evidence only, explicitly labelled **synthetic
codec/Session**. All four legacy method requirements remain **blocked** and
there are **zero fully verified promotions**.

The test at 30–58 round-trips each constructed request and preserves the exact
server-request envelope at 237–241. Session validates the method-specific request
before enqueueing it. Explicit replies at 43–45 retain the exact result after
method-specific response validation. Optional presence tests at 60–78 cover only
`grantRoot` and `approvalId` across omitted/null/present. Other fields retain
their concrete tested-value limits. The 15 whole union containers, untested
optional/null alternatives and four previously indexed network members are
excluded from this supplemental index. No filesystem execution or policy effect
is established.

The exact candidate IDs, physical pointers, node hashes, construction/assertion
ranges and exclusions are in
`/tmp/samgita-legacy-approval-local-contract-candidates-20261024.json`, SHA256
`71dc4920665cca8608fd09c3ae12227accbd2b49d647dcda9c486426b9a8dc7a`.
Test SHA256 is
`d6bdbff4eb80baaca11292246eb9860f29f122e6fa9b6e37ea5b8042875b3761`;
it matches both complete 663-case driver repeats in the
[frozen 7a5de5e matrix](repair-qualification.md#frozen-local-matrix-at-7a5de5e).
This is indexing of existing assertions, not a new native legacy success run.
The two actual-binary tests still establish removed-method rejection only.

## Remaining acceptance requirement

Enabled legacy approval success remains unverified. Credentials and a different
Linux fixture cannot supply the missing production emission path identified
above. An older or modified Codex build would test a different target. Do not
fabricate a server, change the immutable pin, relabel contract tests as real
interactions or remove these entries to make completeness pass. Preserve the
unmet requirement in the full compatibility ledger until an explicit target or
evidence-policy decision resolves the conflict between retained advertised
schemas and unavailable runtime behavior.
