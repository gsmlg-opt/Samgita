# Native process lifecycle

Six cases in `apps/samgita_codex_driver/test/process_lifecycle_test.exs` drive
the real immutable Codex `rust-v0.163.0` over stdio. Source/binary hashes match
[qualification](qualification.md). Only owned temporary shell/Python children
are started; every case requires zero model requests. Python scripts are
ordinary command targets, not counterfeit app-server peers.

| Profile | Required observed behavior |
| --- | --- |
| Real PTY | `tty` implies streamed output. Initial and resized rows/columns reach the child. Invalid dimensions fail. Binary stdout/stderr multiplex into the PTY stream, and one exact nonzero exit is retained. |
| Stream bounds | Zero, partial, exact-boundary and null byte caps apply separately to raw stdout/stderr. Base64 bytes and final cap flags match native semantics without UTF8 loss. |
| Stdin and EOF | Missing/invalid stdin input fails while the process stays usable. Accepted binary bytes drain before explicit EOF, with exact stdout/stderr and exit association. |
| Controls and isolation | Non-PTY resize and disabled stdin reject explicitly. Killing one child leaves another usable. Reusing the terminal handle is a new explicit command after its exit notification. |
| Spawn and correlation | Empty command/handle, invalid size and negative timeout retain native errors and request IDs. Failed executable startup releases its reservation; a subsequent explicit spawn works. Unknown controls cannot address another process. |
| Finite timeout | A deliberately blocked owned process reaches native exit `124` exactly once, with no relaunch, pending request or uncertain local call. |

Both `process/outputDelta` and `process/exited` require the official positive
`emittedAtMs`. No readiness sleeps, timeout increases, skipped assertions or
retry-until-green were used. The first run passed **6 tests**, seed `501432`.
Together with existing method-family coverage, **21 tests passed** at each seed
`513498` and `987654`. Driver warnings-as-errors compile, scoped format and
whitespace checks passed. Logs:
`/tmp/samgita-process-lifecycle-{initial,regressions}.log`.

Pinned sources, relative to `codex-rs/`:

- `app-server-protocol/src/protocol/v2/process.rs`: PTY/stream/default contracts.
- `app-server/src/request_processors/process_exec_processor.rs:69,267,366,411,487,610,677,712,726`:
  validation, reservation cleanup, controls, timeout, caps and errors.
- `utils/pty/src/process.rs:186`: PTY resize and non-PTY rejection.
- `app-server/tests/suite/v2/process_exec.rs:24,143,193,239`: official profiles.

The four process methods' request/response entries and two process notification
entries have selected implementation evidence. Field contracts, concurrent
client ownership on a persistent server, remote execution and other required
transport/OS/backend profiles remain incomplete. These commands do not establish
Samgita Project authorization, Task acceptance, publication or deployment.
Final-source aggregate/hosted evidence is recorded separately.
