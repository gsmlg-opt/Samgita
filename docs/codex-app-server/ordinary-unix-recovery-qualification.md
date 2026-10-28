# Native Unix socket recovery and lost replies

This functional continuation follows `f9032d8b977b0b6f95246b5a4ce042efc0f409e2`
on the existing `main`. It targets stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, combined executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
YOLO is fixed launch configuration. No security, credentials, authentication,
authorization, approval, sandbox or permission behavior is tested. Existing
checks and required gates remain intact; mixed broad/hosted checks stay unrun.

## Actual native flow

The existing ordinary WebSocket gap module now executes three isolated cases:
the retained TCP case, an acknowledged Unix socket case, and a Unix socket case
with one intentionally withheld native `turn/start` reply. The stock server,
rather than a scripted app-server peer, produces every protocol frame. The
unchanged local Responses fixture supplies only model SSE and a bounded control
barrier. Each case has its own random root, provider and native listener.

Both transport generations must report their actual transport kind and borrowed
process ownership. UDS uses `unix://<owned-root>/codex.sock`, the public
`UnixSocket` client and the default `/app-server` WebSocket endpoint. A bounded
local connection establishes listener readiness. Reconnect and borrowed-client
close preserve the socket and native process; only explicit owner shutdown
reaps that process. No daemon-shutdown request or service resource is used.

The acknowledged cases retain the entire original flow and assertions: observe
one exact native Unicode delta and held provider response, receive the explicit
unsubscribe reply, reconnect, initialize again, and release the provider. Global
idle is the completion barrier while scoped turn/item/delta notices stay absent
on generation two. Explicit read/resume/read returns the original completed
paginated turn. History does not clear the visible connection gap or fabricate
replayed deltas. Exactly one provider request and one outgoing `turn/start`
occur. All eleven original request/reply pairs are correlated by generation/ID;
the outgoing method sequence is prescribed, not derived from observed traffic.

## An accepted operation with no delivered reply

For the third case, the capture transport records the original incoming native
success and withholds that one response from Session. It does not construct or
modify a native envelope. The test receives a bounded observation of those
original bytes and requires the request Task to remain pending. Independently
observed delta, thread/turn identities and the provider's one held request prove
that native execution has started.

An acknowledged unsubscribe establishes detachment. Explicit reconnect settles
the still-pending request as `uncertain:true`, reason `explicit_reconnect`, with
its original ID/method/generation. The new connection reinitializes and the
same remote execution completes once. Native history queries recover its exact
content while local uncertainty remains one. Only an explicit caller
`record_reconciliation(:applied, evidence_digest)` clears it, after the digest
is computed from native completed history and the independent provider journal.
That digest is a caller record, not native deduplication or a remote status API.
One raw success was withheld; all eleven original replies remain captured,
while only ten are delivered to Session in this case.

The pending request keeps its original three-second timeout. A separate absolute
two-second bound covers pre-reconnect observation and caps unsubscribe's timeout;
the Task and Session pending state are checked immediately before reconnect.
This ordering was corrected during source review before runtime qualification.
No timeout failure was hidden or repaired by extending a bound.

## Scope and source

Production code, protocol schemas, providers, shared cleanup, dependencies,
database and historical records are unchanged. The two existing lifecycle
requirements gain this scoped transport evidence; no schema owner or state is
promoted. Counts remain 462 implemented /12 missing /11 blocked requirements
and 5,748 implemented /737 missing /136 blocked contracts, zero globally verified.

Pinned source routes:

- `app-server/src/lib.rs:810`: the Unix listener delegates to the control-socket
  acceptor, rather than starting a second model runtime.
- `app-server-transport/src/transport/unix_socket.rs:134`: the accept loop runs
  a separate WebSocket connection and forwards it into the shared native
  connection implementation at line211.
- `app-server/src/request_processors/thread_processor.rs:1034`: unsubscribe
  awaits removal of the connection's thread subscription before returning.
- `app-server/src/thread_state.rs:557`: subscription removal is independent of
  the actual thread execution; global status and scoped delivery are separate.
- `app-server/src/thread_status.rs` and `outgoing_message.rs`: native global
  status broadcasts and thread-scoped outgoing messages use different routing.

The scenario proves a controlled client response loss and explicit reconnect.
It does not prove physical packet loss, arbitrary ambiguous-outcome matching,
native operation deduplication, automatic resubmission, cold-process recovery,
TLS/proxy/other OS behavior or a real external backend. A11, source-bound legacy
and nullable branches, external/platform success, prohibited/broad/hosted gates,
complete compatibility and release remain incomplete.

## Verification

Focused qualification passes 3/0 at seeds501432/987654 with the existing
60-second case, five-second observation and three-second ordinary RPC bounds.
The withheld reply adds the stricter absolute bound described above. Event,
capture, message, read and provider limits are unchanged. Native/helper/provider
completion and process disappearance precede disposable-root removal.

Focused evidence is `/tmp/samgita-uds-reply-loss-focused-20261029`: 3/0 at
seed501432 in4.911s and seed987654 in4.611s. Original log SHA256 values are
`c49f4fcf16da7c390f3fb3b468f94d1ed25216b8a4898bdbafb9fc19da1c2de6`
and `82826bc62ecdf2da7029b47b815da5695ba28bfc6feefe30af6eec75049905eb`.

The first static preflight reports cyclomatic complexity26 after the shared
scenario is extracted from its original test macro into a function. Splitting
that function into native setup, stream observation, reconnect, recovery and
wire-inventory helpers corrects the structure. A separate quoted-AST comparison
requires all **107 assertion expressions and multiplicities** to remain exact;
it passes. Focused strict Credo then passes with no issue. No assertion or gate
is removed or disabled. Final runtime qualification uses the extracted helpers.

## Final combined source functional qualification

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-uds-recovery-combined-20261029
python3 -B /tmp/samgita-uds-recovery-binding-20261029.py
```

All **17 reviewed functional steps pass**. The retained main165 cases pass
twice in299.699s/302.786s within the original320s bounds. Extensions17/0 pass
twice in30.665s/30.768s within120s. The three original WebSocket seed selections,
four cleanup cases, independent outside consumer1/0, inventory, driver/root
formatting and compilation, strict Credo, Dialyzer and assets build also pass.
The runner's original argv and bounds remain; it checks exact selected counts.
No security/permission test, audit, mixed broad suite or hosted workflow runs.

All **1,762 guarded hashes** are identical before/after the run. Reviewed
fingerprint is `73c06faef86b5f50d9e208dbc7704f2025d320eb4abc9ca757b52dd7e3d58aa4`.
`results.json` SHA256 is
`c77bdbe6b76a99b040b0fb304606fdd24e1071f95bfdb4912c2d863e83f86b90`;
`source.json` SHA256 is
`2e29d5a3675cde9bce5ae049dd0980079acaa998416fda22b9ddb13553c03ceb`.

The binding checks all1,749 other tracked guarded files against Git baseline,
and ten ignored static outputs against the preceding successful17-step snapshot.
The first bookkeeping attempt wrongly required those ignored outputs to exist
in Git and stops with `KeyError`; it does not invalidate a functional step.
The corrected comparison preserves both conditions separately. Seven complete
causal upstream files match the immutable source archive. Only the two named
lifecycle records gain append-only evidence/limitations/transport coverage;
all schema contracts and states remain exact. Binding evidence is
`/tmp/samgita-uds-recovery-binding-corrected-20261029/binding.json`, SHA256
`379cb26dcb615c67a915b5053935022323868399ea90cb1223df2b5433dd12c0`.

Production inputs and existing dependency/replay/database/cleanup repairs are
unchanged; this unit makes no fresh assembly, publication or deployment claim.
Next: qualify the four source-supported ordinary quota literals separately,
then continue remaining genuine producer gaps. A11, prohibited/broad/hosted,
external/OS, full compatibility and release gates remain incomplete.

Rollback restores the single test module, the two lifecycle evidence records
and the reviewed runner count/fingerprint. No runtime or data migration occurs.
