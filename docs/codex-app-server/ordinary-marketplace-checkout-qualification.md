# Ordinary native marketplace selectors and checkout/delete effects

This unit follows `bfa90249983638d697721805cf26705654111b9c` on `main`.
Official Codex is `rust-v0.163.0`, source commit
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Tests verify both executable input and actual native PID executable bytes. Every
app-server frame comes from that binary. Peers supply bounded HTTP/HTTPS content
only; they never manufacture app-server responses or events.

Fixed YOLO (`never` / `danger-full-access`), synthetic local identity and owned
HTTPS configuration are setup. No security, credential, authentication,
authorization, permission, approval, sandbox, trust or TLS outcome is tested.
Historical mixed profiles, audits, broad suites and hosted workflows remain
unrun/incomplete under the current verification restriction.

## Six physical owners

Only these six physical `ClientRequest.json` contracts change from missing to
scoped implemented. Eight already implemented request/response entries for
`plugin/list`, `plugin/share/checkout`, `plugin/share/delete` and
`plugin/share/list` receive supplements without changing state. No equal-hash
reference, alias, union, neighboring field or entire method gains promotion.

| Index | Physical pointer | Native behavior |
| --- | --- | --- |
|274|`/definitions/PluginListMarketplaceKind/enum/1`|`vertical`, GLOBAL collection=vertical; warm/warm/cold descriptive lists|
|275|`/definitions/PluginListMarketplaceKind/enum/2`|`workspace-directory`, WORKSPACE catalog and installed reads|
|276|`/definitions/PluginListMarketplaceKind/enum/3`|`shared-with-me`, separate workspace/shared catalog and installed reads|
|277|`/definitions/PluginListMarketplaceKind/enum/4`|`created-by-me-remote`, USER catalog and installed reads|
|1509|`/oneOf/81/properties/id`|Integer `-1` then string `"-1"` checkout across distinct native generations|
|1514|`/oneOf/82/properties/id`|One integer1514001 delete with independently observed effects|

The four canonical literal node SHA256 values, in table order, are
`75f5cdc0528cecd6f8997f519a9fe078ebad7a2e8b67bbc3efb754e583800c38`,
`e0366cf2cc4249bfec3ea041eb2500fb453bf251ecf63a975808bb15e84a830d`,
`1f7200122edc1304fe247834d1b6f7b6a4aa7bff2dd78decf2d55f70b7555dc9` and
`ff085318e97bcc8b9407c13be59d8f382728ad64d45e67c1496ed5b2998af7f0`.
Both distinct ID owners have canonical reference SHA256
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.
Checkout/delete each select their unique actual method and root variant, require
the unchanged RequestId definition, validate exact sent bytes and correlate typed
response IDs. The equal reference hash does not combine their ownership.

The binary-generated experimental ClientRequest SHA256 is
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
The source archive's shipped schema is a distinct artifact; no byte equality is
claimed. Exact source archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.

## Catalog and filesystem oracles

Remote catalog tests require seven explicit business reads: warm WORKSPACE,
shared, USER, WORKSPACE; cold USER, shared, WORKSPACE. Each catalog has two
independently authored Unicode plugin identities/versions/display names/keywords
in beta/alpha order. Native conversion must preserve those descriptive values.
Installed snapshots have separate exact scope/count checks; concurrent joins
receive no invented cross-route ordering guarantee. Required policy/share fields
remain opaque setup and receive no permission behavior credit.

The second native process must first finish observed startup reads, including
exactly one USER and one WORKSPACE refresh of the warm-populated caches. A marker
written only after confirmed warm shutdown distinguishes those startup reads
from cold explicit RPCs. The original seven business reads remain required.
The separate fixed vertical profile makes three actual curated list calls and
requires only the two observed per-process featured startup reads. Native
threads, turns, model calls, workspace changes and execution remain absent.

The checkout peer serves a deterministic real gzip/tar containing three inert
Unicode files. Warm checkout must actually extract those bytes and create the
marketplace/local mapping. An explicit local marker edit precedes shutdown.
A distinct cold native repeats checkout with the same remote identity and a
different typed ID; exact edited bytes and the mapping persist, and the bundle
is downloaded only once. The backend independently reads the real files/mapping
before the cold detail reply and before DELETE.

One delete produces a separately persisted dependency-side DELETE204/effect
record, removes the actual local share mapping and retains the edited checkout
files and marketplace. A final real native share listing is empty. An empty
response alone is insufficient. Exact business sequence is detail1, scope1,
bundle, detail2, scope2, DELETE, created-empty; outgoing native inventory is14
frames/12 responses. Catalog inventories are17 frames/15 responses remotely
and13 frames/11 responses vertically, across two distinct native processes each.

All cases retain60s total/5s request limits and bounded captures, queues, message
sizes and peer request counts. Catalog peer lifetime follows the enclosing test
and owned-process cleanup; checkout behavior has30s and its peer50s. Cleanup
requires the actual owner DOWN, completion1, Port absence and native PID absence;
no process-cleanup, replay, database guard or runtime code changes.

## Exact immutable producer bindings

Archive members and extracted source bytes were compared directly. Paths below
are relative to `codex-rs/` at the pinned commit.

| Source | SHA256 |
| --- | --- |
|`app-server-protocol/src/protocol/v2/plugin.rs`|`9e4686a275660635aa8328e54162bdced484ffb3ec059e372f6e272bc7430436`|
|`app-server-protocol/src/protocol/common.rs`|`ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3`|
|`app-server/src/request_processors/plugins.rs`|`78268f03497b38a9e02bc00b765b0929a7f50cd5c4df2378180d9625a51181de`|
|`core-plugins/src/remote.rs`|`890446011fcdab53516a3148e34b7b6780b1e2064fc0539dc7471dbca71c4075`|
|`core-plugins/src/remote/share/checkout.rs`|`24f456b405a4bc2fc548318a808bef4f87f3423e4f4b9f6fc299c6770794a965`|
|`core-plugins/src/remote/share.rs`|`6c8df6a479270a87530055111f620bfdd27e65f1cead9673cb554464bd9595d2`|
|`core-plugins/src/remote/share/local_paths.rs`|`f9bcf28b2306e10e15694d690c8a1898630879c0e5e26ea34528a26dad71030d`|
|`core-plugins/src/manager.rs`|`4eebf620702838b0f373379395029b2400e6bb158c932cf03f490a9d4e9bbb5e`|

Enum declarations are in plugin.rs158–178. Processor548–610/678–792 selects
catalogs; remote.rs864–970/1207–1275 joins source/installed snapshots and
2200–2284 builds queries. Processor1407–1467 delegates checkout/delete.
checkout.rs37–163/186–222/255–391 implements extraction, mapping and cold reuse;
share.rs279–301 deletes remotely before removing mapping, retaining local files.
local_paths.rs38–46/88–113 removes the empty mapping file. Manager2890–2935 and
3433 onward refresh all cached catalog scopes during native cold startup.

## Focused results and preserved corrections

The final focused command runs a reviewed three-case selection twice and root
strict Credo in the verified environment:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-marketplace-checkout-final-focused-20261028.py
```

Both seeds501432/987654 pass3/0 in5.0s; strict Credo passes across627 files.
The only subsequent test change replaces the obsolete candidate module comment
with `@moduledoc false`; the final combined selection checks its delivered bytes.
Logs are in the command's same-named evidence directory.

| Evidence | SHA256 |
| --- | --- |
|Focused501432|`9feddd36a56896c5d62bbf4c0e5207e38dbde9e05db68cea40c5533f91a1f822`|
|Focused987654|`abd6c2b9a02f6a37eba9b7fe1b6008e238488f00a1a9c70724401d3c79afda11`|
|Focused strict Credo|`6bda4a19fbf1ca18537c15ba1b99b08f0f5e262e7ced4508d4516664a0bf9d71`|
|Marketplace test|`81531855445530f66a206b4cb1b2274562f84e09d2a3934571444490d513e6da`|
|Checkout/delete test|`f615fec1c049967614e3e534224c1846e7f80c1a7ba0ee1857cc6f0676cfaaec`|
|Marketplace peer|`468c6a43690707199f921206fc8440c2cace30e8c032b5ab02fda890cb002f02`|
|Checkout/delete peer|`2f0faa131dc0802e9f6075c6d39c373ebe197796ac62e6ddf9f209cf6c0d9797`|

Original failing logs remain in `/tmp/samgita-ordinary-marketplace-checkout-focused-20261028`
and the corresponding diagnostic/diagnostic-v2 directories. The copied `/bin/sh`
is1,217,736 bytes and exceeded the original1MiB snapshot ceiling. The first
diagnosis incorrectly identified ClientRequest (actually306,165 bytes); that
provisional schema exception was withdrawn. Only the owned copied `bin/sh` now
uses its actual source size; all other checkout inputs retain1MiB and unchanged
byte snapshots. The source-only binding report's provisional diagnosis/hashes
are superseded by this record.

The original catalog fixture also counted real cold USER/WORKSPACE startup
refreshes as business reads. Exact source explains those requests. The explicit
post-shutdown marker and startup barrier now observe them separately without
changing seven business reads, native behavior, assertions or deadlines.
The final draft's only Credo issue was an overquoted fixed ID-node string;
an equivalent heredoc preserves its canonical bytes/hash and all assertions.

## Final combined-source functional qualification

The reviewed runner now selects96 files/164 native cases. Its guarded source
fingerprint is `595e7ac0925f0a125cf62310a36bdb5d88e26a17033200bf1421b41b96b59975`
across1,735 sources. Only these four additions, six manifest promotions/eight
supplements and the reviewed runner differ from the preceding source snapshot.
All existing command bounds, selected WebSocket cases and consumer/static/build
commands remain unchanged. Preflight proves1,729 prior source hashes unchanged,
only the six selected promotions/eight supplements, and unchanged command bounds
and prior arguments after removing the two added test filenames.

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-marketplace-checkout-final-20261028
```

All14 reviewed steps pass against1,735 identical before/after guarded hashes:
three selected WebSocket seeds455834/501432/987654 (each16 total,13 excluded,
zero failures), driver format/compile,164 native cases at501432/987654
(316.641s/319.043s), outside consumer1/0, inventory consistency, warning-free
umbrella compile, root format, strict Credo across627 files, Dialyzer and assets.
The enclosing native command bound remains320s; it was not increased. These
results qualify this selection only, preserving the earlier failed gate.

| Final report/log | SHA256 |
| --- | --- |
|Preflight|`48d45e6d0b5c9c340255af8be695931b8b732e4f7d9fe2b55e6f5a5353ea1a57`|
|Results|`741f7d6373ac8da97ba3d83a5c80ee30363a586e2950930a0b5470f6210e5b01`|
|Before/after source|`e08a7e948162f2c23e45661307e73adf9c84f3626f8b73f778cd903683554a8d`|
|Native501432|`5cf3ec1775f56f28ffe8e046be9440c5254237020e579fd465c3edc5a1a5a3cb`|
|Native987654|`96d3f3cf486ca6d354fe4c633ae56558fc97c1d0654823d52f5b0109c78cd4da`|
|Outside consumer|`4a4ab40e1ad129e2dced7209e956f77285259583b9a36146743f414970fad1f2`|

Command-plan SHA256 is
`3c60a7c183eef54f7234eb71069efb04e7c8f502281c2e3e5d07243313055700`.
No prohibited check, hosted workflow or audit runs.

The [preceding161-case cleanup failure](ordinary-lifecycle-effects-qualification.md#combined-source-result-and-unresolved-cleanup)
remains unresolved. A passing new selection cannot retroactively repair that
failed gate or establish its helper-side cause. Ledger is5,658 implemented/
827 missing/136 blocked contracts,462 implemented/12 missing/11 blocked
requirements; zero globally verified. A11, prohibited/broad/hosted checks,
unavailable emitters, real external/other OS profiles, native timestamp cursor,
full goal, publication and release remain incomplete. No platform database
recovery rerun, production migration, live service change or deployment occurs.
Rollback removes only this unit's added tests/peers/runner entries, six promotions,
eight supplements and documentation, preserving all existing runtime repairs.
