# Native child close, resume and followup

One functional journey uses the same real child across three ordinary root
turns on immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
A new Responses-only fixture prescribes model outputs and tool arguments.
It does not produce app-server responses, allocate child IDs or implement an
Agent runtime. Stock Codex owns those operations. No Samgita database or external
model service is required.

## Three causal turns

1. Spawn one child with a fixed initial input, mock-model and supported low
   effort. Wait for its independently prescribed completion, close it, and wait
   on that same formerly owned ID. The second wait returns actual not_found
   with timed_out:false; its native canonical item is failed/notFound.
2. Resume that same child, complete the root turn, and query thread/loaded/list.
   Both root and that child must be present before any followup send could load
   the child itself. Idle resume causes no model request.
3. Send a different fixed input to that child, wait for its independently fixed
   second answer, then close it. The final loaded list retains only the root.

The provider journal must contain exactly thirteen real requests: eleven root
requests grouped 5/2/4 by the three actual root turn IDs, and two child requests
with distinct actual child turn IDs and the prescribed initial/followup input.
Every request uses mock-model/low. Actual tool outputs must preserve the exact
child identity and fixed completion messages. Close reports the previous
completed state; it is not asserted to emit Shutdown. Native tool-result
not_found and canonical item notFound are different spellings and are checked
independently.

Every selected call has exactly one genuine item/started and item/completed in
the matching root/thread/turn, with independently fixed call IDs and bounded
native timestamps. Terminal-only thread/items/read observes those same calls
after the owning root turn completes. Wait and close have complete independent
expected item/state maps. Spawn/send/resume assert prescribed stable fields;
their scheduling-sensitive agentsStates snapshots are deliberately unqualified.
No observed native item is copied wholesale to manufacture expected content.

Twelve exact captured public envelopes cover start, turns, terminal item reads
and loaded-state queries. They retain unique IDs and matching actual response
IDs, with a 32-frame/4096-byte capture bound. Events are bounded to 256 and one
MiB with explicit gap detection. Readback must preserve the entire provider
journal, configuration, catalog, Python fixture and empty workspace. Existing
captured-connection cleanup and hash-checked owned-process disappearance remain.
Requests and initialization use five-second bounds; turns use twenty seconds
inside a sixty-second case. Fixed yolo launch settings implement the user's
default without policy tests or production configuration changes.

Twenty-one complete production source files match the pinned archive. Actual
[wait](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/wait.rs#L120),
[close](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/close_agent.rs#L43),
[resume](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/resume_agent.rs#L34)
and [send](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/multi_agents/send_input.rs#L44)
producers establish reachability. Source/owner mappings are in
`/tmp/samgita-v222-collaboration-candidate/`. Independent review confirms the
13-request and 12-envelope counts and the separate loaded-state resume oracle.

## Exact owners and qualification boundary

Only seven physical ThreadItemsReadResponse owners gain scoped implemented evidence:
**5297**, CollabAgentStatus notFound; **5298/5299/5300/5302**, spawnAgent/sendInput/
resumeAgent/closeAgent; **5309**, failed tool-call status; and **5459**, non-null
spawn reasoningEffort. **5291/5292** PendingInit/Running and **5307** canonical
inProgress remain unverified. No intermediate selective-history query, invented
emitter, race-selected snapshot, alias propagation or whole-family promotion is
used.

The first focused native run passes **1/0**, seed `501432`, in 2.7 test seconds;
log `/tmp/samgita-v225-collaboration-first.log`. Review identified inherited
30-second RPC defaults; final requests/initialization/diagnostics are tightened
to the planned five seconds before final combined-source qualification.

The final twenty-one-file block documented in
[start-default qualification](thread-start-default-values-qualification.md#exact-owners-and-qualification-boundary)
passes **35/0 at both 501432/987654**, in **60.544/61.603** command seconds.
Compile/format, root strict Credo, outside-umbrella consumer **1/0**, both Python
AST checks and the **246-file** source guard pass. The bounds-only focused
two-file run also passes **2/0**, seed 987654, in 4.9 test seconds; log
`/tmp/samgita-v225-tightened-bounds.log`. The subsequent v229 static failure and
unchanged-semantics cleanup correction belong to the new command test and remain
recorded in [its qualification](command-control-values-qualification.md).

Exact final commands/logs/source are in
`/tmp/samgita-v231-functional-checks/functional/`, with the results/source hashes
recorded in start-default qualification. The adjacent
`manifest-binding-collaboration.json` records original/current rows and test
SHA256 `a196c56d901a47cd682de62b79bf999dcec947b989f83ed4686e7b41544df9d0`.
Seven rows change: **4,682 implemented / 1,880 missing / 59 blocked** contracts;
requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified
in both. Runtime libraries and prior cleanup fixes remain unchanged.

General delegation, v2-only tools, every child state, interruption/reconnect,
other backends/transports/OS profiles and complete compatibility remain
unqualified. Security/permission checks and related broad/hosted workflows remain
unrun under the user's restriction; A11, unreachable legacy producers and real
external acceptance remain incomplete. No release, publication or deployment is
claimed.
