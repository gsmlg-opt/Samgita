# Current image-result history inputs

Two actual-native profiles capture a current Responses image result, transfer
its genuine durable user/image maps through the pinned unstable
`thread/resume.history` input, and consume the image in one explicit followup.
One imports both maps unchanged; the other changes only image passthrough
metadata to client null. This qualifies raw image-result history handling,
not an image-generation service, extension or artifact workflow.

## Native behavior and ownership

`apps/samgita_codex_driver/test/native_supplied_image_history_test.exs`
starts the immutable native executable against the bounded local Responses
producer `scripts/codex/supplied_image_history_fixture.py`. The producer emits
the current upstream `image_generation_call` shape with a fixed tiny PNG,
`completed` status, Unicode revised prompt and nonempty `ig_` ID. Native Codex
records the actual response item and stamps its source `turn_id`; the fixture
does not write app-server frames, rollout rows or database records.

The model catalog declares `input_modalities: [text, image]` before either
native starts. This matters because the pinned text-only model normalization
clears generated-image results. That separate behavior is not exercised here.
The ordinary generic response path need not emit an `imageGeneration` live item
pair; these tests require correlated native turn start/completion and actual
durable raw maps without inventing such a notification pair.

The source process closes and is reaped before bounded rollout inspection.
Whole-map equality checks the native user ID, observed creation-time range,
source turn and content classification, plus every image field and its native
metadata. A distinct cold process has an empty loaded list and imports these
two maps into a new idle thread/path. The unmodified case preserves both whole
maps; the separate client-null case changes exactly image passthrough metadata
to null and expects native serde to omit that key, preserving all other fields.
It is not evidence of native-null emission.

Import performs no inference or execution. One deliberate continuation then
consumes the exact original image copy with only custom-provider passthrough
removed; the original `ig_` ID, result, status and revised prompt remain exact.
Both user messages and supplied-history initialization metadata are checked.
The provider returns a fixed literal assistant answer, independently required
in the correlated completion. Requests stay **1 → 1 → 2** per profile; a third
request fails. Source bytes, imported original maps, config/catalog/script bytes
and the empty workspace are checked through explicit cold close/reap.

## Exact nodes and upstream evidence

All selected physical nodes belong to `ClientRequest.json` under
`/definitions/ResponseItem/oneOf/12`:

| Owners | Evidence and limit |
| --- | --- |
|407|Current image-result object, genuine whole native map and consuming followup|
|409|Exact nonempty `ig_` ID; null-ID behavior is not covered|
|410/411|Actual native source-turn metadata object|
|412|Separately modified client-null metadata input, normalized to omission|
|413/414/415|Fixed PNG result, nonempty Unicode revised prompt and literal completed status|
|416/417|Exact `image_generation_call` type/literal|

Owner408 stays missing and unchanged. Shared hashes, enclosing unions, other
variants and unrelated capabilities receive no promotion.

Pin: `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Twenty-three complete source files were compared byte-for-byte with the pinned
official archive; eleven exact exported schema nodes were hash-checked:

- `core/tests/suite/model_switching.rs:1035–1120` contains the current
  `generated_image_is_replayed_for_image_capable_models` integration producer;
  `core/tests/common/responses.rs:953–970` defines its response shape. These
  upstream tests were read, not executed.
- `codex-api/src/sse/responses.rs`, `core/src/session/turn.rs`,
  `stream_events_utils.rs`, `event_mapping.rs` and `session/mod.rs` establish
  current decoding, generic handling, source metadata and durable recording.
- `context_manager/history.rs`, `normalize.rs` and `image_preparation.rs`
  establish history retention and image-capable normalization.
- `core/src/client.rs:1007–1009,1092–1096` and
  `protocol/src/response_item_id.rs:36–39` explain the separate provider copy:
  custom-provider metadata is removed while the `ig_` ID is retained.
- The pinned thread processor/protocol, rollout payload/policy/recorder and
  live-thread/writer complete the supplied-history persistence chain.

## Checks, bounds and remaining gates

The owning module passes **2/0**, seed501432, in **3.5 seconds**, log
`/tmp/samgita-v312-image-history-501432.log`. Final commands and their exact
environment are in `/tmp/samgita-v312-final-run.py`; artifacts are under
`/tmp/samgita-v312-functional-checks/`. The final reviewed functional matrix
passes **44 files, 86/0 twice**, seeds501432/987654, in **149.177/149.049 seconds**.
Scoped format, warnings-as-errors compile, strict Credo, outside actual-binary
consumer **1/0**, twenty-two fixture ASTs and the **287-source** guard pass.
All prior285 guarded sources also match committed baseline
`a1cd0f200f8e544785ed87b9c9ad5649015d2e13` byte-for-byte. Only the new test
and producer are added; no native semantic repair is needed.

The first matrix also passed86/0 twice, but the later staged whitespace check
found one trailing blank line in the new Python producer. The local commit had
already been created because that check did not stop the command sequence.
Before pushing, the blank line was removed, the complete permitted matrix was
rerun on final sources, and the unpublished commit was corrected. Original
artifacts remain in `functional/`; final artifacts are in `functional-final/`.
The evidence records the exact one-newline delta; no assertion or deadline changed.

| Evidence | SHA256 |
| --- | --- |
| Results | `8e1c2a3a96daa9ac06d5fe004c7799ba7cea3390f283140bb03b0f8c6b44a99b` |
| Source guard | `f9dfd06bc6ca22e3eb6a5c351f8e8364f405c27ca18dec7fc0a0c55884376649` |
| Twenty-three pinned files, eleven nodes and final newline correction | `e8261c1d3eadfdd0a324a9081ef22aaedaf2e64b0e439010db67c5007091a682` |
| Resulting manifest | `4f34dec7713978ab9b2705ee88346ca9103a7b46850b5f61264eba9fcd193448` |

Session defaults remain256events/8MiB; local event capture/import input is
bounded to1MiB, files to4MiB/2048rows/262KiB per line. Existing20-second event
and60-second case deadlines, owned process guardians, native close/reap and
provider owner/completion/Port cleanup remain. No timeout increase, blind retry
or weakened gap assertion occurs. Fixed yolo is setup, not a varied policy.

Exact manifest binding proves ten promotions with unchanged schema identities,
planned tests, requirements and excluded owner408. Inventory consistency passes;
strict completeness exits **1**. Contracts become **4,933 implemented / 1,622
missing / 66 blocked**; requirements remain **462 implemented / 12 missing /
11 blocked**, zero verified. Real image generation/quality, image_gen HTTP or
extension/artifacts, arbitrary metadata/statuses, null IDs/prompts, full context
restoration and external providers/OS/transports remain unqualified. Prohibited
security/authentication/permission/approval tests, broad/hosted workflows,
full-goal, A11 and release gates remain incomplete. No publication, production
migration or deployment occurs.
