# Native resume bootstrap pages and hydration cursors

Five tests against stock `rust-v0.163.0` pass at seeds `501432` and `987654`,
**5/0** each, 7.4/6.9 seconds. Source commit:
`83086188ae0614bd882818ff1aa23f3194962012`; binary SHA256:
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The independent driver creates three completed native turns with distinct Unicode
input. Only the Responses model dependency is synthetic. No seeded rollout,
app-server emulator, imported history or platform database supplies the results.

`native_resume_page_fields_test.exs` and its eight fixed JSON variants exercise
initial-page omission, explicit null, empty parameters, asc/desc, all three
itemsView values, partial pages and zero clamping to one. Complete native pages
must match equivalent thread/turns/list results, with independent assertions for
expected IDs, order, count, view, exact user/assistant text and cursor presence.
Equality of two APIs alone cannot establish the result.

For both legacy and paginated histories, excludeTurns controls inline hydration
independently of the optional initial page. Explicit-null versus omitted page
requests are distinguished by key-presence assertions on the response. Global
hydration cursors are exact nulls for legacy and strings for populated paginated
history. Ordinary nextCursor excludes its previous page; descending backwards
turn/item cursors include their anchor. Saved cursors and exact pages survive
confirmed native shutdown and a different native process. Cold reads do not load
a thread; only explicit resume does. Model request count stays exactly three.

Malformed nested values sent through validation:wire receive actual native
errors. Stable negotiation rejects an active page option locally and on native
wire, while explicit null remains inactive. Rejections preserve history and do
not infer another turn. No timeout or production code changes were necessary.

## Pinned source and commands

Relative to the exact `codex-rs/` source:

- `app-server-protocol/src/protocol/v2/thread.rs:417-430,470-529` defines independent
  hydration, optional bootstrap pages and cursor fields.
- `app-server/src/request_processors/thread_processor.rs:3334-3410,3476-3490`
  shares the actual paginated listing; `3518-3547` returns global backwards
  cursors. `4330-4419,4616-4645,4710-4773` composes cold/hot pages separately.
- `thread_processor.rs:5895-5900,5945-6019,6044-6086` defines legacy page defaults,
  limit clamping and inclusive/exclusive cursors.
  `thread-store/src/local/thread_history/segment_paging.rs:450-467,491-528`
  implements their paginated comparison semantics.
- `app-server/src/request_processors/thread_lifecycle.rs:724-902` handles loaded
  resume and its separately owned active-turn overlay. This test covers idle
  completed histories only.
- `codex-experimental-api-macros/src/lib.rs:260-266` treats an Option as active
  only when Some. The stock server's error is checked independently of the local
  schema gate.

From the independent driver in verified Devenv, with `MIX_ENV=test` and the
hash-checked `CODEX_BINARY`:

```sh
mix test test/native_resume_page_fields_test.exs --seed 501432
mix test test/native_resume_page_fields_test.exs --seed 987654
mix compile --warnings-as-errors
mix format --check-formatted test/native_resume_page_fields_test.exs
```

JSON parsing, namespace prerequisite and scoped strict Credo pass. Logs:
`/tmp/samgita-resume-page-initial-*-20261024.log`. Nineteen exact request/result
contracts gain scoped implemented evidence, with no verified promotion. The
default native CI suite includes the file. Three assistant-only turns do not
prove richer tool filtering, upper-limit100 clamping, empty cursor branches,
active overlays, interrupted/error histories, remote storage, other transports/
OSes, service acceptance or A11. Full negotiation/default lifecycle stays missing.
