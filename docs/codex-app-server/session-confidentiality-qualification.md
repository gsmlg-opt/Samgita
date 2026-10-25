# Session callback, status and Logger confidentiality

The driver contains exceptions from the external transport callbacks `open`,
`send`, `handle_info`, `metadata` and `close`. Arbitrary raise/throw/exit reasons
and argument-bearing stacks are discarded at invocation, before they can enter
raw OTP Logger reports. The replacement is a fixed typed
`transport_callback_failed`, containing only the callback name and no native
wire. This bounded repair does not close Samgita's framework A11 exposure or
establish complete credential isolation.

## Reproduction and implementation

The original controlled-crash test used a safe exception reason. It qualified
callback-formatted state/message/log redaction, but arbitrary transport reasons
and stack arguments still escaped to raw Logger. Synthetic canaries reproduced
that leak before production editing. The retained baseline and raw external-term
capture are in `/tmp/samgita-v89-transport-boundaries/` and
`/tmp/samgita-v89-red-raw-events.term`. These are scripted transport failures,
not native Codex acceptance.

Only the external callback invocation is caught. Normally returned native Errors
and their authorized full wire remain intact. A typed raised cleanup Error keeps
the existing checked Stdio shutdown contract. Only `:ok` confirms close; arbitrary
exceptions or unconfirmed return values leave `shutdown_failed`, expose a safe
shutdown error and block replacement. Pending mutations retain uncertainty;
no exception causes an automatic retry or reopen.

A metadata exception makes `Session.status/1` return `{:error, Error}` and
disconnect. Later status reports disconnected or shutdown-failed state. The
platform bridge now rejects failed status before ticket commit as ownership loss;
a failure after ticket commit settles uncertain without native dispatch. Two
explicitly scripted bridge cases preserve exact Task/Attempt/event/receipt state
and prove no retry. They qualify this public return contract separately from
real native Session/generation tests.

Independent review then found a partial-allocation gap during replacement open:
the initial wrapper collapsed callback exceptions into normally returned errors,
leaving the Session alive and its owner-death guardian idle. Raise/throw/exit
regressions reproduced the leak twice before the lifecycle correction. Replacement
open exceptions now return the sanitized failure and stop the Session normally,
allowing guardians to reap resources whose handle was never returned. A normal
returned open Error remains exact and allows a later explicit retry on the same
disconnected Session. The original pending caller receives its uncertain result
before replacement starts; consumers must persist it because a stopped Session's
in-memory inventories cannot be queried afterward.

An explicit external allocation barrier installs the resource monitor before
releasing the exception. The tests require confirmed original close, pending
uncertainty before the replacement fault, normal Session termination, bounded
partial-resource reaping, no extra open or resend, and canary absence in captured
logs and raw Logger terms. Existing two-second cleanup bounds remain unchanged.
Red runs and the final correction are retained in
`/tmp/samgita-v100-replacement-open/`.

## Status and privileged diagnostic access

The existing tests retain independent canaries in pending request parameters,
native error message/data and explicitly supplied transport environment. Positive
controls scan external-term encodings independently of Inspect. Authorized
consumers still receive exact native errors and pending results. Error Inspect
and exception messages remain redacted.

With OTP debugging disabled, the entire real `:sys.get_status` term contains no
canary and its outer Debug list is empty. Explicit `:sys.log` is a separate trusted
boundary: tests positively require canaries in raw outer Debug while requiring
the process dictionary and callback-formatted state/log to remain redacted.
Disabling that debug history restores the full-status assertion. `:sys.get_state`
and privileged Debug access are not sanitized exporter inputs.

Retained OTP27.3.4.17 sources explain the distinction:
`stdlib-6.2.2.5/src/sys.erl:1006-1017` returns raw Debug outside formatted status;
`gen_server.erl:2942-2962` invokes application formatting only for the inner
state/log, using character-list labels. Its crash path at2629-2653 applies that
formatting before Logger emission. No private OTP/debugger state is patched.
The earlier label-type and raw-Debug test-oracle corrections remain documented in
[default semantics](default-semantics-qualification.md#fork-path-normalization-and-optional-resume-history).

## Executed evidence and remaining gates

The complete focused driver block, including all retained cases and four new
replacement-open regressions, passes **59/0 at both seeds501432/987654** in the
independent candidate source/build layout. Format and warnings-as-errors compile
pass. Exact commands, red/green logs, source hashes and limits are in
`/tmp/samgita-v100-replacement-open/handoff.json`. The earlier v89 block passed
55/0 twice; its two source-backed test-oracle repair rounds remain in that record.

The pre-integration platform block passes **17/0 twice** and its separate genuine
native authority profile **6/0 twice**, with compile, format and strict Credo in
`/tmp/samgita-v96-bridge-and-authority-checks/`. Those checks predate the final
replacement-open correction; final combined root checks and the complete
local/hosted matrix remain required and are recorded separately when executed.

After final-source integration, both full focused driver blocks pass **59/0**,
both bridge blocks **17/0**, and both dedicated genuine-native authority profiles
**6/0**, seeds501432/987654. Root/driver compile and format, root strict Credo
(449 source files) and the six-file source guard pass. The two retained databases
are distinct and neither is reset. Commands/logs are in
`/tmp/samgita-v103-integrated-checks/`; results SHA256
`ddaf509da80f5e425e32a340b4a8af9bc1172e3c0b2683b6cf96239d7000ec9a`,
source SHA256
`ffd021689cb85c7db5ff18267adf9b25fbe658435af6b0308d6063641fe4ddb6`.
The complete frozen-source local matrix and exact-pushed hosted checks remain
separate and required.

This boundary excludes callback-authored logs, malformed callback return values,
untrappable kills, unrelated internal/process exceptions, native stderr and raw
framework ingress/exporters. No arbitrary credential-authored Error is promised
safe merely because it has the Error struct. The complete confidentiality
requirement stays missing. A11's
[supported ingress prerequisite](a11-ingress-boundary.md) stays blocked. No
manifest owner is promoted by these scripted cases, and no live secret, paid
task, publication or deployment is involved.
