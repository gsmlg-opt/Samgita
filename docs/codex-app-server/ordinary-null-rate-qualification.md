# Explicit null in an ordinary native quota read

This unit follows `e58f4f98f651d9367f7c8c1b1dffd8ed9d7040fd` on existing
`main`. The target remains official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`,
archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The profile uses explicitly owned Linux x86_64 musl stdio processes and fixed
YOLO setup. No security, credential, authentication, authorization, approval,
sandbox or permission behavior is tested. Audits, broad mixed suites and hosted
workflows remain unrun, with their gates intact and incomplete.

## Behavior, source and bounded dependency

The existing ordinary data-read case sends an optimized quota request with
`excludeResetCreditDetails:true`. It remains unchanged. A second tagged case
sends a **present `params:null`** to real native `account/rateLimits/read`.
Omission and another method's nullable input cannot satisfy this case.

Native processing [defaults absent parameter values](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L195-L202).
The [two derived-default flags are false](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/account.rs#L312-L326).
The [read path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/account_processor.rs#L1225-L1231)
therefore adds a separate reset-detail GET alongside the quota GET. The existing
fixture would correctly reject that extra request; merely changing the old
request to null would not account for this behavior.

Only the new fixture scenario accepts that read-only endpoint. It returns the
complete constant DTO `{"available_count":0,"credits":[]}`; the required fields
come from [the actual backend type](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/backend-client/src/types.rs#L27-L31).
No credit row, reserve, consume, billing mutation or account result is selected
as an oracle. Default fixture routing still rejects the extra endpoint. This
loopback HTTP dependency does not emulate an app-server: the immutable real
executable receives both RPCs and generates both responses.

The case checks independently prescribed quota values in warm and distinct cold
native processes: primary 37%, 60 minutes, reset 2000000100; secondary 12%, 1440
minutes, reset 2000000200. Backend journal rows independently retain the original
3600/86400-second windows. Only those numeric response fields are inspected.
Synthetic identity remains opaque setup, without header or access assertions.

Exactly four business HTTP GETs occur: two `/backend-api/wham/usage` and two
`/backend-api/wham/rate-limit-reset-credits`, each with an empty query and a
recorded 200 result. Native `tokio::join!` leaves sibling arrival order
unspecified; the complete ledger checks multiplicity without inventing an order.
Startup reads retain the existing finite bounds and three-path allowlist.
Unknown requests, fixture errors, profile/thread/message data reads and model
requests remain absent.

Each process emits six outgoing frames: initialize, initialized, diagnostics,
loaded-thread list, quota read and loaded-thread list. The complete capture has
12 outgoing frames, 10 unique requests and 10 exactly correlated native replies.
The quota IDs are integer `1005001` and then string `"1005001"`. Original encoded
bytes must include `params:null`; capture prefixes survive the cold restart.
No thread, turn, task, inference or tool execution occurs. Original fixture
inputs, empty workspace and histories, ready/empty Session state, real helper
ACK, native/helper reaping and explicit dependency shutdown stay required.

The source-only report archive-matches the five causal account/DTO/client files
and separately inventories restricted request identities:
`/tmp/samgita-client-request-next-20261028-source-report.md`, SHA256
`8c781bfb6cacca7321ff4e9e2cd15527409be6b12ff70b687c9ec952bb5f012e`.
The changed ordinary fixture SHA256 is
`e69015fb0979cddb5c4752934ae951b55a079929bc7a40a11cbf724bc218cb12`.
The original case and nine owning assertion/lifecycle helper bodies remain
byte-identical. No timeout, buffer, previous assertion or production code changes.

## Exact physical owner and focused qualification

Only owner **1010** gains scoped `implemented` evidence:
`ClientRequest.json#/oneOf/145/properties/params/anyOf/1`, exact node
`{"type":"null"}`, canonical SHA256
`b7c373d0981a5441c9dd775ad89a68ba691af04e4da70eaeaacaaf54549837fb`.
The whole root SHA256 remains
`92d920b10b9ce7871e21f49573275bb931a58ad7fd367ab71b3716edbb6a0352`.
IDs, node hashes, schemas and the immutable target stay unchanged. No equal-hash
alias, standalone nullable node, whole method or globally verified state follows.

The full owning file passes **2/0 at seeds 501432 and 987654**, 3.859s and
3.809s including startup. Driver format/compile and strict Credo pass. All
1,760 guarded source hashes remain identical during this focused check.

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-null-rate-focused-20261028.py
```

Results JSON SHA256:
`3e5bc358e6a807dc314d716061a85b3e499dd6806e44849ca745be54a280c375`;
source JSON SHA256:
`eb0ae047ec43c0c84a35360280e4d62020c3dc19f14cfb9ce03ca237ebb17543`.
These focused results precede manifest/runner integration. Requirements remain
462 implemented /12 missing /11 blocked. Contracts become 5,736 implemented
/749 missing /136 blocked, with zero globally verified in either ledger.

## Final combined-source functional qualification

The main 165 cases, argv, assertions and 320s bound stay unchanged. The single
new case raises the separate extension count from 12 to 13, retaining its 120s
bound and all prior cases. All **17 reviewed functional steps pass** against
**1,760 identical guarded source hashes**:

| Check | Actual result |
| --- | --- |
| Selected neutral overflow/replay | 16/0, 13 excluded at each of 455834, 501432 and 987654 |
| Main native block | 165/0 at 501432 and 987654; 289.772s and 286.859s |
| Separate native extension block | 13/0 at both seeds; 22.148s and 22.047s |
| Owned cleanup phases | 4/0, existing ACK/exit/deadline requirements retained |
| Outside-umbrella consumer | 1/0 against actual pinned Codex, without Repo/Phoenix |
| Other checks | Driver format/compile, inventory, umbrella compile/format, strict Credo, Dialyzer and assets build pass |

```sh
MIX_ENV=test ERL_FLAGS='+S 2:2' devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py --output /tmp/samgita-ordinary-null-rate-combined-20261028
```

Results JSON SHA256:
`964333c09dee7bae33d85ff3ab97a3bfe79eb33a95264fe0225b545815bb07e2`;
source JSON SHA256:
`c19a680b608a20b819bb1edde5634c4047698a066503a3419339f4240475c566`.
The frozen source fingerprint is
`f3d2712193389a40996231db1a8969eaf2080a5308441737a3d76524563d8a12`.
Exact argv, individual results and log hashes remain in the evidence directory.
No prohibited check, broad mixed suite, audit or hosted workflow runs. These
functional results do not replace full compatibility or release acceptance.

## Production assembly and continuing prerequisites

Production code, configuration, dependency locks, migrations and shared cleanup
remain unchanged. The preceding [successful local assembly](ordinary-record-cache-qualification.md#local-production-assembly)
is retained for those inputs; no fresh production build or publication is claimed.
Comparison with its 2,304 copied inputs finds 2,295 unchanged; the nine differing
paths are ordinary tests/fixtures, the reviewed runner and compatibility documents.
The retained 20,083,133-byte archive SHA256 remains
`ed79ae51eac66b50e46e560395da4deb554dec4d7409d18fe531330d4b00a190`.

The further [notification source review](thread-section-values-qualification.md)
does not establish populated creation-section or extra-data producers. The
actual image serializer [omits an absent saved path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/ext/items/src/image_generation.rs#L38-L40),
so an omitted field cannot qualify explicit null. A separate quota-source review
finds that both model header/WebSocket parsers explicitly set the notification's
individual limit to None; the numeric backend mapper feeds a separate read
response. No genuine notification bridge is established. Its report is
`/tmp/samgita-ordinary-quota-notification-producers-20261028-report.md`, SHA256
`4d261a23443bf26e21b66f5b087dd95da955ecc4841137462462c6773c9c2bcc`.
These bounded reviews do not establish global unreachability or gain owner credit.

Continue independent permitted behavior work when a genuine producer and
deterministic observation are established. Official release metadata now
positively identifies a separate
[Linux musl app-server archive](https://github.com/openai/codex/releases/download/rust-v0.163.0/codex-app-server-x86_64-unknown-linux-musl.tar.gz)
for this same source tag, advertised archive SHA256
`bd587a5419f9b6fa488e4950b065c9127f7db0989388210a3785294b460cdf09`.
The next unit must verify its downloaded/extracted bytes and actual source
selector behavior as a separate immutable profile; the combined executable
pin stays unchanged. Metadata discovery alone gains no compatibility credit.
A11's pre-emission blocker,
source-proven absent legacy emitters, unresolved producer/artifact prerequisites
and historical intermittent cleanup cause, external/backend/other-OS success,
prohibited/broad/hosted checks, full compatibility and release stay incomplete.
No historical data, host configuration, live services, sibling repositories or
credentials change. Nothing is tagged, published, released or deployed.
