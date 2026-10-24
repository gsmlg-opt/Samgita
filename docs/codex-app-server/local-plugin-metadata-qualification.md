# Native installed local marketplace and plugin metadata

Two additive cases in `native_plugin_lifecycle_profile.exs` exercise actual
stock `plugin/installed` warm and after owned cold restart. Source is
`83086188ae0614bd882818ff1aa23f3194962012`, release `rust-v0.163.0`, Linux musl
binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The fixture enables local plugins with remote plugin/sharing disabled and uses
only owned source files, no credentials, threads or model calls. Existing
process-owner shutdown/reaping and all earlier lifecycle assertions remain.

The first case adds a prescribed Unicode marketplace displayName, verifies the
complete empty uninstalled response, installs the ordinary local fixture and
compares the entire installed response to an independent expected map. That
map includes exact marketplace name/path/interface and complete plugin summary,
including every expected null. It repeats the same oracle after a distinct
native PID starts, with immutable marketplace bytes and no loaded threads.

The second case supplies a complete rich local plugin interface. It independently
specifies all 19 output fields, including normalized defaultPrompt whitespace,
Unicode descriptions, category, informational capabilities, invalid-domain URLs,
brand color, absolute owned asset paths, null URL/dark alternatives and empty
screenshotUrls. The three assets are prescribed PNG bytes; all remain regular
files with exact source bytes before install, warm reads and cold restart. Both
complete installed response and plugin/read summary match the independent maps.
The response is never copied to construct its own expected metadata.

This is metadata projection. Informational capabilities do not grant execution
authority; no plugin tool, remote URL, image decoder/rendering, authentication,
policy enforcement or model reasoning is exercised.

## Exact physical owner scope

All 21 owners belong only to `schema:v2/PluginInstalledResponse.json#`.
They become scoped implemented, never fully verified. The corresponding
vendored experimental JSON nodes were independently traversed and hashed using
the inventory's canonical encoding; equal sibling hashes transfer no evidence.

| Definition prefix | Exact suffixes |
| --- | --- |
| `/definitions/MarketplaceInterface/properties/` | `displayName` |
| `/definitions/PluginMarketplaceEntry/properties/` | `interface`, `interface/anyOf/0`, `name`, `path`, `path/allOf/0` |
| `/definitions/PluginInterface/properties/` | `brandColor`, `capabilities`, `category`, `composerIcon`, `composerIcon/anyOf/0`, `defaultPrompt`, `developerName`, `logo`, `logo/anyOf/0`, `longDescription`, `privacyPolicyUrl`, `screenshots`, `shortDescription`, `termsOfServiceUrl`, `websiteUrl` |

Whole interfaces/summaries, Git/remote alternatives, URL-backed assets,
omission/default branches, sibling read/list aliases, nonlocal backends and
other OS profiles gain no qualification from this index.

## Executed evidence

The complete owning plugin profile is **10/0** within each **14/0** combined
scoped run at seeds501432 and987654. Command:
`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-sleep-queue-plugin-v2-20261024.py`. Compile, format, root
strict Credo and executable-source guard pass. The combined `results.json`
SHA256 is
`afbde503a2f8efdb71d2a668ad3c34ecfeeea21068f01c89cb026bd85c5bc4fc`;
source snapshot SHA256 is
`3753eeb92184af2fabf7392b8e251586ff2e265e2eafc5b28d87f48f4cc42149`.
Both logs and complete source snapshots remain in its `/tmp` result directory.
No native failure occurred in these two new cases. Existing CI already runs
the complete owning profile explicitly; final-source hosted/aggregate checks
remain required. A11, missing emitters and full compatibility remain incomplete.
No publication, release, production migration or deployment follows.

## Owned local Git source and immutable cache

One later additive case uses stock plugin/install with an absolute owned local
Git repository and subdirectory. The source has main/HEAD at commit B, whose
parent is requested SHA A, with independently prescribed distinct skill bytes.
The native cache must contain exact A bytes while source main/HEAD/files stay B.
The complete installed response and plugin/read summary must equal independently
prescribed maps with exact Git url/path/refName/sha. Both maps and cached bytes
are rechecked after confirmed native PID replacement. No skill executes and no
thread or model request starts.

The fixture discards inherited Git environment, uses isolated HOME, disables
system/global Git config and initializes with an owned empty template/hooks
directory. Source remotes/submodules/credentials are absent; Git config remains
byte-identical. No `protocol.file.allow` override, permission change or remote
access is introduced. The explicit top-level local clone uses Git's normal file
policy. SHA wins over ref during materialization; refName remains provenance,
so this proves no ref-only selection or remote-Git success.

`devenv shell --no-tui -- python3 -B
/tmp/samgita-native-git-plugin-v1-20261024.py` passes compile, format, root strict
Credo and the complete **11/0** owning profile at both seeds501432/987654, with
a matching executable-source guard. No runtime failure occurred in this case.
`results.json` SHA256:
`b06e2290ec3a8a63a888566595b7287802fd34b0a68b2b124088608048344678`;
source snapshot SHA256:
`b1d4759eafb78672db3b80b336281f7e5e4d69bc56177215618f2a64e3beba8d`.
The existing required hosted step runs this full profile.

Exactly seven still-missing physical owners under
`schema:v2/PluginInstalledResponse.json#/definitions/PluginSource/oneOf/1`
gain scoped implemented evidence: selected complete Git alternative, properties
path/refName/sha/type/url and type's git literal. Each subtree hash is
independently recomputed. Null/omission, remote auth/protocol, other platform,
plugin execution, policy and full qualification stay incomplete. Earlier local
source/rich-interface evidence above retains its original scope and counts.
