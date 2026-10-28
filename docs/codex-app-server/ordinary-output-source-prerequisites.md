# Ordinary output producer prerequisites

This source-only unit follows the millisecond reverse-pagination qualification
on `main`. It binds17 exact missing owners to their reviewed production route,
without new implementation, runtime or acceptance credit. Target remains
official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`.

## Two nullable schemas lack their corresponding typed output producer

Owner2549 is
`ServerNotification.json#/definitions/ThreadItem/oneOf/15/properties/savedPath/anyOf/1`.
The public ImageGenerationItem at `ext/items/src/image_generation.rs:38–40`
uses `skip_serializing_if = Option::is_none`. None omits savedPath; Some emits
a path. Neither emits explicit null. The immutable
[serializer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/items/src/image_generation.rs#L38)
is the upstream evidence for this boundary. Extension pass-through and older core
image conversion share this serializer
(`app-server-protocol/src/protocol/v2/item.rs:1002–1019`). The genuine provider
ImageGenerationCall mapper supplies None at `core/src/event_mapping.rs:240–255`.
Public item notification conversion at
`app-server-protocol/src/protocol/event_mapping.rs:406–421` uses that typed item;
the media transformation only clears result (`app-server/src/notification_media.rs:193`).
A missing member, positive saved artifact or authored null frame cannot qualify
this explicit-null branch. See the earlier [pinned output boundaries](pinned-output-blockers.md).

Owner3386 is
`v2/CollaborationModeListResponse.json#/definitions/CollaborationModeMask/properties/reasoning_effort/anyOf/0/anyOf/1`.
Both production models managers call the same closed preset function
(`models-manager/src/manager.rs:482–484,828–830`).
The immutable [preset constructor](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/models-manager/src/collaboration_mode_presets.rs#L6)
at6–24 constructs Plan with Some(Some(Medium))
and Default with outer None. The empty public list params, thread-manager
delegation and public Into conversion preserve those values
(`app-server/src/request_processors/catalog_processor.rs:332–344`,
`core/src/thread_manager.rs:936–938`,
`app-server-protocol/src/protocol/v2/collaboration_mode.rs:9–45`). No parameter
or alternative production manager selects Some(None). That constructor at
`protocol/src/config_types.rs:842` belongs to a cfg(test) mask test, not list
production. The already observed Default null belongs to3387; it cannot prove
3386 by equal JSON value or node hash. See the [catalogue qualification](collaboration-catalogue-qualification.md).

## Exact stored search sources remain prerequisite

Seven owners remain missing:

| Owner | Export and pointer |
| --- | --- |
|6079|`v2/ThreadSearchParams.json#/definitions/ThreadSourceKind/enum/6` — subAgentCompact|
|6081|`v2/ThreadSearchParams.json#/definitions/ThreadSourceKind/enum/8` — subAgentOther|
|6107|`v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/0` — scalar union|
|6109|`v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/0/enum/1` — compact|
|6110|`v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/0/enum/2` — memory_consolidation|
|6120|`v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/2` — Other object|
|6121|`v2/ThreadSearchResponse.json#/definitions/SubAgentSource/oneOf/2/properties/other`|

The real search path at
`app-server/src/request_processors/thread_processor.rs:2765–2884` applies the
exact core-source postfilter (`app-server/src/filters.rs:51–81`), then projects
the stored thread's source at6373–6448. It does not derive source from a task
name, compaction item, a same-named separate ThreadSource or a supplied history.
Current compaction uses the existing Session (`core/src/tasks/compact.rs:29–96`,
`core/src/compact.rs:117–177`); this bounded review establishes no new Compact
child constructor. This is a discovery prerequisite, not global impossibility.

The current memory producer explicitly uses **Internal** MemoryConsolidation
plus a separate ThreadSource (`memories/write/src/runtime.rs:390–407`). Public
conversion maps Internal to Unknown
(`app-server-protocol/src/protocol/v2/thread_data.rs:45–57`), rather than the
retained SubAgent literal. No memory runtime was enabled. Other still requires
an independently established permitted producer; the previously excluded route
was not reopened. Existing Review evidence is not recounted as a new parent-only
union acceptance. Neither empty searches nor notification/history aliases
satisfy these source-specific request/result locations. The
[existing prerequisites](thread-source-prerequisites.md) remain intact.

## Populated creation metadata is separate from later section operations

The eight missing notification owners are2433,2454–2455 and2704–2708 in
`ServerNotification.json`: nonnull Thread.extra, Thread.section and its nonnull
alternative, plus ThreadSection appearance/non-null/null/id/name. Only2433 is
entry-specifically experimental; reading the experimental export does not
change that classification.

`app-server/src/request_processors/thread_processor.rs:6581–6605` explicitly
sets extra/section None for the fresh/pathless builder. The stored conversion
at6401 fixes extra to None. ThreadExtra is an empty representable struct
(`app-server-protocol/src/protocol/v2/thread_data.rs:163–167`); no reviewed
app-server Some constructor or extra assignment supplies its populated branch.
The apparent summary constructor is cfg(test). Persistence extra_config is
another field, not this output.

Stored section projection at `thread_processor.rs:6407–6416` is conditional:
it **can** preserve a section supplied by the new child's store. That is not
proof that ordinary fork inherits its parent's section. Public fork stages
project/daybreak only at5461–5474 and later copies name at5524–5537. It reads
the **new child** at4945–4961,5593–5605. The inspected local fork/create path
passes history/lineage, without copying the parent section:
`thread-store/src/local/paginated_fork.rs:15–85`,
`core/src/session/session.rs:1048–1110`,
`thread-store/src/local/create_thread.rs:11–68` and
`state/src/model/thread_metadata.rs:285–340`. This establishes an unmet
pre-snapshot child-section prerequisite, not impossibility across all stores
or external metadata producers.

Start/fork snapshots are constructed before their replies
(`thread_processor.rs:1652–1664,5689–5710`). A later move cannot refresh an
already constructed notification. Public start/fork/review params expose no
section/extra assignment; section moves address an existing thread and emit
no ThreadStarted. Exactly three stock started emitters are fresh start, fork
and detached review. Read/list/search/section CRUD results, null section,
or source-thread membership cannot qualify section-bearing started output or
nested appearance:null. Existing [section response evidence](thread-section-values-qualification.md)
does not establish this notification. No timing-selected race or fabricated
store/history/frame is introduced.

## Immutable source binding and unchanged acceptance

The17 physical nodes retain their exact IDs, canonical hashes, states, tests,
coverage and implementation modules. Canonical JSON uses sorted keys,
two-space indentation, UTF-8 and a final newline. Only append-only evidence and
limitations are added. Every other contract and all485 requirements stay exact.

Four bounded source reports provide36 distinct complete causal files, all
byte-equal to unique members of the official source archive, SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`:

| Report under `/tmp` | SHA256 |
| --- | --- |
|`samgita-collaboration-inner-null-source-20261029.md`|`9734b940c6eca2f7e61f9a1c2de4c1a59d318a391a767c74a7b280324f5fa319`|
|`samgita-thread-search-source-prereqs-0791257-20261029.md`|`ea0757f5ed1c0716cb1c0db27fe649415dd53ace7f04ebe23618a507a12cb6c5`|
|`samgita-image-saved-path-null-source-20261029.md`|`923b07a9905b38e907164fe80861cdb8097a34a9a58957eba1b52fca22d37139`|
|`samgita-thread-started-extra-section-source-20261029.md`|`a7032aa302210ebfa28154371b8b76d33322305c29ae4a99e83e1e2b3d225a77`|

Restricted candidates identified while reading the reports receive no field
metadata changes or runtime credit. No security, credential, authentication,
authorization, approval, sandbox or permission test or audit is run. Source
closure is distinct from enabled native success; no mock or retained alias
replaces that missing evidence.

## Metadata-only qualification

```sh
python3 -B /tmp/samgita-ordinary-output-boundaries-binding-20261029.py \
  5105136c2e90fb8ada2388bca80829dd4b486093
```

The binding passes, including fresh `scripts/codex/inventory.py --check`.
All17 exact nodes and36 complete archived source files match. Only those rows'
evidence/limitations and the runner's fingerprint literal change. All1,761
other guarded hashes stay exact, and every preceding17-step command, result,
166/23 case count, deadline and original log hash is rebound. No new runtime
suite, native output, provider/platform success or field-state credit is added.

Reviewed fingerprint is
`07d14270bb3eb43567b78fb6a8811369d43c1e7f266ac599f41022f0652d963b`.
Binding `/tmp/samgita-ordinary-output-boundaries-binding-20261029/binding.json`
has SHA256 `c18574e29f79027c6c5c0afbb68cda0888f11f009392f9b331f5650f30201f91`.
Inventory log SHA256 is
`0d98cdb3e17fb613b9e32450810e8b60557a2d449b6818a3d240a0663cb0aa19`.
Prior passing functional results/source hashes remain
`1b38f16cb3d65941d69a5d6c51748527d5753135c1a58d2e1ca12c1ce4f09a04`/
`d9c9aa4e33cf3fdf73844a47fd20795e1020038872bd14c0271384c1ee07ff08`.

The separate final command
`python3 -B scripts/codex/inventory.py --check --require-verified` still exits
**1** because unverified requirements remain. Original output is
`/tmp/samgita-ordinary-output-boundaries-completeness-20261029.log`, SHA256
`8c14de37787f2fa05e8a25dbe96cc1932f9d716f451c257ce98ba73ecbeea0cd`.
It is a retained failing gate, rather than an expected-failure success wrapper.

Counts stay **5,756 implemented /729 missing /136 blocked contracts**,
462 implemented/12 missing/11 blocked requirements and zero globally verified.
The blocked full-compatibility gate, A11, prohibited/broad/hosted checks and
unavailable external/OS success remain incomplete. Further runtime acceptance
for these exact owners requires the named genuine producer/profile or an
explicit target/evidence-contract decision; neither is silently supplied.
No release, publication, production migration or deployment occurs. Rollback
removes these17 metadata supplements and restores the reviewed fingerprint;
runtime/data remain unchanged.

Remaining implementation/acceptance prerequisites are concrete: a genuine
producer for the retained output branches; supported stored provenance for the
conditional search/section routes; resolution of the existing upstream
created_at precision defect; required verification currently prohibited by the
user; and unavailable real service/OS profiles. The separate A11 framework
pre-emission telemetry boundary remains blocked in
[the repair record](repair-qualification.md). These are not closed by repeating
the passing ordinary selection. Legacy no-emitter findings retain their pinned
source evidence and incomplete acceptance; no scripted peer becomes a real
producer. There is no automatic phase/release approval or complete-goal claim.
