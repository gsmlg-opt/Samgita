# Selected native approval and permission decisions

These checks use immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, with a loopback deterministic
Responses provider. They qualify observed decisions, native history and local
synthetic effects on Linux/stdio. They do not qualify every approval variant,
external account, general sandbox enforcement or Task acceptance.

`apps/samgita_codex_driver/test/approval_decision_variants_test.exs` adds eight
actual-binary scenarios to the retained interaction suites:

| Decision | Required observed outcome |
| --- | --- |
| Command `accept` | The exact synthetic `printf` completes once, writes no policy rule and requires a fresh approval on the next matching command. The old handle cannot decide that new request; explicit decline yields no command output. |
| `acceptWithExecpolicyAmendment` | The exact selected `["printf"]` rule is written. A confirmed process shutdown, new process and new thread execute the matching synthetic command without another approval; the rule and native history remain exact. |
| Command RPC error | Native command item fails with no output or exit code; no rule is created. |
| File-change RPC error | The exact requested synthetic patch is declined and the target file remains absent. |
| Permission response with omitted scope | The normalized output grants only the requested directory with `scope: "turn"`. |
| Excess directory/network grant | Unrequested sibling-write and network permissions are removed from the normalized grant; synthetic workspaces remain unchanged. |
| Session scope plus `strictAutoReview: true` | The server fails closed to an empty turn-scoped grant. |
| Permission RPC error | The provider receives an empty turn-scoped grant. |

Every interaction retains native thread/turn/item IDs, a fresh generation-bound
handle and its original requested action. Completion collection rejects new
unanswered interactions and verifies persisted turn history. The permission
normalization cases do not attempt unauthorized writes or network calls and
therefore do not establish operating-system enforcement. Pinned
`app-server/src/bespoke_event_handling.rs:1860–1918` and
`core/src/session/mod.rs:3330–3399` define the permission response boundary.

The fixture omits an explicit shell. Pinned command construction consequently
selects the account's shell; the test parses its exact argv, requires an existing
absolute POSIX shell and preserves the exact `printf` payload, cwd and proposed
rule checks. A private fixture-shell expectation was incorrect and was repaired
in the assertion rather than by changing Codex or weakening the requested action.

The eight cases passed at seeds `501432` and `501433`, with scoped compilation
and formatting. Logs:
`/tmp/samgita-driver-approval-variants-astra1-{501432,501433}.log`.
The full driver and hosted checks are recorded separately in
[qualification](qualification.md). Legacy approval wire contracts have a
different, source-proven production reachability blocker documented in
[legacy approval qualification](legacy-approval-qualification.md); scripted
messages are not substituted for that missing enabled-success acceptance.
