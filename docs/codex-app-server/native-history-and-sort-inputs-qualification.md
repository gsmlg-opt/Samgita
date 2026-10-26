# Native history, sorting and initialization inputs

This unit qualifies seventeen exact canonical ClientRequest owners through actual
stock-native input consumption. It adds three functional modules and two local
Responses fixtures; the only changed shared code fixes ordinary native test
launch defaults to yolo. It adds no platform/runtime API or provider service.

Pin: rust-v0.163.0, source83086188ae0614bd882818ff1aa23f3194962012,
binary SHA256399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215.
All model traffic uses owned loopback synthetic Responses backends. Codex owns
the app-server responses, lifecycle, persistence and native control generation.

## ConfigurationUpdate production and current raw history

`native_configuration_update_values_test.exs` uses the dedicated
`configuration_update_fixture.py`. The configured provider ID remains fixture;
its name OpenAI satisfies the verified native name classifier. This is not a
real OpenAI service. The native feature and synthetic model support are enabled.
The peer returns ordinary assistant output only, never configuration controls.

Four explicit turns select medium → high → unchanged high → low. Applied native
settings barriers and complete actual provider controls distinguish the changes:
[medium], [medium,high], the same prefix, then [medium,high,low]. Request-level
effort stays medium. Complete native raw control notifications, stable prompt
cache key and exact whole outer persisted control rows establish the real
producer. After source close/reap, eleven actual user/control/assistant maps are
captured with full IDs, turn metadata, user timestamps and content classification.

A separate cold native receives those raw maps unchanged through unstable
thread/resume.history; complete delegated outgoing frames and response IDs are
checked. Imported control rows retain their raw maps without the outer native
annotation. Import creates no turn or inference. One deliberate followup creates
a new native medium control, identified by its actual annotated outer row and
position after the followup user. The provider sees only this fresh control;
the three imported raw controls remain durably unchanged. Counts are **4 → 4 → 5**,
with nine captured management frames. No outer annotation is supplied or forged,
and no cold raw-event emission is claimed.

Source `core/src/session/reasoning_effort.rs` constructs native controls and
suppresses redundant changes. Feature/provider/model gating is in client.rs;
the official ordinary reasoning-effort test prescribes the four-turn sequence.
The native envelope serializer, raw-history wrapper and API-history projection
explain the raw-versus-outer representation. This is ordinary configuration and
serialization coverage, not a provenance-policy or permission matrix.

## Independent native timestamp sorting and cold pages

`native_thread_sort_values_test.exs` creates two actual paginated threads and
three assistant-only turns. A later continuation of the first thread advances
its real updated/recency clocks. Bounded clock barriers separate observations;
raw SQLite millisecond values are read through a query-only connection. No rows,
rollouts or timestamps are manufactured or edited. Both selected list orders
must differ from created order; universal updated-versus-recency discrimination
is not claimed because ordinary turns can advance both clocks together.

Actual thread/list updated_at/recency_at and thread/search created_at/updated_at
requests cover both directions. Independent timestamp order, membership and
API timestamp projections govern full/first pages; list continuation uses the
unaltered first cursor and requires exactly the remaining item and terminal
null. The same matrices/cursors repeat in a distinct cold native before history
hydration, with threads remaining unloaded. Forty-five complete captured frames,
exact saved turn histories, source/config/catalog/journal bytes and exactly
three model requests remain. Created search continuation stays unqualified
because of the existing pinned cursor precision defect; no workaround is added.

The actual request processors map the two different sort enums independently
into native search/list storage. Native SQL selects raw created_at_ms,
updated_at_ms or recency_at_ms columns; an equal schema hash is not evidence
that the distinct search and list owners share behavior.

## Accepted controls excluded from durable and model history

`native_filtered_history_values_test.exs` uses `filtered_history_fixture.py`.
The trigger case captures the entire actual backend compaction_trigger produced
by a deliberately requested native remote-v2 compaction after an ordinary turn.
The Other case supplies the declared current Other literal as synthetic provider
data; the stock generic Responses decoder emits the complete actual raw native
Other notification. It is not a historical ghost snapshot or legacy producer.

Each separate cold native receives a genuine native user plus the whole
captured control unchanged in thread/resume.history. Exact actual frames,
correlation, idle/no-dispatch import and retained whole user data are required.
Both controls are absent from durable/API history. An explicit ordinary followup
must consume both user markers once, without a trigger, checkpoint, Other or
tool operation. Durable omission is checked before and after followup and close.
Counts are exactly **2 → 2 → 3** and **1 → 1 → 2**, with five/four captured frames.
Input acceptance does not launch another compaction or execution.

`compact_remote_v2_attempt.rs:172` is a genuine native trigger producer. Current
generic decoding/raw forwarding supplies the Other path; native history,
rollout and local-writer filters explicitly exclude both variants. Synthetic
current data and filtering coverage establish no real legacy/backend success.

## Explicit runtime initialization provenance

The unchanged `native_thread_start_source_values_test.exs` actually supplies
startup and clear. Independent provider metadata requires new and cleared on
the owning runtime, with exact native thread/turn references and isolated
markers. Four distinct native histories remain through clear and cold process
replacement; no earlier record is deleted or another inference started.
Eight whole captured requests and four provider requests establish consumption.
This input labels new-thread initialization; it is not a destructive clear
command, startup-hook test or post-resume provenance-restoration claim.

## Physical ownership, verification and limits

Forty-six complete official source files match the immutable archive. Group
closures contain26 configuration,9 sorting,19 filtering and8 initialization
files, with overlaps. Seventeen physical nodes are independently hashed, and
the actual thread/start, thread/resume, thread/list and thread/search reference
graphs resolve to their specific definitions.

| Exact owners | ClientRequest definitions | Owning functional module |
| --- | --- | --- |
| 102,426–429 | ConfigurationReasoning.effort and ResponseItem.oneOf14 | native_configuration_update_values_test |
| 430–432,441–443 | ResponseItem.oneOf15/17 and their type literals | native_filtered_history_values_test |
| 664/665,670/671 | ThreadSearchSortKey.created_at/updated_at; ThreadSortKey.updated_at/recency_at | native_thread_sort_values_test |
| 683/684 | ThreadStartSource.startup/clear | native_thread_start_source_values_test |

The initial configuration draft failed1/1 because its complete assistant oracle
omitted native content_item_kinds:[unknown]. The pinned image-preparation path
and context-fragments/annotated_content.rs:48–104 prove the classification.
Adding that exact expected field preserves full-map equality; the focused rerun
passes1/0. Initial strict Credo reports two nested capture helpers; extracting
the existing bounded send/capture bodies resolves them without changing limits
or assertions. The three-module focused run passes **4/0**. Retained logs:
/tmp/samgita-v320-owning-501432.log,
/tmp/samgita-v320-owning-501432-r1.log,
/tmp/samgita-v326-credo-initial.log and /tmp/samgita-v326-owning-501432.log.

Base4cf04afc076a4e1038b630122f1801a7a7f9b92b. Final commands/environment:
/tmp/samgita-v326-run.py; artifacts:
/tmp/samgita-v326-functional-checks/functional/.
The **52-file functional matrix passes103/0 twice**, seeds501432/987654,
**178.223/178.272 seconds**. Scoped format, warnings-as-errors compile, strict
Credo on502 sources, outside actual-binary consumer1/0 and29 fixture ASTs pass.
The **302-source guard** remains exact throughout the run. All prior297 files
except the ordinary-launch helper match base/current tested bytes; five focused
sources are added. The helper retains existing plugin flags and adds fixed
never/danger-full-access defaults. No behavioral assertion is removed or weakened.

| Evidence | SHA256 |
| --- | --- |
| Functional results | ba29fd83f30968794f0604ec307d75c7982537e708e79b85b99626e260f9d553 |
| Source guard | f3194e6ba833dce584283c20c4085b8dcbeebf3469a03a1fb56f17bdfe1f7ea1 |
| Forty-six files, seventeen nodes and request graphs | 92f31647915fb3642bbbb70472305cd1e0546618603634f8629a24cd8adbf3e2 |
| Resulting manifest | 2fc1459afd920eeb6ad2667df7718fb2290757728acd3e0c14fb96edb2220c1e |

Existing Session256-event/8MiB defaults,20s turn deadlines, finite case/file/
collector bounds and owned cleanup remain. New capture caps are16/64/8 frames;
history maps and collectors are bounded to1MiB, rollout reads to4MiB/2048 rows/
262KiB per line. Original configuration/source files remain exact through
native shutdown; provider owner completion/Port checks precede removal where
explicitly owned by the new fixtures. No arbitrary timeout increase or retry
is used to obtain a pass.

Final binding permits exactly the seventeen owners, retaining identities,
planned tests, other records and all requirements. Inventory passes; strict
completeness exits **1**. Contracts: **4,983 implemented / 1,572 missing /
66 blocked**. Requirements: **462 implemented / 12 missing / 11 blocked**,
zero verified. Linux-stdio/local synthetic behavior is the evidence boundary.
Full history/sorting/defaults/lifecycle, genuine legacy producers, real external
providers, other OS/transports, A11 and full-goal/release gates remain incomplete.
Prohibited security/credential/authentication/authorization/permission/approval
tests and audits, broad suites and hosted workflows stay unrun. No publication,
production migration or deployment.
