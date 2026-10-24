# Owning history-item and read-state fields

Status: selected implemented contracts; full compatibility remains incomplete.
All native evidence uses Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

## Nonempty text spans through persisted item reads

`native_text_span_history_test.exs` adds two actual-native cases using the
existing deterministic Responses fixture and owned-process guardians. Its
positive input `é🙂xλ` is independently asserted to have nine bytes and four
characters. Four exact inclusive-start/exclusive-end byte ranges slice that
input into the original characters. Nonempty, absent, null and empty-string
placeholders retain the pinned conversion semantics: absence becomes null;
the other values remain exact. Original user-item events, loaded full history
and `thread/items/read` must return the complete expected item. Item timestamps
come from the original started/completed events. After confirmed owned shutdown,
a different native process returns the same persisted entry without loading the
thread or making another provider request.

The second case sends six malformed span forms through native wire validation:
null arrays/ranges, a missing end, negative unsigned offset, string offset and
nonstring placeholder. Each must fail before dispatch and preserve the entire
known history, selected item response and single provider request. These cases
do not invent rejection of overlapping, reversed, out-of-bounds or split-codepoint
spans. The source declares byte ranges and typed fields; it does not establish
all such semantic validation.

The pinned [input conversions](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/turn.rs#L358-L448)
and [owning item-read projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/thread_processor.rs#L3622-L3669)
provide the exact source boundary. This extends the previously qualified
[turn-input behavior](turn-input-qualification.md) to this specific response
owner; identical schema hashes alone are not evidence.

Serial commands through `devenv shell --no-tui --`, `MIX_ENV=test`, from the driver:

```sh
mix compile --warnings-as-errors
mix test test/native_text_span_history_test.exs test/turn_input_test.exs test/native_persisted_tool_items_test.exs --seed 501432
mix test test/native_text_span_history_test.exs test/turn_input_test.exs test/native_persisted_tool_items_test.exs --seed 987654
mix format --check-formatted test/native_text_span_history_test.exs
```

Both combined runs pass **14/0**, 11.3s each, followed by strict Credo. Full
commands/exits/logs: `/tmp/samgita-native-span-validation-20261024/`. Six exact
owning `ThreadItemsReadResponse` contracts gain evidence: byte-range start/end,
the range property and its referenced object, placeholder and nonempty
`text_elements`. No complete input union, renderer, other transport or OS is
qualified.

## Previously executed assertions indexed without new runtime behavior

Eight additional owning `ThreadItemsReadResponse` rows index the existing
[persisted dynamic-tool cases](persisted-tool-items-qualification.md).
`native_persisted_tool_items_test.exs` independently supplies nonempty Unicode
user text and asserts the exact original user item, discriminator and distinct
ID before direct loaded/cold `thread/items/read` comparisons. The eight rows are
user content/ID/type/exact type enum and the literal text-input variant plus
text/type/exact type enum. The fourteen-case repeats above include both dynamic
success/failure cases. Their original empty spans never supplied nonempty span
evidence; the new cases above do so explicitly.

Two `ThreadReadResponse` rows index the existing
[organization read-state cases](organization-lifecycle-qualification.md): the
non-null `readState` property and its object branch. Actual owning reads assert
independent unread turn identity, advancing revisions, explicit read/unread
changes, cold persistence and the committed winner of competing updates.
`firstUnread: null` inside that object does not qualify `readState: null`; the
outer null branch remains missing. Existing executed eight-case evidence is
retained, rather than presented as a new test run.

Only these sixteen exact IDs gain scoped `implemented` status; no requirement
or contract becomes fully verified. No generic forwarding, sibling-schema
propagation or synthetic notification establishes these statuses. Final
combined-source/hosted checks, complete lifecycle evidence, A11 and external
success profiles remain required.
