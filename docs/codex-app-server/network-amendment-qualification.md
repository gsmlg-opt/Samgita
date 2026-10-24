# Native managed-network approval amendments

Selected Linux behavior is implemented against stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. Binary SHA256 is
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`;
bundled bwrap SHA256 is
`77360cb751ccedc5971391444ac86a8a33c15b04d6b4a6fe45f5d25496e62c4c`.
This is actual native behavior with synthetic local dependencies. It is not
full approval, external-service, legacy-protocol or security qualification.

## Production emitter and effects

The native managed proxy invokes its policy decider for an unknown host.
`core/src/tools/network_approval.rs:740-948` constructs
`ApprovalAction::NetworkAccess` and calls `session.request_approval`.
`app-server/src/bespoke_event_handling.rs:665-820` emits production
`item/commandExecution/requestApproval`, with the exact host/HTTP context,
proposed allow/deny amendments and correlated thread/turn. Its command, cwd and
commandActions values are null. The typed network amendment response is handled
at `bespoke_event_handling.rs:1973-2043`; native persists the matching rule and
updates proxy policy. No app-server frame is synthesized by the fixture.

Each of the two tests explicitly answers its own actual native handle. Allow
reaches only the owned origin and reports successful tool output. Deny returns
native rejection with no origin hit. The exact host/action rule persists without
an execpolicy prefix. A second same-host turn reuses that rule, requests no
approval and produces the same bounded allow/deny effect. Both turns finish,
and Session has no pending interaction. The provider records four requests per
case; it supplies a fixed tool command and a final tool-free response, never an
app-server approval or result.

## Isolation and cleanup

Stock managed proxy configuration requires `/etc/codex/requirements.toml`;
the environment override is debug-only. The fixture proves private user, mount
and network namespace identities before making child mounts private, mounting
tmpfs over child `/etc`, and read-only binding its synthetic requirements.
It never writes host `/etc`. There is only loopback, with no IPv4/IPv6 default
route. The owned provider uses `127.0.0.2`; the unknown owned origin uses
`127.0.0.3`. Native sandbox configuration permits its proxy's actual HTTP
listener (`network-proxy/src/network_policy.rs:364-417`). A fixed command proves
direct origin access is blocked, then uses native HTTP_PROXY. No public route,
DNS name, upstream proxy, real credential, arbitrary tool, paid inference,
debug override or weakened native sandbox is involved.

Both Python invocations use isolated mode. Peers track sockets/workers and poll
at 0.02 seconds. One unchanged 0.75-second cleanup deadline covers peer shutdown,
native TERM/KILL, leader reap and adopted-child reap. Native stderr is drained;
only its first 65,536 bytes are retained, with truncation metadata. Startup
failure reports bounded diagnostics. `closed.json` and the test assert zero
sockets, workers and children, a reaped leader, absent owned group and elapsed
cleanup within the budget. Only the owned native process group is signaled.

The first two cases passed all behavior assertions but failed cleanup: four
adopted children per case were zombies in bwrap-created process groups. Native
bwrap uses `--new-session`/`--die-with-parent` at
`linux-sandbox/src/bwrap.rs:289-290,361-362`; the wrapper also changes process
group at `linux-sandbox/src/linux_run_main.rs:607`. Reaping only the app-server
PGID missed these exited children. Diagnostic logs preserve state `Z`, parent,
group/session and native-group absence; they do not classify a live escaped
process as harmless.

The fixture now retains the native leader through the final group signal with
`waitid(WNOWAIT)`, preventing reuse of its owned PGID, then reaps explicitly
enumerated actual children regardless of group. It sends no extra group signals.
Live escaped children still fail under the same deadline. The previously
qualified production Stdio cleanup implementation and assertions are unchanged.

## Commands and results, 2026-10-24

The mount-only prerequisite proved read-only private requirements and loopback
isolation before full native execution. Both initial and diagnostic profiles
reported **2 tests / 2 cleanup failures**; logs remain
`/tmp/samgita-network-amendment-501432-20261024.log` and
`/tmp/samgita-network-amendment-diagnosis-501432-20261024.log`.

After the fixture correction:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-single-native-unit-validation-20261024.py network-amendment-final native_network_amendment_profile.exs isolated_network_amendment_fixture.py
# Driver package, CODEX_BINARY set to the immutable artifact:
mix test test/native_network_amendment_profile.exs --seed 501432
mix test test/native_network_amendment_profile.exs --seed 987654
```

Both final native runs passed **2 tests / 0 failures**, 3.9 seconds each.
Python AST, namespace prerequisite, warnings-as-errors compilation, formatting
and scoped strict Credo also passed. Logs use
`/tmp/samgita-network-amendment-final-*-20261024.log`. CI explicitly selects the
profile and fails if namespace/mount/sandbox prerequisites are unavailable.
Final aggregate and hosted outcomes are separate gates.

## Expanded decisions and edits

Eight further cases retain the original two and exercise these exact native
branches:

| Decision/context | Observed result |
| --- | --- |
| Plain accept | One owned-origin success, no rule; the next original-host request prompts and is explicitly declined. |
| acceptForSession | Two owned-origin successes with one approval and no persistent rule. |
| Equivalent edited `" 127.0.0.3. "` allow | Only the canonical original-host rule persists; two successful turns, one approval. |
| Different-host allow | Exact mismatch warning, no rule/effect; a later original-host request prompts again. |
| Different-host deny | Exact mismatch warning, no rule/effect; the original host remains denied by the session cache without another prompt. |
| Explicit JSON-RPC error | Native reports approval failure with no access/rule; the next original-host request prompts. |
| Decline | Turn completes with rejection and no access/rule/session grant; the next request prompts. |
| Cancel | Turn is interrupted, with one provider request and no access/rule. A separately explicit next turn prompts and is declined. |

The mismatched host exists only in the typed response; no command connects to
it. Native host normalization and equality checks are at
`core/src/session/mod.rs:2811-2889`; allow/deny mismatch cache behavior is
asymmetric at `core/src/tools/network_approval.rs:921-1018`. Tests preserve that
observed distinction rather than imposing symmetric rejection. Exact per-marker
provider counts, stale-handle rejection, terminal status, no pending state and
zero owned-origin effect are asserted. Original approval-context and cleanup
checks remain unchanged; the Python fixture is unchanged.

Both five-case intermediate runs passed **5/0**, 9.7/9.8 seconds. Both expanded
ten-case runs passed **10/0**, 18.8/18.7 seconds, then strict Credo rejected a
nine-parameter test helper. Grouping the expected approval/terminal pair into
one tuple retains all assertions and deadlines. The final ten-case block again
passes both seeds, **10/0**, 18.6/19.5 seconds, with compile, format and strict
Credo; logs are `/tmp/samgita-network-negative-final-*-20261024.log`.

Thirteen exact positive field/variant contracts gain scoped `implemented`
evidence. Shared canonical NetworkPolicyAmendment definitions describe the typed
v2 decision exercised here; they do not imply legacy ApplyPatchApproval runtime
acceptance. Existing decision contracts gain the expanded selected evidence;
no entry becomes fully verified. Cross-context edits, lost replies, native
cold-restart policy persistence, other network protocols and legacy approval
methods still require separate evidence. See
[legacy reachability](legacy-approval-qualification.md); this v2
request must never be rewritten to counterfeit a legacy emission. A11 and the
remaining external/OS/full-compatibility gates remain incomplete.
