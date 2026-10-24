# Ordinary native thread lists and reverse-cursor limitation

Three tests against stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, pass at seeds `501432` and
`987654`, **3/0** each, 5.7 seconds each. Binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This unit tests ordinary persistent `thread/list`, separately from loaded-thread
pagination, full-text search and turn/item history pages.

## Positive behavior

The real native process creates four completed assistant-only turns in four
persistent threads across two owned directories. The loopback model fixture
supplies only fixed Responses content. Exact stored names contain Unicode,
percent and underscore characters absent from the input text. Native results
prove scalar, relative/dot and array cwd filtering, duplicate/empty/nonmatching
cwd values, matching/nonmatching provider filters, default/empty/null/explicit
interactive source filters, literal case-sensitive title matching and combined
filters. These are exact expected ID sets, not comparison of two unasserted APIs.

Created-at ascending and descending order, explicit null/default values,
zero-to-one limit clamping and native next-cursor continuation preserve all four
IDs without gaps or duplicates. Exclusions apply before the requested limit:
alternating excluded IDs still fill a two-row page. Null/empty/unknown/uppercase
IDs,100 duplicate valid entries and101 rejected entries are distinct cases.
Invalid cursor, invalid UUID and malformed native-wire fields produce explicit
errors without modifying the listing or triggering inference.

Confirmed owned shutdown and a different native process retain the same opaque
next cursor, durable row projection and continuation. Listing does not load the
threads. Model request counts stay exactly4,4,1 in the three cases. Neither
Samgita nor PostgreSQL is required. Cleanup and all existing deadlines remain.

## Failed advertised reverse invariant and immutable upstream evidence

The initial seed `501432` run failed **1/3** in 4.6 seconds. The test required
reversing the second page to include its first row and the complete preceding
prefix. The actual response omitted the anchor. This is an unresolved native
contract discrepancy, not a driver cursor repair or a timeout/synchronization
problem. The original failure log is
`/tmp/samgita-thread-list-initial-501432-20261024.log`.

Exact paths below are relative to the pinned `codex-rs/` source:

- `app-server-protocol/src/protocol/v2/thread.rs:1573-1578` describes the reverse
  cursor's timestamp overlap. `app-server/src/request_processors/thread_processor.rs:2734-2736`
  actually calls the ordinary-list helper at5902-5930. It is not a turn-list helper.
- `rollout/src/recorder.rs:2170` converts native state `created_at` to
  `SecondsFormat::Secs`, losing its milliseconds. `thread-store/src/local/helpers.rs:140`
  parses that truncated timestamp into `StoredThread`.
- `thread_processor.rs:5923-5930` then adds1ms for an original ascending query
  or subtracts1ms for descending, assuming the stored timestamp still has its
  original precision. `state/src/runtime/threads.rs:1510-1542` compares the cursor
  strictly against `created_at_ms`; an ordinary timestamp-only reverse cursor
  has no UUID equality branch. Tie-breaking order is timestamp and UUID.

For actual native DB timestamp M, this pin emits C=floor(M/1000)*1000+1 for
ascending-to-descending reversal. The anchor is absent whenever M>=C. In the
opposite direction C=floor(M/1000)*1000-1 can include additional same-second rows.
The driver's lossless surface preserves that native cursor; silently rewriting
it would invent guarantees and require private server-state access.

The final test retains this discrepancy as an explicit **native-limitation
diagnostic**. It opens only the owned native `state_5.sqlite` using `mode=ro` and
`PRAGMA query_only=ON`, reads IDs and `created_at_ms`, and checks the complete
ascending order independently. It asserts the emitted cursor's exact truncated
timestamp and compares the complete reverse result with strict predicates over
all observed native timestamps, sorted by timestamp/ID. There is no subset-only
assertion, seeded history, database write, modified executable, driver workaround
or fake app-server frame. This establishes the actual defect's precision chain;
it does **not** satisfy the original anchor-inclusion acceptance condition.

The positive `backwardsCursor` contract therefore remains **missing** with this
source/behavior limitation. Nineteen other directly exercised contracts gain
scoped implemented evidence; no row is verified. Fixing the advertised reverse
guarantee requires upstream evidence for a corrected build and an explicit
target-pin decision. No external repository was modified or issue opened here.

## Reproduction and limits

From the independent driver in verified Devenv with `MIX_ENV=test` and the exact
hash-checked `CODEX_BINARY`:

```sh
mix compile --warnings-as-errors
mix test test/native_thread_list_fields_test.exs --seed 501432
mix test test/native_thread_list_fields_test.exs --seed 987654
mix format --check-formatted test/native_thread_list_fields_test.exs
```

Namespace preflight, Python AST and scoped strict Credo pass. Final logs:
`/tmp/samgita-thread-list-native-timestamp-*-20261024.log`. The default native
suite discovers the file. This unit qualifies only selected LocalThreadStore,
Linux/stdio, created_at and synthetic-model branches. `useStateDbOnly:true` is
the fixture path, not scan/repair acceptance. Other sort keys, ancestry,
originators, multi-provider positive populations, actual noninteractive sources,
concurrent list mutations, remote storage/services, other OS/transports and A11
remain incomplete. Aggregate and hosted checks are separate; no full compatibility,
publication or deployment is claimed.
