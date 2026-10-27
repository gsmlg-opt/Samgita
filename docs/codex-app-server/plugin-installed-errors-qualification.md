# Native installed-plugin partial inventory

Actual `plugin/installed` now has populated marketplace-load error evidence
alongside retained valid suggested metadata. Repairing one malformed source
clears only its diagnostic; exact restoration and a distinct cold process
reproduce it. Protocol and driver runtime are unchanged.
Base: `b6e65b70c9203f34096c798d26a2feab8ea752ac`.

## Producer and effects

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Six complete source/archive members and both canonical schema nodes match.

`core-plugins/src/marketplace.rs:446–469` continues discovery after individual
manifest errors, preserving each original path/message. Its decoder at512–527
reads the current file. `marketplace_context.rs:33–91` combines valid inventories
and errors. `app-server/src/request_processors/plugins.rs:887–955` separately
retains installed or explicitly suggested plugins, removes empty marketplaces
and maps actual load errors to this method's public response. This differs from
marketplace/upgrade configuration errors and plugin/read declaration metadata.

Two owned roots contain one valid inert local plugin and one marketplace whose
bytes are exactly `{}`. Eight real plugin/installed calls cover repeated initial
discovery, a valid-empty replacement, exact malformed restoration and a distinct
cold-process repeat. Each response must preserve the independently prescribed
good marketplace path/name and sole suggested plugin ID/name/local source with
installed:false/enabled:false. Its exact malformed error must name the bad
manifest path, with the complete native diagnostic:

```text
invalid marketplace file `<owned bad manifest path>`: missing field `name` at line 1 column 2
```

The expectation follows the fixed bytes, required-name decoder and source error
wrapper; it is prescribed before execution, rather than copied from the reply.
Replacing only bad content with a named valid empty marketplace returns no
errors and leaves the good result intact. Restoring `{}` restores the original
error. Exact source-tree snapshots discriminate current discovery from stale
cached diagnostics or loss of valid rows. A distinct cold native PID reproduces
the original result without installation or inference.

Sixteen captured original requests have exact bytes/maps and unique correlated
replies: eight plugin/installed, six loaded-list and two diagnostics calls.
Capture stays24 frames/4KiB; responses65KiB, source files8KiB, tree64 paths/1MiB.
Requests stay5s and the case60s. Config/catalog/provider/support bytes remain
exact. Both shutdowns check cleanup completion, closed Port and absent owned
native PID; the existing failure/model cleanup remains. YOLO is fixed setup.
No plugin activation, hook/tool/thread/model operation, remote dependency or
security/permission behavior is exercised; the inference journal stays empty.

## Checks and boundaries

Initial actual native **1/0**; the two ordinary plugin modules pass **2/0 at
501432 and987654**. Driver compile/format, strict Credo546 and inventory
consistency pass. All379 guarded sources are stable and all378 prior sources
remain unchanged;770 official exports and15 input descriptors are exact. Earlier
unrelated full ordinary matrix, isolated-consumer, root/static and assembly
evidence retains source equivalence; those checks are not claimed freshly run.
No mixed/broad suite, prohibited test/audit or hosted workflow was executed.

Exact commands/logs/source guard: `/tmp/samgita-v377-run.py` and
`/tmp/samgita-v377-functional-checks/final/`. Source review:
`/tmp/samgita-v377-ordinary-gap.md`, `/tmp/samgita-v377-final-review.md`.
The final binding records their hashes, test/log/source hashes and exact physical
owners4526/4527 (`MarketplaceLoadErrorInfo.marketplacePath` and `.message` in
PluginInstalledResponse). Only those become scoped implemented. Parent4639 and
explicit-suggestion input4524 receive supplemental evidence; other response/error
aliases gain no new state.

Contracts: **5,050 implemented /1,505 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
continues to fail. Other error causes, remote marketplaces, all filters,
transports/OS, unreachable legacy emitters, A11 and external/platform/full-goal
acceptance remain incomplete. No package publication or deployment occurred.

Rollback removes this isolated test and its exact evidence only; retain existing
runtime, fixtures, qualification and historical records. Continue independently
reachable ordinary behavior groups.
