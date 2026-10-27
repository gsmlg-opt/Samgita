# Native Git ref and sparse materialization

Real Codex now has positive marketplace branch-selection and sparse-checkout
evidence. A nondefault branch selects independently known A content while source
main remains B; native sparse materialization excludes a known tracked nested
file. Warm/cold duplicate additions retain the checkout and make no further
HTTP requests. Protocol and driver runtime are unchanged.
Base: `b4b4f1b339b9d8e2c1b77af5a52a92f1afb6fdd2`.

## Real source transport and native effects

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and source archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Nine complete source members and both canonical schema nodes freshly match.

`core-plugins/src/marketplace_add/source.rs:18–85` selects the explicit Git ref
and forwards sparse paths. Absolute directories are Local sources, and file
URLs are rejected, so their earlier tests cannot qualify these Git selectors.
The new fixture serves one tiny real owned repository through installed Git's
HTTP backend on an ephemeral loopback listener. It transfers real refs/objects;
it does not emulate app-server replies, replace Git or substitute a file URL.

`marketplace_add/install.rs:6–41` performs the native clone, sparse setup and
checkout. Public `marketplace/add` selects `fixture-selected` at commit A with
two prescribed sparse paths. Source HEAD/main remain at the distinct B commit.
The installed revision and three exact manifest/plugin/Unicode-marker files
must match A and differ from B. An independently checked tracked A tree contains
the nested excluded file, which must be absent from the native working tree.
This proves materialization, without claiming Git object-transfer savings or
execution of the inert plugin metadata.

The actual native-written TOML must contain exactly the expected marketplace
source/ref/sparse declaration; setup never writes that declaration. After the
first add, complete bounded source/installed trees, config, HTTP journal,
catalog/support inputs and the empty provider journal remain exact. Identical
warm and distinct cold-process adds return `alreadyAdded:true`; the unchanged
HTTP journal proves no further HTTP clone in this fixture. No model turn,
plugin activation, external remote service or Samgita platform is needed.

Ten selected original outgoing requests retain bytes/maps and unique correlated
responses: three adds, two diagnostics and five loaded-list reads. Capture is
bounded16 frames/4KiB; tree snapshots256 paths/1MiB. The real HTTP/backend journal
tracks accepted attempts separately from successful exchanges, bounded64 attempts,
2MiB bodies/backend output,16KiB backend stderr/headers and64KiB journal. Backend
work stays3s, socket reads2s, native requests/startup5s and the case60s.
Backend/native/helper PIDs, transport cleanup completion, closed Ports and the
closed listener are checked. Model cleanup retains the unchanged TurnFixture.

## Fixture cleanup repair and checks

The first helper source revision set its socket timeout only after header
parsing and used unbounded server shutdown. A single accepted unfinished
connection reproduced close exceeding the fixed3s observation. The retained
old-helper diagnostic exits1, then releases its owned client and confirms clean
cleanup. The same diagnostic on the repaired helper exits0. Accepted sockets
are now bounded before parsing, active connections are interrupted on close,
and the request loop/join are bounded. Unfinished/failed attempts consume the
request budget. This is a fixture lifecycle repair, not a native Codex defect.

A retained ordinary lifecycle regression uses an observable real-accept barrier,
keeps the client open without headers while close runs, checks bounded close and
requires one consumed attempt with no backend success. It passes **1/0**. No
sleep, inflated deadline, permission/credential outcome or security audit is used.

Initial actual-native **1/0**, final focused marketplace group **2/0 at501432 and
987654**, Python syntax/lifecycle, driver compile/format, strict Credo544 and
inventory consistency pass. All377 guarded sources stay stable; all374 prior
sources,770 exports and15 descriptors are exact. Prior unrelated matrix,
consumer/root/static/assembly checks retain source equivalence without rerun
claims. No broad or hosted suite was executed.

Commands/logs/guard: `/tmp/samgita-v374-run.py`,
`/tmp/samgita-v374-functional-checks/final/`. Source report and independent
reviews: `/tmp/samgita-v374-ordinary-gap.md`,
`/tmp/samgita-v374-final-review.md`, `/tmp/samgita-v374-regression-review.md`.
The binding includes their hashes, old/new lifecycle diagnostic logs and exact
physical owners4331/4333 (`MarketplaceAddParams.refName` and `.sparsePaths`).
Only those become scoped implemented; source and three response owners receive
supplemental evidence.

Contracts: **5,046 implemented /1,509 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
still fails. No nonsparse control, arbitrary ref/sparse/error/concurrency cases,
real external repository, other transports/OS, or complete marketplace/provider
compatibility is claimed. Prohibited checks and hosted gates, A11 and
legacy/external/platform acceptance remain incomplete. No publication or deploy.

Rollback removes these isolated fixtures/tests and exact supplemental evidence
only; preserve runtime, previous qualification and historical records. Continue
remaining reachable ordinary behavior groups.
