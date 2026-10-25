# Native history, voices and badRequest

Status: scoped implementation evidence; **full compatibility remains incomplete**.
Nine added actual-native cases pass within the complete nine-file owning block:
**89 tests / zero failures** at seeds 501432 and 987654, with no excluded cases.
The immutable target is `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Samgita driver code, permissions, process cleanup and existing deadlines are
unchanged. The only provider-fixture addition is a prescribed HTTP 400 response.

## Supplied history

Six cases in `native_default_gates_profile.exs` import independently prescribed
records through the real `thread/resume` operation. Each verifies the exact
outbound request, newly allocated native identity, full durable JSONL payloads
and order, no inference before an explicit turn, exactly one subsequent provider
request, and unchanged history after confirmed owned restart/cold read. The
provider is synthetic; the app-server and its storage/normalization are stock.

| Case | Selected physical owners | Observable scope |
| --- | --- | --- |
| Function/custom pairs, plain and structured output | 33 | Exact call IDs, names/namespaces, raw arguments/input, completed status and ordered string or text-array results |
| Search actions | 24 | Completed historical search/open_page/find_in_page/other, including query/queries/url/pattern |
| Local shell | 16 | Completed historical Exec command, timeout, cwd, env and user, paired with a separately prescribed historical output |
| Additional tools and client tool search | 22 | Exact nested declaration/argument JSON and matched historical search call/output |
| Message phase/status | 9 | Exact commentary/partial_answer/final_answer classifications and opaque completed message status |

All provider items sharing each selected call ID must equal the complete
prescribed pair, including items with unknown IDs. Known-ID-only filtering would
miss a synthesized extra result. Historical tool names/declarations are absent
from active top-level provider tools; their historical content remains visible
in model input. No live tool registration, discovery, execution, search or URL
access is qualified by historical retention.

The local-shell proposal was corrected during source review, before runtime:
pinned [normalize.rs:113–141](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/context_manager/normalize.rs#L113-L141)
synthesizes an aborted output for an unmatched LocalShellCall. The final case
supplies the matching historical output and rejects any extra same-call-ID item.
This is a source-oracle correction, not a demonstrated native defect or repair.
Five absent-sentinel checks complement no-work/events/provider assertions;
read-only policy could block an attempted write, so absence alone cannot prove
that no process was ever attempted. Phase/status retention likewise proves no
provider-generated classification, actual completion or platform Task acceptance.

## Realtime selection

Two cases in `native_realtime_lifecycle_profile.exs` select 17 explicit V1/V2
voices and 16 V3-exclusive voices, plus omitted/null V3 defaults. Every owned
session checks the captured native handshake URL/version/session identity and
exact outbound voice selection. Explicit stop, peer-close observation and the
existing barrier precede the next session; there are no error/server-request
events, duplicate updates, pending requests or uncertainty.

Thirty-three new explicit leaves plus two existing explicit cove/cedar leaves
gain 35 physical `ClientRequest.json` input contracts. Cove is bound only to its
existing V1/V3 WebRTC assertions in `native_realtime_sdp_profile.exs`; cedar is
bound only to the explicit V2 lifecycle case. Omitted/null defaults do not prove
explicit enum-input ownership. No sibling enum or transport inherits evidence.

Both 17/18-session tests pass with the unchanged 60,000ms test and 10,000ms helper
deadlines. The generic lifecycle fixture has a private home and loopback peer;
it does not inherit the separate SDP fixture's network-namespace guarantees.
Captured selection is not audible synthesis, voice quality, live OpenAI service
acceptance, real credentials, universal WebRTC support or other OS qualification.

## Native badRequest

The added `http-400-invalid-image` case in `native_provider_errors_test.exs`
receives a prescribed HTTP 400 body whose exact invalid-image sentence reaches
the pinned native InvalidImageRequest classification. It checks the captured
HTTP status/URL, exact `badRequest` error, failed turn/history, one initial
provider request and no retry or implicit continuation. One caller-authorized
next turn succeeds. A generic HTTP 400 would not prove this classification.
Only one physical `ServerNotification.json` CodexErrorInfo enum leaf gains
evidence; real image validation, provider authentication and the whole error
union remain unqualified. No production emitter is manufactured for retained
ResponseStreamFailed or legacy ThreadRollbackFailed variants.

## Verification and mapping

The exact runner is
`devenv shell --no-tui -- python3 -B /tmp/samgita-native-history-voices-v25-20261025.py`.
It runs namespace/sandbox prerequisites, warning-free compile, format check,
both native seeds and strict Credo, then checks every one of the 1,495 guarded source files
and executable again. The nine files are default gates; realtime lifecycle,
SDP and BEM; provider errors; session budget; Apps metadata/catalog; and account
metadata. Both native commands pass in 151.855/151.199 seconds respectively.

Source-only review and parent preflight checked 53 original source preimages,
14 proposal artifacts, every full original owner row and canonical schema node.
The 140 owners are unique and disjoint from the preceding 50 retained owners.
The final manifest matches the complete expected JSON, with exactly 140 changed
contract rows and every other section unchanged. Requirements remain
462 implemented/12 missing/11 blocked; contracts become 3,781 implemented/2,840
missing; **zero are verified**.

Artifacts and exact source/log hashes:

- `/tmp/samgita-v25-140-owner-source-review-20261025.json`, SHA256
  `8afa33d6b6efde4de4aa0fc027b75e2483d28ce2f472cb485e8d4081684be0c3`.
- `/tmp/samgita-native-history-voices-v25-20261025/`, including source snapshot,
  commands, exits and complete logs.
- `/tmp/samgita-v25-140-owner-terminal-20261025.json`, SHA256
  `37b20570987d1c792ccef9e5a1a4f6947c6876d14f8ced1fc1e073100a705c97`.
- `/tmp/samgita-v25-140-owner-bound-20261025-index.json`, exact selected pointers,
  node hashes, nominated tests and final runtime test hashes.

Complete final-source local/hosted qualification remains required after the next
scoped integration. A11, unreachable production emitters, external/backend/OS
success and retained aggregate failures stay incomplete. No publication, tag,
deployment, sibling-service edit, production task or database migration occurs.
