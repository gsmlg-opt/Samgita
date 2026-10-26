# Native initial PTY dimensions

Two added real pinned-native cases distinguish nondefault initial terminal sizes
from an ignored/default object. They preserve every original resize/default case,
setup, helper and Python fixture. No production code or dependency changes.

## Independent command and process effects

The command case in
apps/samgita_codex_driver/test/native_command_control_values_test.exs sends actual
command/exec with tty:true and size:{rows:31,cols:101}. Its child calls
os.get_terminal_size(0) before READY and after receiving the existing fixed input.
The test compares complete actual child identity, streamed RESULT and result
file against31/101, actual PID/handle and exact input bytes, then requires
correlated normal exit0. Captured native requests are exactly exec plus write.
The original command case independently keeps null/default24/80 and real
resize45/132 observations.

The process case in
apps/samgita_codex_driver/test/native_process_values_test.exs sends actual
process/spawn with tty:true and size:{rows:37,cols:113}. Its child measures the
kernel terminal size for READY. A normal q input yields exact binary tail,
stdout-only output and exactly one correlated process/exited with exit7.
Captured requests are exactly spawn plus writeStdin. The original process cases
retain explicit/null-default24/80, real resize40/120, binary controls and reaping.

Expected dimensions never reach either child through argv, environment or
stdin. The command arrays are checked in full. The capture transport delegates
encoded requests to stock Codex and only records copies; it creates no native
response or terminal output. No inference, model response or terminal emulator
stands in for OS state. Each case requires ready/gap-free/no pending/uncertain
operations, empty loaded threads and zero provider requests. Actual child/native
reaping and script/config/request-journal retention remain required.

## Exact owners and source

Only four ClientRequest properties gain implemented evidence:

| Owner | Pointer |
| --- | --- |
|96|/definitions/CommandExecTerminalSize/properties/cols|
|97|/definitions/CommandExecTerminalSize/properties/rows|
|297|/definitions/ProcessTerminalSize/properties/cols|
|298|/definitions/ProcessTerminalSize/properties/rows|

The two definitions share some node hashes; each receives its own actual API
input and independent observed terminal effect. No enclosing method, reference,
optional object/default/error sibling or other environment gains evidence.

Pin: rust-v0.163.0, source83086188ae0614bd882818ff1aa23f3194962012, binary SHA256
399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
Eight complete official files match the immutable archive; all four exact
physical nodes independently match their canonical hashes.

The separate v2 command_exec.rs/process.rs protocol structs carry uint16
rows/cols. Command request conversion at
app-server/src/request_processors/command_exec_processor.rs:311–315 and
app-server/src/command_exec.rs:271–280 reaches spawn_pty_process with the supplied
size. Process conversion/spawn at
app-server/src/request_processors/process_exec_processor.rs:125–142,309–321
independently follows that size. The original resize routes reach ProcessHandle
resize. utils/pty/src/pty.rs:481–504 constructs libc.winsize.ws_row/ws_col and
passes it to actual openpty; utils/pty/src/process.rs:305–317 uses TIOCSWINSZ
for resize. The fixture's kernel queries supply the independent behavioral
oracle; a successful control reply alone is insufficient.

## Verification

Owning block:5/0, seed501432,5.3seconds, log
/tmp/samgita-v318-terminal-size-501432.log.
Commands/environment: /tmp/samgita-v318-run.py; artifacts:
/tmp/samgita-v318-functional-checks/functional/.

The reviewed **48-file matrix passes97/0 twice**, seeds501432/987654,
in **169.837/169.484 seconds**. Scoped format, warnings-as-errors compile,
strict Credo on498 sources, outside actual-binary consumer **1/0**,27 fixture
ASTs and the **296-source** guard pass.

Original command/process cases and helper suffixes remain byte-identical to
baseline d0a92c70cc7538f4b21581598ac125e5b79b087d. Final reconstruction proves
only one inserted case per module; formatter changes are confined to new lines.
No files/fixtures are added; the other294 guarded sources remain byte-identical.

| Evidence | SHA256 |
| --- | --- |
| Results | 4f5253115565585f5ea9e82918c7c8eece422764007457f5b232970c2f424f25 |
| Source guard | ce0533be12e99cc6e5209f28d658f8567907ec5ea9b843ebd03e2888fcacc39d |
| Eight pinned files and four nodes | 5e465427360efd2f307d96e91b597709cc016cf660f24d87e1c1f7800e854152 |
| Resulting manifest | f874bb963ffa9b975dad6f5517045cd436cc4097ffd5f70079741accfea64857 |

Command retains60s case,15s command timeout,20s task/5s control bounds,
16captured frames/4KiB,128events/64KiB and existing20s cleanup failsafe.
Process retains60s case/5s control/event bounds,32frames/4KiB,256events/64KiB
and its existing20s cleanup failsafe. Both successful new cases terminate
normally; no failsafe, timeout increase or weaker gap assertion produces success.
Explicit owned PID/start/script identity and pidfd cleanup stay unchanged.
Fixed yolo is setup, not policy qualification.

Final binding proves exactly four promotions with schema identities, planned
tests, every other contract and all requirements unchanged. Inventory consistency
passes; strict completeness exits1. Contracts become **4,953 implemented / 1,602 missing /
66 blocked**; requirements stay **462 implemented / 12 missing / 11 blocked**, zero verified.
Only selected positive dimensions on Linux-x86_64-musl/stdio are qualified.
Invalid/uint16-boundary dimensions, Windows/ConPTY, macOS, remote and complete
terminal behavior remain unqualified. Prohibited security/auth/permission/
approval tests and broad/hosted workflows stay unrun. A11, external/OS,
full-goal and release gates remain incomplete. No publication or deployment.
