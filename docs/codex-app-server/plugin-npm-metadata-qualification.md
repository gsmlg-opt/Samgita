# Native npm source metadata

Real Codex reads and normalizes an uninstalled suggested npm source from an
owned local marketplace, without resolving or installing a package. Source
rewrites remove optional values as explicit nulls; exact byte restoration and
a distinct cold process reproduce the original descriptor. Protocol and driver
runtime are unchanged. Base: `1f3ba86aafe8fed5a229be0a9b515e71a526517e`.

## Actual producer and observable effects

The immutable target remains `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`
and archive SHA256
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Eight complete source/archive members and all six canonical schema nodes match.

`core-plugins/src/marketplace.rs:540–585,661–670,815–925` reads current source
bytes and normalizes npm package/version/registry. `manager.rs:2420–2504` retains
an uninstalled descriptor without materializing it. The public source mapper
in `app-server/src/request_processors/plugins.rs:121–147` preserves all fields;
the installed endpoint's explicit-suggestion filter retains the uninstalled row.
This is a populated production enum branch, with real file discovery and native
normalization rather than a scripted response or an npm installation substitute.

One owned manifest prescribes a scoped package, version range and inert HTTPS
registry string with surrounding spaces. Two real plugin/installed calls must
return the independently literal complete trimmed source map. Replacing only
the source with a different valid unscoped package and omitting version/registry
must return the exact new package plus explicit null options, preserving known
marketplace/plugin identity and uninstalled/disabled status. Two reads per stage,
exact original-byte restoration and two distinct-cold-process reads establish
current-file behavior. Marketplace errors must remain empty throughout.

The registry string is metadata only. No npm command, package directory,
download, installation, activation, remote service, thread, tool or model turn
is requested. Actual inference journal and workspace remain empty. Existing
after-initialize metadata setup and fixed YOLO launches remain unchanged.
Sixteen selected outgoing requests preserve original maps/bytes and correlated
IDs: eight inventory, six loaded-list and two diagnostics calls. Capture stays
24 frames/4KiB; responses65KiB, source files8KiB and tree32 paths/1MiB. Requests
remain5s and the case60s. Config/catalog/provider/support and restored complete
source tree are exact. Both native shutdowns check owner completion, closed
Port and absent owned PID; existing failure/model cleanup remains in force.

## Qualification and evidence limits

Initial actual-native **1/0**. The reviewed functional matrix passes **87 protocol
and148 ordinary driver tests at501432 and987654**, plus the outside-umbrella
consumer **1/0**. Protocol/driver compile/format, strict Credo547, fixture Python
syntax and inventory consistency pass. All380 guarded sources remain stable;
all379 prior sources,770 official exports and15 input descriptors remain exact.
The matrix explicitly lists ordinary-only modules, preserves every assertion
and runs no mixed/broad suite, prohibited test/audit or hosted workflow. Earlier
root/static/production assembly evidence retains source equivalence without a
fresh execution claim.

Commands/logs/source guard: `/tmp/samgita-v378-run.py` and
`/tmp/samgita-v378-functional-checks/final/`. Source/final review:
`/tmp/samgita-v378-ordinary-gap.md`, `/tmp/samgita-v378-final-review.md`.
The final binding includes their hashes, exact source/log hashes and physical
owners4602–4607: the PluginInstalledResponse Npm source branch, package, registry,
type/type enum and version. Only those become scoped implemented; source
parent4637 and suggestion4524 receive supplemental evidence. The equal-shaped
PluginSearchResponse fields gain no state from this endpoint's observations.

The same pinned source audit retains a concrete non-emission boundary:
`hooks/src/engine/discovery.rs:637–657` warns and continues for prompt/agent
handlers before registry metadata is created. `catalog_processor.rs:72–108`
maps only actual command/MCP registry handlers. V375's declaration summaries
are a separate producer and cannot qualify those missing HooksList variants.
No fake emitter or scope waiver is introduced.

Contracts: **5,056 implemented /1,499 missing /66 blocked**. Requirements remain
**462 implemented /12 missing /11 blocked**, zero verified. Strict completeness
continues to fail. npm materialization, remote registry/backend success,
other transports/OS, unreachable legacy emitters, prohibited verification, A11
and external/platform/full-goal acceptance remain incomplete. Nothing was
published or deployed.

Rollback removes this isolated test and its exact evidence only; retain prior
runtime, fixtures, qualification and historical records. Continue ordinary
reachable field/effect groups, including the source-backed optional skill
metadata recipe; do not infer completion from this matrix.
