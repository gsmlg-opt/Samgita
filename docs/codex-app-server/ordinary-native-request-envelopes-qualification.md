# Ordinary native marketplace and review request envelopes

V483 (2026-10-28) indexes fifteen exact physical request owners using three
unchanged actual-native functional cases. This adds no protocol/driver runtime
code or new scenario. The immutable target remains official `rust-v0.163.0`,
source `83086188ae0614bd882818ff1aa23f3194962012`, Linux musl/stdio, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

| Exact owners in ClientRequest.json | Original wire and independent effect |
| --- | --- |
| 1438–1442, `/oneOf/69` | `native_marketplace_git_selection_test.exs`: actual encoded `marketplace/add` requests select a known nondefault A revision through real loopback Git HTTP and materialize an exact sparse working tree while source HEAD remains B. Persisted config and warm/cold duplicate no-ops preserve source, checkout and HTTP journal. |
| 1453–1457, `/oneOf/71` | `native_marketplace_partial_error_test.exs`: three actual encoded `marketplace/upgrade` requests use empty params. A valid local source materializes known bytes while a separate invalid source remains an errors entry inside the successful response. Repeated warm/cold no-ops preserve config, source and checkout. The Git-selection case does not call upgrade and cannot qualify these owners. |
| 800–804, `/oneOf/109` | `native_review_source_values_test.exs`: actual encoded Custom inline `review/start` creates a genuine native Review child. Real provider lineage, completed review items, canonical parent/child persistence and unloaded warm/cold discovery/history establish effects. |

Each five-node group is its complete request object, ID property, method
property, literal method enum value and params reference. The unchanged cases
retain original outgoing bytes/maps and distinct literal string IDs, then
require their correlated real native responses. Referenced parameter variants,
integer IDs, aliases, response siblings and equal-hash nodes gain no new credit.
The existing deeper behavior records remain
[Git selection](marketplace-git-selection-qualification.md),
[partial upgrade](marketplace-partial-error-qualification.md) and
[Review source](native-review-source-qualification.md).

Pinned dispatch is in `common.rs:909–913,1122–1126` and
`message_processor.rs:1555–1556,1702–1703`. Native marketplace handling is in
`marketplace_processor.rs:68–135`, `manager.rs:2951–3026` and
`marketplace_upgrade.rs:91–161,190–223`. Custom inline review dispatch and the
actual child are in `turn_processor.rs:445–475,1589–1599` and
`core/src/tasks/review.rs:128–140`. Ten complete source files match the retained
immutable archive binding; fifteen canonical nodes match the original generated
experimental export. Exact binding:
`/tmp/samgita-v483-envelope-binding/source.json`, SHA256
`0101433ae00e8dfb9ed5003d0ded673f9c599cbdc114dd79d8d6e7dab0f3e158`.

From the independent driver directory, the reviewed command is:

```sh
mix test test/native_marketplace_git_selection_test.exs \
  test/native_marketplace_partial_error_test.exs \
  test/native_review_source_values_test.exs --warnings-as-errors --seed 501432
# Repeat the same three files with --seed 987654.
```

Both pass **3/0**, in 8.019/7.717 command seconds, with all **1,668** executable
source hashes unchanged during the runs. Logs, exact commands and guard:
`/tmp/samgita-v483-envelopes-focused/`; `results.json` SHA256
`ea89fbce4dafebfcd555f7a15e819bfef379375c4e9abf944c5dbeddbb826cdf`,
`source.json` SHA256
`11e03ea457786d750a8810fc2e4a3f8987104d7c0b3de2be0eedf79ad3a1a3f6`.
The source guard runs before this metadata update. The prior V482 fourteen-step
matrix remains its exact recorded evidence; no 87-case combined run is claimed
by these focused results. The reviewed runner now includes the three cases;
its new selection is **53 files / 87 cases**.

Only these fifteen manifest rows change: **5,432 implemented / 1,073 missing /
116 blocked** contracts, unchanged **462 implemented / 12 missing / 11 blocked**
requirements and zero verified. Fixed YOLO is launch setup. No security,
credential, authentication, authorization, permission or approval test/audit,
broad suite or hosted workflow runs. Native code review here is an ordinary
functional operation, separate from permission approval. No real marketplace,
model-quality, detached-review, arbitrary selection, other OS/transport or
whole-method qualification follows. A11, unavailable emitters/external profiles,
full-goal and release gates remain incomplete. No publication or deployment.
Rollback reverts only the scoped evidence index and runner selection; it changes
no runtime, platform record or historical data. Continue genuine realtime
start/end instruction effects, followed by final combined permitted checks.
