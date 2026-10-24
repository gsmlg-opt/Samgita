# Native turn and item cursor semantics

Five new stock Codex `rust-v0.163.0` cases pass at seeds `501432` and `987654`,
**5/0** each, 8.5 and 9.1 seconds. They verify the source pin
`83086188ae0614bd882818ff1aa23f3194962012` and executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
A loopback Responses fixture supplies fixed assistant messages to the actual
native process; there is no fake app-server, edited native database or seeded
rollout.

Three independently completed turns supply exact original turn IDs and content.
The six original user/assistant started/completed notifications independently
supply item IDs, turn associations, payloads and timestamps. Legacy and paginated
turn pages, and paginated item pages, must return those complete expected
sequences in both directions. Next cursors exclude their previous anchor and
end with explicit null. Every page's reverse cursor includes its first anchor
and enumerates the complete preceding prefix, including first-page overlap.
There is no subset-only assertion or client cursor rewriting.

Confirmed owned shutdown, a distinct native process and unchanged opaque cursor
strings reproduce every exact query/response. History reads leave threads
unloaded and make no additional model requests. Malformed cursors, cursors for
independent foreign histories and paginated cross-method scope return exact
native invalid-request errors. Both durable histories remain unchanged and the
provider count stays fixed. Legacy turn-ID cursors have no explicit thread
binding; rejection here concerns distinct turn IDs, not fork-shared identities.

Source owners below are relative to pinned `codex-rs/`:

- `app-server/src/request_processors/thread_processor.rs:3189-3270,5942-6035`
  selects legacy versus paginated turns and implements turn-ID/includeAnchor
  legacy cursors and exact parse/absent-anchor errors.
- `thread-store/src/local/thread_history/read.rs:30-43,276-311,450-454`
  binds paginated cursors to requested thread and turns/items scope.
- `thread-store/src/local/thread_history/segment_paging.rs:450-530`
  implements strict next and inclusive backwards ordinal comparisons.
- `thread_processor.rs:3337-3405,3550-3625` maps native store errors to JSON-RPC
  invalid-request responses and hydrates completed items.

From the independent driver in verified Devenv, with the pinned CODEX_BINARY:

```sh
mix test test/native_history_cursor_semantics_test.exs --seed 501432
mix test test/native_history_cursor_semantics_test.exs --seed 987654
```

Compile with warnings as errors, namespace preflight, scoped formatting and root
strict Credo pass. Commands and complete results:
`/tmp/samgita-native-history-cursors-qualification-20261024/attempt-01/`.
Existing 60-second case limits, turn deadlines, fixture readiness and guardian
cleanup remain unchanged. Only four exact owning next/backwards response-field
contracts gain scoped implemented evidence. Other variants, concurrent mutation,
compaction/rollback invalidation, updated-item ordinal scope, remote storage and
other transport/OS profiles remain unqualified.

The ordinary timestamp-based
[thread-list reverse-cursor defect](thread-list-fields-qualification.md) is a
different contract and stays missing. These turn/item success cases neither
repair that immutable upstream defect nor promote it. No whole method, broad
lifecycle or fully verified claim follows. Final combined-source and hosted
checks remain separate; there is no tag, publication or deployment.

## Existing item timestamp owner evidence

A later source audit indexes two more exact owning contracts,
`ThreadItemsListResponse`'s `ThreadItemEntry.startedAtMs` and `completedAtMs`,
from the unchanged positive test at `native_history_cursor_semantics_test.exs:39`.
At lines 153–178 the expected entries obtain their timestamps from the original
matching native start/completion notifications, with positive integer start,
completion not before start, and exact item/thread/turn identity. Lines 193–243
compare complete direct `thread/items/list` pages in both directions against
those expected entries; lines 257–271 repeat every query after confirmed owned
shutdown and a distinct native process. No list response supplies its own oracle.

The unchanged persisted-tool test at lines 144–147, 189–231 and 253–266
independently corroborates the same owning method with selected tool items.
Its direct list evidence, rather than sibling `thread/items/read` equality,
is used here. Both modules retain their prior two-seed native results. They also
ran inside both successful hosted default-driver partitions, **547/0** total,
at `3fbaf74` in conformance run
[40064648290](https://github.com/gsmlg-opt/Samgita/actions/runs/40064648290).

Only these two timestamp contracts become scoped `implemented`, with zero
`verified`; no new test or runtime change is introduced. Null/absent timestamps,
in-progress histories, remote storage, cross-host clock ordering, other
OS/transport profiles and whole-method qualification remain incomplete. The
reviewed source-only candidate report is
`/tmp/samgita-thread-items-list-existing-assertions-20261024-candidates.json`.
