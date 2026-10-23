# Native diagnostics and memory status

Five actual-binary cases in
`apps/samgita_codex_driver/test/native_diagnostics_memory_test.exs` exercise the
immutable Codex `rust-v0.163.0` pin described in [qualification](qualification.md).
They use owned disposable homes, a loopback model fixture and zero model calls.
No Samgita database or real memory history is involved.

The diagnostics case checks the returned PID against `/proc/<pid>/exe`, requires
the owned pinned executable, observes Linux resident memory and the null
non-macOS physical footprint, and verifies registered gauge names/values. Two
native threads produce `core.threads.live = 2`. After archival and a cold process
restart, their metadata remains readable while neither thread is loaded. A
gauge is absent until its first use; an unregistered gauge is not a fabricated
zero measurement. The native `app.requests.in_flight` gauge includes the
diagnostics request, with the upstream-supported startup overlap of one or two.

Memory cases verify omitted/null/default and boundary thresholds `1`/`4096`,
reject `0`, `4097` and the largest u32 with the exact native error, and require
unchanged subsequent status. A new persistent thread alone is not consolidated
memory. Native `memory/reset` touches only that case's disposable home and leaves
its thread readable; archival materializes metadata before the cold read. An
in-memory *thread* store still has SQLite-backed memory status. All observed
empty-history statuses are exactly zero consolidated threads and `v2Ready=false`.
Explicitly disabled experimental negotiation reaches the native rejection for
diagnostics, status and reset, bypassing only local preflight to observe it.

Pinned source, relative to `codex-rs/`:

- `app-server/src/request_processors/diagnostics.rs:5-26` and
  `app-server-protocol/src/protocol/v2/diagnostics.rs`: native snapshot mapping.
- `diagnostics/src/lib.rs:8-62,90-105,132-148` and
  `core/src/codex_thread.rs:87,254`: first-use registration, sorting, Linux
  measurements and thread-lifetime accounting.
- `app-server/tests/suite/v2/server_diagnostics.rs:25-110`: native reference
  behavior and experimental gate.
- `app-server/src/request_processors/memory_status.rs:13-54` and
  `app-server-protocol/src/protocol/v2/memory.rs`: thresholds/readiness.
- `app-server/src/lib.rs:1395-1462`: standalone startup initializes a state DB
  even when a different thread store is selected.
- `app-server/src/request_processors/thread_processor.rs:1731-1741,1898-1936,2966-3027`:
  archival materialization, scoped memory reset and cold read behavior.

The first run had five cases and three fixture expectation failures: an unused
gauge was assumed present; the in-memory thread store was incorrectly assumed to
disable memory SQLite; and an unmaterialized thread was assumed durable after
process exit. Source inspection corrected those expectations without changing
runtime behavior. The next run exposed one remaining exact-response fixture
error: `thread/loaded/list` includes `nextCursor:null`. The assertion now retains
that field. There were no timeout increases, deleted scenarios or native mocks.

`mix test test/native_diagnostics_memory_test.exs --seed 501432` and the same
command at seed `987654` each passed **five tests, zero failures** under Devenv
Elixir 1.18.5 / OTP 27.3.4.17. Logs:
`/tmp/samgita-native-diagnostics-memory-initial.log`,
`/tmp/samgita-native-diagnostics-memory-repair-1.log` and
`/tmp/samgita-native-diagnostics-memory-repair-2.log`.

These selected entries are implemented, not fully verified. A genuine native
consolidation producing `v2Ready=true`, unavailable-state-DB errors, nonempty
reset behavior, concurrent consolidation/reset and other OS/transport profiles
remain unqualified. Upstream's readiness unit fixture seeds internal SQLite
records (`app-server/tests/suite/v2/memory_reset.rs:150-245`); this client profile
does not treat such seeding as real native consolidation evidence.
