# Ordinary native plugin reconciliation

This profile targets stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The app-server is real. Only installed-plugin metadata and the HTTPS bundle
dependency are local fixtures. No Samgita platform, remote account, paid task,
model, command, MCP or hook execution is involved.

## Real effects and exact message slice

Five sequential native `plugin/reconcile` requests prove:

1. One skills-only GLOBAL package downloads and materializes. The native result
   contains the literal plugin ID and skills-only declaration flags; both failure
   arrays are empty. Actual marker/skill bytes, remote-ID metadata and the complete
   native-normalized manifest, including release version, match independent literals.
2. Repetition returns the exact empty result and preserves cached bytes without
   another download.
3. A confirmed distinct cold native process reads the same cache and returns
   the empty result without another download.
4. A later empty installed snapshot reports the removed plugin's original
   declaration flags and removes only this fixture's newly created cache.
5. Repetition after removal returns empty and leaves the cache absent.

The independent dependency journal requires exactly five complete installed
snapshot reads and one real tarball GET. The helper supplies data only; it emits
no app-server frames. Native request/reply bytes, Wire decoding, Session return,
exact typed IDs `-1`, `"-1"`, `1`, `"1"`, `"owned-reconcile-empty-λ🙂"` and full
results must agree. All outgoing frames and thirteen correlated exchanges are
accounted for across both native processes.

Only physical ClientRequest owners **1473–1477**, root75 and its id/method/
method-literal/params leaves, move missing→implemented. The exact root is checked
against an independent literal and selected with only RequestId and
PluginReconcileParams definitions. Its canonical subtree matches the official
archive. Whole-schema equality, equal aliases and unobserved optional/default
values receive no credit. The already implemented request/response entries gain
supplemental ordinary evidence without a state change. The harmless reason
string is tracing metadata; forwarding it does not prove extra semantics.

## Production path and fixture boundaries

The pinned
[handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins/reconcile.rs#L21)
reloads config and invokes the actual plugin manager. The
[installed-state synchronizer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/remote/remote_installed_plugin_sync.rs#L233)
reuses an active matching version, downloads a missing one and removes stale
owned cache after a later snapshot. These are actual native effects, with no
client-side simulated install. Six decisive complete source files match the
immutable official archive in the source investigation.

The release requires an HTTPS bundle URL. Disposable local certificates and
fixed synthetic runtime identity are inert dependency setup; no header,
credential, TLS outcome, permission, authorization or approval assertion runs.
There is no insecure client setting or binary modification. The helper imports
only the previously reviewed ordinary configuration setup and replaces every
HTTP handler; it never invokes an older mixed profile or its self-tests.

Each native process starts with plugins disabled, initializes, then observes an
explicit atomic change to its owned TOML before the first request. The usual
ordinary CLI helper persistently forces plugins=false, so this case spells the
same fixed YOLO `approval_policy="never"` / `sandbox_mode="danger-full-access"`
setup directly and leaves this feature under TOML control. This avoids startup
background sync consuming the initial change. Enabled-at-startup readiness is
unqualified; no production behavior or shared helper is changed.

The bundle contains only a manifest, marker and skill document. Declaration
flags do not prove permission or executable plugin behavior. Config/input
snapshots, empty workspace/model journal, no loaded threads or interactions,
original warm capture prefix and explicit owner/Port/PID shutdown remain
required. Capture is bounded to256 frames/2MiB, each8KiB outgoing/128KiB
incoming. HTTP requests are bounded to32, snapshots8, downloads2, journal128
entries/128KiB and sockets5seconds. The case remains60seconds, RPCs5seconds,
fixture startup5seconds and each OpenSSL setup subprocess4seconds.

## Focused evidence and review

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-plugin-reconcile-focused-20261028.py
```

The exact new file passes **1/0 at seeds501432 and987654**, on its first run
at each seed. Formatting passes. Independent review of the complete formatted
test/helper finds no concrete source or scope defect. No deadline, assertion
or existing test is removed; no security/permission test or audit runs.

| Artifact | SHA256 |
| --- | --- |
| Source reachability note | `de19cea3c26961ebc2e1c77da1b72a06305ab17972a063178be5c52ba47a5237` |
| Independent source review | `fc43b68888d1784881a4595ed5865d42b5e20873cedb83fd72f9eb5a218c5745` |
| Formatted test | `5b4aa13c1e55d17d0f0e8646d5c5fb74b27a6f53aa9680d2ebee398410bed7cf` |
| Helper | `45ddc9bf6a80c2f0de23569a444e35d3420d6801df44ed20329d1ddbade5fa05` |
| Focused seed501432 log | `170f4bdf61a02d840f1dd7065978c597ae98ab183596d629375cbf1240a83840` |
| Focused seed987654 log | `5e9a2c082b32c6d22a9236aae5977a61f2e1b66a3d0eaa1e7f4900924c108a7e` |

Final combined-source qualification, including the
[app/fork slice](ordinary-apps-fork-projections-qualification.md), follows below.
Focused evidence alone does not establish that combined result. Counts regenerate
to **5,603 implemented / 882
missing / 136 blocked** contracts; requirements **462 implemented / 12 missing /
11 blocked**, both zero globally verified.

## Final combined-source functional qualification

All **14 reviewed steps** pass on the frozen integrated source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-apps-fork-reconcile-final-20261028
python3 -B /tmp/samgita-apps-fork-reconcile-final-binding-20261028.py
```

The selection contains **80 files / 144 real-native cases**, passing at seeds
501432 and987654. The same three WebSocket overflow/replay cases pass at455834,
501432 and987654, with the other thirteen mixed-file cases explicitly excluded.
The outside-umbrella consumer passes **1/0**, seed724069, using the pinned real
binary. Driver/root warnings-as-errors compile, formatting, strict Credo across
611 sources, Dialyzer and assets all pass. No broad suite, audit, hosted workflow
or security/permission-related test runs.

All **1,707** guarded sources match before/after and final binding. Two new
test/helper files are added. Only the app/fork assertions, manifest and reviewed
selector change among prior sources; all **1,701** other prior hashes remain
exact. Every previous command is unchanged after removing the one new test
argument. The final integration source review confirms exactly nine physical
missing→implemented owners and two supplemental entries, with no other state
transition, removed assertion or bound change. Final binding independently
checks original log hashes, exact source identity and those manifest changes.

| Final artifact | SHA256 |
| --- | --- |
| Evidence directory `results.json` | `31e3eb01108e1d7bdd52958931bb259643362ee8e2fae5c713ce39e01295e75d` |
| Evidence directory `source.json` | `9bbe42fe8a5633c7c7f9376e07fc90eaddd4818df6e9befc05ad4cd50dd81813` |
| `/tmp/samgita-apps-fork-reconcile-final-binding-20261028.json` | `ee78892a7991b90f4e0aed4a1fbd1e81e720f2622077bd8c3597de991cdad9f3` |
| Reviewed manifest/runner raw diff | `40ecbdee7a3e4c1e711e319c99b21e5624ab733b248ecd4b552d37929e1a2820` |
| Reviewed source fingerprint | `db1d22a3cbbb863e1c3d4495efaa3cf665f23517d0b87fe36cb1fdfaa9263713` |

The complete goal remains active. Next: implement an independently reviewed
ordinary `plugin/share/save` profile for actual native tar upload, file-ID/ETag
correlation and owned local path mapping. Source investigation is
`/tmp/samgita-plugin-share-save-ordinary-reachability.md`, SHA256
`ec8abee516aba67ecd4445f7db7a37f16421d77479796a4c0a1588d369227b29`.
Its five root78 owners1488–1492 remain missing; no save runtime or new contract
credit is claimed. Omit access inputs and leave discoverability-null, targets,
publish/access/default-policy assertions and whole-policy response validation
outside the permitted selection. Real external success remains unverified.

Rollback removes this test/helper and selector argument, restores the five
physical rows and two supplemental entry annotations, then restores the reviewed
fingerprint. No platform database, real installed history or external repository
changes occur. Other plugin scopes/features, executable effects, real services,
OS/transports, prohibited/broad/hosted gates, A11, full compatibility and release
remain incomplete. No package publication or deployment is claimed.
