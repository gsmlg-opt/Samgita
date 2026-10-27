# Native optional skill metadata

Real plugin/read now observes optional metadata removal and restoration while
retaining the same local skill. Warm and cold scans distinguish explicit null
icons from a null interface and recover the original rich metadata. Protocol
and driver runtime are unchanged.
Base: `024e6fe764cb39a03b1b8a7481aa87f20247667a`.

## Actual source reload and nulls

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Ten complete source/archive members and four exact canonical nodes match.

The real local detail loader passes no plugin-skill snapshot to
`core-plugins/src/loader.rs:1058–1097`. The production host loader at
`ext/skills/src/host_service.rs:419–444` rescans roots through host_merge.rs;
this path does not reuse the separate config/cwd skill cache. Actual current
YAML is parsed by `ext/skills/src/loader/metadata.rs:78–153` and resolved by
`skills/src/interface.rs:32–75`. Missing icon declarations become None, while
nonempty displayName preserves an interface. Holding the optional YAML aside
produces no interface. Removing icon files alone would not prove these nulls:
their ordinary path resolution is lexical.

One never-installed inert plugin has one genuine SKILL.md, two fixed PNG files
and a prescribed rich eight-field interface. Twelve actual plugin/read calls
cover six stages, twice each: warm rich/stripped/held YAML, then distinct cold
held/stripped/rich YAML. Rewriting only YAML removes both icons with explicit
null values while retaining the same interface display name. Holding it aside
preserves the sole skill's namespaced name, description, concrete path and
enabled value but changes interface to null. Restoring stripped then exact rich
bytes in the cold process recovers each independently prescribed map. Assets,
SKILL.md, manifests, config/catalog/provider/support and final source tree remain
exact. No result field is copied to construct an expectation.

The manifest declares an existing onboarding skill. Public
`plugins.rs:1119–1136` selects onboarding only for an enabled plugin. This fixed
uninstalled/disabled plugin returns onboardingSkill:null throughout. The test
does not toggle enablement or claim a positive-to-null onboarding transition.
No plugin installation, activation, skill/hook/tool/thread/model execution or
remote service is requested; the actual inference journal remains empty.

Twenty-two original requests have exact sent maps/bytes and correlated IDs:
twelve reads, eight loaded-list and two diagnostics calls. Capture remains
24 frames/4KiB; responses65KiB, source files8KiB and tree64 paths/1MiB. Existing
5s request/start and60s case limits remain. Fixed YOLO launch and the existing
metadata-after-initialize helper remain. Both shutdowns check owner completion,
closed Port and absent native PID; existing failure/model cleanup is retained.

## Qualification and unavailable local branch

Initial native **1/0**; the two ordinary plugin/read modules pass **2/0 at501432
and987654**. Driver compile/format, strict Credo548 and inventory consistency
pass with381 stable sources/all380 prior unchanged.770 exports and15 input
descriptors are exact. Prior **87 schema /148 ordinary driver twice**, isolated
consumer and root/static/assembly evidence retains source equivalence without
fresh-run claims. No mixed/broad, prohibited or hosted checks ran.

Exact commands/logs/guard: `/tmp/samgita-v379-run.py` and
`/tmp/samgita-v379-functional-checks/final/`. Source/final review:
`/tmp/samgita-v379-ordinary-gap.md`, `/tmp/samgita-v379-final-review.md`.
The final binding records their hashes and exact physical null owners4676,
4717,4721,4728. Only those become scoped implemented; their already implemented
parents and plugin/read request/response receive supplemental evidence.

Null skill path4732 remains missing. `plugins.rs:70–96` always assigns Some path
to a local skill; deleting SKILL.md removes the skill rather than preserving a
null-path row. Its separate remote detail producer at2326–2336 supplies None.
Local tests, empty arrays or equal-shaped aliases cannot qualify that remote
branch. No fake response or scope waiver is used.

Contracts: **5,060 implemented /1,495 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
still fails. All remote/other-transport/OS profiles, legacy emitters, prohibited
verification, A11 and full-goal acceptance remain incomplete. Nothing was
published or deployed.

Rollback removes this isolated test and exact supplemental evidence only;
preserve prior runtime, fixtures, qualification and historical records. Continue
the source-backed ordinary direct-MCP request recipe and remaining reachable
functional groups.
