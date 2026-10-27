# Ordinary native environment connection envelopes

V528 continues after `e2d3ca0` with stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
It adds one ordinary functional case and a standalone finite helper. No
production driver, schema, platform, database or external service changes.

## Genuine producer and explicit lifecycle barrier

The helper owns real pinned `app-server` and `exec-server` processes, an
opaque held/cut byte proxy and a finite rejecting HTTP request sink. It does
not import the old environment helpers, which automatically execute checks
prohibited by the current user restriction. Synthetic connection setup only
establishes the native connection; no credential or permission outcome is
tested. Native launches use fixed yolo.

With the executor connection held, the case creates an attached thread and
a distinct detached control. Successful attached thread/start is the release
barrier: Session::spawn awaits Session::new; connection forwarding subscribes
synchronously before return. Pinned Tokio1.52.3 snapshots the receiver version
on subscribe, and changed() retains an unseen update even if the spawned
listener first polls later. Twelve complete producer/barrier files match the
official source archive; the pinned Tokio crate checksum matches Cargo.lock,
and the inspected watch implementation equals the crate.

Releasing the actual connection yields one original attached
`thread/environment/connected`. The case separately checks native executor
cwd metadata and ready status. It then terminates/reaps its owned executor
and closes the proxy; native recovery publishes Disconnected and the public
emitter yields one original attached `thread/environment/disconnected`.
Actual status must become disconnected. Observing Connected before stop
prevents watch-value coalescing. The detached thread receives neither event.
No arbitrary sleep supplies subscription readiness.

The full delivered native maps must preserve method, independently known
thread/environment IDs and original integer `emittedAtMs` inside measured
wall-clock brackets. Original encoded native lines are retained and separately
decoded through JSON and Wire, compared to complete delivered maps and
validated against the pinned aggregate schema. Exact counts/order, generation,
kind and monotonic capture identities remain required. No public notification
is fabricated.

Only root physical owners **2847** (`ServerNotification.json#/oneOf/18`) and
**2851** (`#/oneOf/19`) are candidates. Their canonical node SHA256 values are
`7f7295a6ef3bd788d20d15bdc0cf33363011bbc7edcf7d2a619632d50a58d52d`
and `493f75c910119347210c559f18f958f60e55c82c524192cc1a784795af9e7f36`.
The original experimental aggregate SHA256 is
`c626079776d401d358a8791b74cfe6c978d18aabbb78477ce7bd710a79779bc1`;
the hash-pinned generator reproduced it in the V527 schema-reference record.
No descendant or alias receives automatic credit.

## Bounds, ownership and focused verification

The journal records selected original notifications and operation/control
metadata only. Bounds: 65,536 bytes per native line, 8 selected captures with
524,288 total bytes, 160 journal entries, 16 helper workers, 8 proxy connections,
4 sink connections, 1 MiB forwarded proxy data, 32 issued requests and 96
native output messages.
Sequential controls release, stop and close have actual completion records;
close acknowledges only after cleanup. The helper reaps its own subprocesses,
closes owned sockets and joins every worker. Stdio owner completion and Port
closure are also required. Failed closure retains owned diagnostic artifacts.
No borrowed service resource is stopped.

The test issues metadata operations only, preserves both empty-turn thread
identities/selections, and requires zero requests at the rejecting sink. The
sink never supplies model success or inspects request headers/bodies. This
is a scoped no-inference observation; an opaque proxy does not independently
inventory every internal executor RPC or establish broader network behavior.

Two source-review startup findings were corrected before execution. Explicit
absolute owned CODEX_HOME/HOME/TMPDIR satisfy the existing Stdio guard.
Fixture-only `deferred_executor=true` allows a selected held executor during
initial thread snapshot; the default false would await readiness before the
test could release it. No production default, gate, assertion or deadline was
relaxed. The formatter preserves the complete Elixir syntax tree; Python AST
syntax parsing passes without importing or running the helper.

First actual-native focused run passes **1/0**, seed `501432`, in 2.0 seconds:

```sh
mix test test/native_environment_connection_envelope_test.exs --warnings-as-errors --seed 501432
```

| Artifact | SHA256 |
| --- | --- |
| New finite helper | `239f96ea487ae43eac710a9ddf40e7240abd462bcdc3cfb511552a48108d087c` |
| Formatted test | `833a5800abedbc3cfe5b56c1f7c28ad551e2030c4669a813e55a5f1f3334d135` |
| `/tmp/samgita-v528-environment-handoff.md` | `b8fdd62d292a26f62488adbbb680ad32becff1be48fdc04e9317936ccadecbc3` |
| `/tmp/samgita-v528-independent-review.json` | `1f300d0791102328426171b8a80f0c8e986cc789ed92c8c82cd12632b6df9820` |
| `/tmp/samgita-v528-focus-501432.log` | `160c5cbb6fcf4b92a6b3de0738844a80d9af69ef45a084a936caefb6032e6f64` |

The first combined-source run in `/tmp/samgita-ordinary-v528-qualified`
passes **131/0** at both fixed seeds and the outside consumer **1/0**, then
stops at strict Credo: one nested close-control expression and a zero-count
predicate in the new test. Dialyzer and assets do not run after that failure.
The final correction extracts that exact close-control body into
`request_close/2` and replaces the zero-count assertion with the equivalent
`refute Enum.any?`. Cleanup, assertions, bounds and all production sources stay
intact. Initial test SHA256 above identifies the earlier source; the corrected
test SHA256 is
`ecdedae6f64b734805c550cde96e294f3b2acbf89225a17cf90cf4a16b27d4bd`.
This adds one selected case/file, giving **70 files / 131 cases**. No native runtime
failure or bound increase occurred; the failed static check remains evidence.

## Final combined-source functional qualification

All **14 reviewed steps pass** against the corrected source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-v528-final
```

The **70-file / 131-case** actual-native selection passes at `501432` and
`987654` in 226.932 and 228.183 seconds. Three selected neutral WebSocket
cases pass at each of `455834`, `501432`, `987654` (13 other cases excluded).
The outside-umbrella real-native consumer passes **1/0**. Driver/root format,
driver/umbrella warnings-as-errors compile, inventory, strict Credo, Dialyzer
and assets build pass. The failed first static run above is not suppressed.

All **1,689** before/after guarded source hashes match. Fingerprint:
`892cf5373d7e7ab71c6d30dd445cc6c9b980d3ef02393aab0241d06abea8ca95`.
The final binding checks every command/result/log hash, the exact two added
files, two changed metadata/selection files, the precise equivalent static
refactor, twelve whole official producers, the pinned Tokio watch implementation
and both schema nodes. All **1,685** other earlier guarded files remain exact.

| Final evidence | SHA256 |
| --- | --- |
| `/tmp/samgita-v528-final-binding.json` | `7a16cb87afdb9c3737a36d1864c8504ed53ed0a291abc576de1c3ce6a24325da` |
| `/tmp/samgita-ordinary-v528-final/results.json` | `b00ae3b504f0c1bbc659e41d8468000abf74fb71f777038a83c1944476b12332` |
| `/tmp/samgita-ordinary-v528-final/source.json` | `6074fddbb6fed5db896faf90512991ddda7f3601c1b113a0520dc891b96a758a` |

Only owners2847/2851 gain scoped implemented credit. Contracts: **5,501
implemented / 990 missing / 130 blocked**; requirements: **462 implemented /
12 missing / 11 blocked**; **zero verified**. Next: integrate the independently
reviewed User transcript and read-only configured-provider capability cases;
their source-only drafts are not runtime acceptance.

## Rollback and remaining gates

Rollback removes the two new fixture/test files and their exact metadata/
selection/fingerprint changes. Existing mixed tests remain intact. No
production data or historical record changes. Security, credential,
authentication, authorization, approval and permission tests/audits, broad
suites and hosted workflows remain unrun and incomplete. Remote environment
services, other transports/OS, full environment compatibility, A11, unavailable
emitters/external acceptance, full compatibility and release gates remain
incomplete. Nothing is published or deployed.
