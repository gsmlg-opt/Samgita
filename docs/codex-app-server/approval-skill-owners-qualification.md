# Ten precise approval/item and skill owners

This evidence-only audit adds **ten scoped implemented contracts**, with no
executable change and no verified promotion. The source-generated ledger is
**485 requirements: 0 verified / 462 implemented / 12 missing / 11 blocked**;
**6,621 contracts: 0 verified / 2,667 implemented / 3,954 missing**.

All evidence binds to committed actual-native tests for immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
There is no new native run in this audit. The owning
[cache/context](approval-cache-context-qualification.md),
[approval validation](approval-validation-qualification.md) and
[skill metadata](input-metadata-qualification.md) records contain the earlier
passing commands, exact source guards and remaining conditions. Combined-source
and hosted results remain separately required.

| Exact physical schema scope | New owners | Independent positive oracle |
| --- | --- | --- |
| ServerNotification, oneOf/42 serverRequest/resolved | method, literal, params | Actual method filter and singleton resolution associated with original thread/approval IDs in `native_approval_duplicate_replies_test.exs:224-238,326-327`; multi-file test 186-191 provides separate association |
| ServerNotification, live ThreadItem command alternative 6 | command | `native_command_cache_context_test.exs:76-119,165-179,267` parses native command into independently prescribed private-shell/printf argv; status/output/cwd/effects are separate oracles |
| ServerNotification, live file alternative 7 / PatchChangeKind add / PatchApplyStatus | file id, add type/literal, inProgress literal | `native_multifile_approval_test.exs:58-107,134-184,204-211` compares prescribed call IDs and complete changes, requires pending state before explicit decision, and checks real bytes |
| v2/SkillsListResponse SkillMetadata | dependencies/anyOf/0, interface/anyOf/0 | `native_skill_metadata_test.exs:74-86,103-123,153-174,211-265` compares complete independent ordered dependency objects and full eight-member interfaces through actual skills/list, reload/filter and cold stable reads |

The resolution assertion uses map-pattern association, **not exact map-key
equality**. It supports these selected params and original identities without
claiming the whole envelope's key set. The command comparison is argv parsing
equivalence, not byte-exact shell quoting. A nonnull interface with null members
does not qualify the outer null branch. No sibling schema owner, whole item,
full union, delete/rename, populated move_path, every decision/environment,
transport/OS/backend or approval lifecycle is inferred.

The coordinating owner independently recomputed every nominated node SHA256
from its physical pinned experimental schema and checked the four committed test
fingerprints before indexing. Exact ID/hash/owner list, patch and expected bytes:
`/tmp/samgita-approval-skills-owners-manifest-20261024/`; generation/review script:
`/tmp/samgita-index-approval-skills-owners-20261024.py`. Source-only proposals are
retained separately at `/tmp/samgita-approval-item-owner-audit-20261024.md` and
`/tmp/samgita-skills-owner-audit-candidates.md`; their source assertions were
checked against the committed tests before adoption. A11, unreachable legacy
emitters, external profiles and all full-compatibility gates remain incomplete.
