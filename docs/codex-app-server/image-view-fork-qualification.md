# Native image-view items and standalone fork sandbox

These cases use unmodified `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The loopback model peer supplies one prescribed tool call and one fixed answer;
it emits no app-server frame and never reads the source PNG. Real Codex performs
the tool, emits events, persists items and reads history.

## Actual local image view

`native_image_view_items_test.exs` creates an exclusive owned 2x2 RGB PNG and an
unchanged canary file. The independently prescribed relative view_image call
must produce exactly one native started/completed imageView pair with the exact
call ID, resolved owned path, type and independently bounded canonical times.
The provider continuation has exactly one call/output image. ImageFixture checks
PNG CRCs, dimensions and every prescribed RGB pixel, independently of native
encoding. Exactly two provider requests and the fixed assistant answer complete
the turn; no approval, callback or shell command is allowed.

Warm thread/items/read equals the complete independent entry. After confirmed
owned native shutdown, the test verifies and removes only its exact synthetic
PNG. A distinct native process's first content read is selective history, with
no resume or hydration. The exact entry survives absent source bytes, no model
request, no lifecycle event, no loaded thread and no recreated image. Duplicate,
absent and wrong-turn selectors retain their exact outcomes. The canary and
all other workspace contents remain unchanged.

Pinned source: `core/src/tools/handlers/view_image.rs:93–212,228–254` reads and
validates under the selected environment/sandbox, emits ImageView and returns
image content. `app-server-protocol/src/protocol/v2/item.rs:998–1002` converts
the complete public item. `app-server/src/request_processors/thread_processor.rs:3622–3669,6162–6185`
reads stored JSON rather than invoking the tool. Other file/model/detail,
remote environment, larger image budgets and other OS variants remain separate
qualification work; the two precise rejection cases below are now exercised.

The initial six-file owning run was **34 tests/one failure**. Its new provider
oracle omitted the genuine generated Responses output ID. The pinned session
stamps IDs at `core/src/session/mod.rs:3543–3552`, using the `fco` prefix from
`protocol/src/models.rs:1428` and UUIDv7 construction from
`protocol/src/response_item_id.rs:20–25`. The correction constrains that separate
generated identity and retains every exact map and pixel assertion. It changes
no driver, fixture response, deadline, cleanup or negative assertion. The failed
log remains in the v7 directory below.

## Native image rejection and cold absence

Two additional cases use the same unchanged native executor with prescribed
invalid-image bytes and `detail:low`. Native returns the complete independently
expected model-visible error string in a single `function_call_output`, with a
separate generated `fco_UUIDv7` identity. It produces no imageView start or
completion, no provider image, callback or approval. The fixed second answer
completes each turn after exactly two provider requests. All owned files and
the request journal remain unchanged through warm and first-cold selective
history queries, which return exactly empty data for the failed call ID. This
does not claim absence of internal failed-call transcript data.

The exact errors and early returns are in
`core/src/tools/handlers/view_image.rs:53–56,128–145,183–188`; the retained
upstream cases are `core/tests/suite/view_image.rs:1011–1086,1453–1515`.
`core/src/tools/parallel.rs:338–363` and `protocol/src/models.rs:2362–2375`
define the plain-text error output. Source order places the low-detail rejection
before filesystem access; these tests check observable files and protocol,
not OS read traces. No new imageView physical owner follows from absence tests.

## Standalone fork sandbox selection

`native_thread_fork_settings_test.exs` now creates a paginated parent with the
named `:read-only` permission profile. A sibling retains that profile and its
distinct cwd/approval selection. A separate child fork supplies only
`sandbox:read-only`, with permissions absent. Its effective public policy is
exactly `{type:readOnly, networkAccess:false}` and activePermissionProfile is
null, unlike the parent/sibling. An ignored override therefore cannot pass.

Independent loaded resume reads confirm every selected setting before and
after one permitted assistant-only child turn. Exactly one prescribed model
request and answer occur. Parent/sibling full history and rollout bytes,
loaded identities, workspace contents and interaction/uncertainty state stay
unchanged. No tool approval, write or turn-level permission override is used.
This proves successful selection and isolated permitted execution; filesystem
write denial, other sandbox modes and cross-OS enforcement are not inferred.

The extension separately supplies omitted and explicit-null `sandbox`, with
`permissions` absent. Both preserve the independently expected named readonly
profile. Integer and invalid enum values fail local schema validation and native
wire validation; the exact source and inherited-child histories/rollout bytes,
loaded identities and zero inference count survive both rejections. The explicit
valid child and permitted turn then prove recovery. Only the directly exercised
primitive null alternative gains another owner; the referenced enum wrapper
remains missing.

Pinned source: `app-server/src/request_processors/thread_processor.rs:1679–1710,5086–5146,5295–5386,5668–5687`
handles config overrides, named-profile inheritance and effective response
snapshots; `app-server-protocol/src/protocol/v2/shared.rs:332–350` and
`v2/permissions.rs:537–549,685–698` define the exact selected policy.

## Checks, mapping and remaining gates

The initial positive six-file owning block passes **34/0 at 501432 and 987654**,
**59.6/59.9 seconds**, zero exclusions. It includes image_view_items,
thread_fork_settings, image_preparation, fork_boundary_fields,
thread_resume_settings and thread_future_settings. Root/driver warning-free
compile, format, namespace preflight and strict Credo **438 files** pass.
The **1,490-file**, manifest-inclusive source guard matches. Commands, source
hashes and logs are in
`/tmp/samgita-native-cold-process-queue-v{7,8}-image-fork-20261025/` and matching
runners. Terminal summary:
`/tmp/samgita-native-image-view-fork-v8-terminal-20261025.json`, SHA256
`c0d299323318174db63158ff7b422a38d5355c1d3146f73fa2b1ae90985f8788`.

After the two image negatives and fork presence/rejection extension, the same
complete six-file block passes **36/0 at both seeds**, **64.9/67.6 seconds**,
zero exclusions. Compile, format, namespace preflight and strict Credo438 files
pass; the 1,490-file manifest-inclusive source guard matches. All commands/logs
are in `/tmp/samgita-native-cold-process-queue-v9-negative-null-fork-20261025/`
and its runner. Terminal summary:
`/tmp/samgita-native-image-view-fork-v9-terminal-20261025.json`, SHA256
`f1c7d0b6e8e344a826ec9b5e2a2a2d1fee42824cedf73606abda206d4e9c784e`.

Exactly ten direct imageView owners, five in each live/history schema, and the
ThreadForkParams.sandbox property plus its primitive null alternative gain
scoped implemented evidence: twelve exact owners.
No shared alias, PathUri definition, reference wrapper, containing method or
broad lifecycle is promoted. No row becomes verified. Together with the prior
[cold/process/config unit](cold-items-process-config-qualification.md), the
regenerated contract ledger is **3395 implemented/3226 missing**, zero verified;
requirements remain **462 implemented/12 missing/11 blocked**, zero verified.
Final complete local/hosted matrices, A11, source-unreachable emitters and
required external/OS success remain incomplete. No release, publication,
deployment, production migration or sibling-service change occurs.
