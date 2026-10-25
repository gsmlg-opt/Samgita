# Native thread-section membership

One functional scenario qualifies `thread/section/move` on the immutable
`rust-v0.163.0` [pin](design.md), source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
All protocol responses/state are stock native output. The loopback provider
supplies four assistant-only turns; no imported or fabricated history is used.

## Independent state and durable ordering

Four actual persisted threads A/B/C/D and two custom sections S/T begin
unassigned. Seven exact move maps establish S[A], append B with null anchor,
insert C before B, append A with null anchor, transfer C to T, remove B with
`sectionId:null`, then remove A with explicit null anchor. D stays unassigned.

`sectionId` is required and nullable; `beforeThreadId` is optional. Omitted/null
anchors append, while a real member anchors insertion. Native lists independently
check all threads versus explicit-null unassigned threads, concrete section
membership and exact ascending `section_position` order. Every page must end
without truncation. Ordinary sorting is used for omitted/null section filters;
section-position sorting is only used with a concrete section.

After the transfer, the old native PID must disappear before a distinct process
observes the nontrivial S[B,A]/T[C] state with no loaded threads. Exact original
completed turns and previews survive every move and that restart. The four-call
provider journal stays byte-identical: moving, querying and restarting cannot
dispatch another turn. Config/workspace, ready state and uncertainty checks hold.

Each of nine state observations checks six actual list maps, giving **54** exact
list captures plus **7** exact move captures. Complete outgoing envelopes and
response IDs match within a 128-frame/4096-byte bound. The local completion
collector keeps the fixed deadline and excludes the shared helper's separate
approval assertion. Existing helpers and production sources remain unchanged.
No built-in section restriction, security or permission behavior is tested.

The v170 source map archive-byte-matches eight immutable upstream files. The
native manager materializes/flushes a loaded thread and awaits the committed
store mutation before the response. Public list/read projections and ordering
come from that native state. The independent v172 source-only review approves
the final candidate and its non-circular state/history/journal oracles.

## Final integrated evidence

The eight-file functional block is the seven files in
[mode qualification](multi-agent-mode-values-qualification.md#integrated-checks-and-limits)
plus `test/native_thread_section_membership_values_test.exs`. Both complete runs,
`--warnings-as-errors --seed 501432` and `--seed 987654`, pass **19/0** in
36.389/35.825 command seconds. Compile/format, root strict Credo and the 231-file
source guard pass. No native failure, timeout increase or retained assertion
change occurs in this unit.

Exact commands/logs/source: `/tmp/samgita-v173-thread-membership-checks/functional/`.
Results/source SHA256:
`a041049c2fc022f1992e314eb7c9e03aab320012159b3299f57fbee5c73b3773` /
`ba428281eaf9118b48ecfd9b9dfd648844e9ba7fa3665bd59e7c858260390c06`.
Only three direct move owners, **6210–6212**, become implemented. The existing
list-filter owner, sorting/result siblings and notifications do not inherit
promotion. Contracts become **4,588 implemented / 1,974 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified
in both. Other transports/platforms/backends, real external services, A11,
complete compatibility and broad/hosted checks remain incomplete. Security and
permission-related tests/workflows remain unrun; no release or deployment occurs.
