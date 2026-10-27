# Native plugin hook declaration inventory

Real pinned Codex now has populated local `plugin/read` declaration evidence.
Independent expected keys distinguish source order, native event order, matcher
groups and handlers. Changes, temporary source removal, exact restoration and
a distinct cold process reproduce the expected current inventory. Protocol and
driver runtime are unchanged. Base: `b788832cc9fa2f8f3a623de46ec6df709633e82d`.

## Producer and observable behavior

The target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Eleven complete source/archive pairs and both exact canonical schema nodes match.

`core-plugins/src/manager.rs:2546–2764` reads uninstalled local plugin details.
Its legacy manifest path loads explicitly ordered hook files; declarations in
`hooks/src/declarations.rs:12–37` preserve each source/event/group/handler key.
`app-server/src/request_processors/plugins.rs:1166–1175` projects those actual
declarations to public key/eventName maps. This producer is distinct from the
executable hook registry and the `hooks/list` diagnostic catalog.

The fixture creates an inert local plugin with two explicit JSON sources. The
first deliberately writes SessionEnd before PreCompact, while the independently
prescribed native result puts three PreCompact handlers before SessionEnd.
The second source's PostToolUse follows both. Exact five-element map equality
checks event values and keys including source path and group/handler positions.
Changing only PreCompact to PostCompact replaces precisely the first three
declarations. Holding the first source aside leaves only the second declaration;
restoring exact original bytes restores all five. Each state is read twice.
A distinct cold native process repeats the original inventory twice.

The existing supported launch helper enables local plugin metadata after
initialization and restores exact config bytes. Both launches explicitly retain
YOLO defaults. No plugin is installed or activated, no hook/tool/thread/model
operation is requested and the actual inference journal remains empty. Inert
prompt/agent descriptors qualify declaration inventory only. They do not prove
execution, event notification or a legacy production emitter.

Nineteen original outgoing requests have exact bytes/maps and unique correlated
replies: ten plugin/read, seven loaded-list and two diagnostics calls. Capture
stays24 frames/4KiB; responses65KiB, source files8KiB and tree32 paths. Requests
remain5s and the case60s. Config/catalog/provider/support inputs and restored
complete source trees are exact. Both owned native shutdowns check completion,
closed Port and absent native PID; existing failure/model cleanup is retained.

## Checks and remaining scope

Initial native **1/0**, focused **1/0 at501432 and987654**, driver compile/format,
strict Credo545 and inventory consistency pass. All378 guarded sources remain
stable and all377 prior sources are unchanged;770 official exports and15 input
descriptors remain exact. Prior unrelated matrix, isolated consumer, root/static
and assembly evidence retains source equivalence, without a new-run claim.
No mixed/broad suite, prohibited test/audit or hosted workflow was run.

Commands/logs/guard: `/tmp/samgita-v375-run.py` and
`/tmp/samgita-v375-functional-checks/final/`. Source and independent review:
`/tmp/samgita-v375-ordinary-gap.md`, `/tmp/samgita-v375-final-review.md`.
The final binding records their hashes, exact test/log/source hashes and physical
owners4681/4682 (`PluginHookSummary.eventName` and `.key` in PluginReadResponse).
Only those become scoped implemented; already implemented parent4668 and
plugin/read request/response receive supplemental evidence. Equal-shaped hook
notification contracts receive none of this method-result evidence.

Contracts: **5,048 implemented /1,507 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
still fails. All handler execution/event variants, other transports/platforms,
unreachable legacy emitters, external providers, A11 and the full goal remain
incomplete. No package publication or deployment occurred.

Rollback removes this isolated test and exact supplemental evidence only;
preserve prior runtime, qualification and historical records. Continue the
remaining reachable ordinary behavior groups.
