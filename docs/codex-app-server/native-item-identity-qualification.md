# Native item identity and shell provenance

Three physical canonical notification owners gain direct ordinary functional
evidence against immutable Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. The real executable produces all
events, history and shell effects. Fixed yolo settings are fixture setup.
No runtime, transport or provider implementation changes in this unit.

## User message identity

Owner2486 is `ServerNotification.json#/definitions/ThreadItem/oneOf/0/properties/id`.
The timeline profile previously required nonempty IDs and preserved them
through raw records, pagination and restart. It now adds an independent oracle:
the ID must be a UUIDv7 whose 48-bit timestamp lies between host times captured
before `turn/start` and after terminal collection. Started and completed user
items must equal the full prescribed item, retain the same ID in sequence,
and differ from the turn ID. The distinct assistant-ID assertion remains.
Both successful and failed turns use this check.

The oracle follows `protocol/src/items.rs:513–515,529–535`, which generates
`Uuid::now_v7()`, and `core/src/session/mod.rs:5260–5279`, which creates the
item independently of its optional caller client ID. The same item is cloned
for started/completed events at2709–2767 and forwarded unchanged by
`app-server-protocol/src/protocol/v2/item.rs:876–880`.

All existing assertions remain: canonical rollout ordinals, literal content,
full and paginated results, opaque continuation replay, first-cold reads,
original bytes, inference counts, error/recovery outcomes and confirmed native
process cleanup. The owning file passes **2/0 twice**, seeds501432/987654,
with warnings as errors and no repair round. Focused logs are
`/tmp/samgita-v301-user-id-{501432,987654}.log`.
Final file SHA256:
`39d08decdf0bb509957e23a690129934c2453b5e251818a7d4d85297fe086ef3`.

## Shell working directory and source

Owners2606 and2614 are the `cwd` and `source` reference branches in canonical
`ServerNotification.json#/definitions/ThreadItem/oneOf/6`.
`native_shell_delta_identity_test.exs` already checks literal `userShell` in
both lifecycle maps and preserves complete items through warm/cold history.
Two added assertions require started/completed `cwd` to equal the known
absolute fixture workspace, passed explicitly to the existing helper.

Pinned `core/src/tasks/user_shell.rs:150,188–207,291–312` takes the local turn
environment cwd and constructs both genuine command items with `UserShell`.
`app-server-protocol/src/protocol/v2/item.rs:921–950,1117–1126` forwards cwd
and maps the source enum. The existing test executes two distinct owned shell
turns, checks exact outputs and exactly one on-disk effect per turn, and proves
history/restart never repeats execution. Zero inference, original config bytes,
event/order bounds and native cleanup remain required.
Final file SHA256:
`a1817ebaa0e3025f9510594f96f40bf1d515942ba1f7ceeae1def5a16b054b24`.
This source-reference evidence covers `userShell`; other source variants do
not inherit evidence.

## Integrated evidence and remaining gates

`/tmp/samgita-v301-run.py` serializes the exact reviewed40-file matrix and
records commands in `/tmp/samgita-v301-functional-checks/functional/results.json`.
Both seeds pass **75/0**, in 125.550/125.206 seconds. Scoped format, compile
with warnings as errors, strict Credo on 490 sources, the outside actual-binary
consumer **1/0** and seventeen fixture AST checks pass. No check fails and no
deadline or assertion is relaxed.

| Evidence | SHA256 |
| --- | --- |
| Final results | `d2b0b191865ade7c8e88e52f012f5085bd1aa9e1791cda400c548c6f670fea64` |
| 278-source guard | `8052d70e388959e3b13c3f8ac14434943c8a380de256048784f21e1fb3f88981` |
| Pinned-source evidence | `39df3cf964d94cc93a2ada56aaca747ad565bc34607430c1841615c9ad34454d` |
| Resulting manifest | `91835625c1ce5cd36cc9b948615e47133c168f4953c8b8c270b1e443dd779753` |

Six complete producer files byte-match the immutable archive. Three exact
physical nodes, unique complete-record patches, original/current rows and
unchanged tested bytes are bound in `source-evidence.json`,
`manifest-binding.json` and `final-binding.json` in the same artifact directory.
Inventory consistency passes; strict completeness still exits **1**.

Contracts become **4,856 implemented / 1,706 missing / 59 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, with zero
verified. Other producers, malformed values, exports, transports and OS
profiles require separate evidence. Prohibited security/permission checks,
broad/hosted workflows, A11, unresolved legacy emitters, unavailable external
profiles, full-goal verification and release gates remain incomplete.
No publication, deployment or production migration occurs.
