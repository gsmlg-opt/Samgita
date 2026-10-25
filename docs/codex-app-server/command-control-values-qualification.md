# Native terminal, stdin and termination controls

One ordinary functional scenario uses two owned local Python children on
immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The official app-server executes every command and produces every protocol
response/output notification. The child fixture writes only stdout and local
identity/result markers; it never emits app-server messages. No model turn,
Samgita platform or database is required.

## Effects beyond control acknowledgements

Exactly five captured native requests have matching actual response IDs:

1. command/exec starts a PTY child with explicit size:null. The child sets raw
   terminal mode, atomically records its identity and kernel terminal dimensions,
   then emits READY. Its independently expected initial dimensions are 24/80.
2. command/exec/resize selects that processId and rows45/cols132. Its empty
   response is only a control acknowledgement.
3. command/exec/write sends fixed newline-terminated UTF8 input to the same ID.
   After reading the line, that child independently records exact input bytes
   and kernel dimensions45/132. Decoded native stdout must contain the same
   complete expected result. The original exec request returns exitCode0 and
   empty response stdout/stderr because output was streamed; the child PID
   must disappear.
4. A separate pipe command emits its own identity/READY marker and blocks on
   stdin. It cannot finish normally on this path.
5. command/exec/terminate selects the ready pipe child's processId. Its empty
   control response is followed by the original exec response with exitCode137
   and exact disappearance of that child PID. No result marker may exist.

The pinned [PTY spawn](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/command_exec.rs#L271)
uses size.unwrap_or_default; the [terminal default](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/utils/pty/src/process.rs#L63)
is 24/80. The control loop invokes actual resize/write/termination methods.
Linux pipe termination sends SIGKILL in
[process_group.rs](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/utils/pty/src/process_group.rs#L269);
the Unix status converter returns 128+signal, explaining 137. The output tasks
finish their ordered sends before the final response, so post-response draining
has a source-backed completion barrier.

The source handoff verifies twelve complete files against the archive. Parent
also verifies process_group.rs byte-for-byte, SHA256
`26668450452dd42b4a9a5a61b873e336a2cfe72be33410b9352d72f31e5bcf22`.
Source/owner snapshots and implementation handoff are in
`/tmp/samgita-v224-next-functional-candidate/` and
`/tmp/samgita-v227-command-control-implementation/`. Independent review finds no
actionable ordinary functional defect in these oracles.

Capture is bounded to 16 frames/4096 bytes per frame; the collector bounds 128
events/64KiB and detects gaps. Initialization, controls, readiness and reaping
use fixed 5s bounds; original exec uses 20s with a 15s native execution timeout.
No timeout increase, retry, shell action or discarded assertion is introduced.
Existing captured-connection cleanup remains unchanged. A fallback can signal
only the exact child identified by pidfd, start time, fixture script and handle.
The model journal stays byte-identical and empty. Fixed yolo launch settings are
setup only; no permission-policy assertion or production configuration changes.

## Exact owners and final checks

Only six physical owners gain scoped implemented evidence: **3409**, CommandExecParams size null;
**3414/3415/3416**, resize processId/size and its terminal-size reference;
**3420**, terminate processId; **3423**, write processId. Process aliases,
command-output thread/turn fields3426/3427 and whole schemas remain unqualified.

The first focused native run passes **1/0**, seed 501432, in 1.2 test seconds;
log `/tmp/samgita-v227-command-control-first.log`. The first combined v229 run
passes **35/0 at both 501432/987654**, but strict Credo rejects an explicit try
in this new test's cleanup helper. Its result is **6/8 planned commands**, with
consumer and Python syntax steps unrun. The syntax-only implicit-try correction
retains the exact cleanup body/after clause and every gate. The original results
remain in `/tmp/samgita-v229-functional-checks/functional/`.

The corrected final twenty-one-file block documented in
[start-default qualification](thread-start-default-values-qualification.md#exact-owners-and-qualification-boundary)
passes **35/0 at both 501432/987654**, in **60.544/61.603** command seconds.
Compile/format, strict Credo on **473 files**, outside-umbrella consumer **1/0**,
both Python AST checks and the **246-file** unchanged-source guard pass; all
eight planned commands complete. Exact commands/results/source hashes are
recorded there and in `/tmp/samgita-v231-functional-checks/functional/`.
The adjacent `manifest-binding-command.json` binds these six rows and final
test source. Contracts become **4,688 implemented / 1,874 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified
in both. No runtime library, shared helper or prior process cleanup is changed.

This qualifies Linux local PTY/pipe effects through stdio. Other OS/transport/
backend behavior, full command lifecycle and complete compatibility remain
incomplete. Security/permission-related checks and broad/hosted workflows remain
unrun under the user's restriction. A11 and real external profiles stay
incomplete; no release, publication or deployment is claimed.
