# Native installed-plugin hook provenance

V461 adds `native_hook_plugin_metadata_test.exs` at `main`
`8a6058cd44bdb11706424f534b08df46ac7994f1`. One isolated ordinary metadata
journey installs a genuinely local plugin, observes its populated hook provenance,
repeats in a distinct owned native process and explicitly uninstalls it. No model,
thread/turn, hook trigger, command execution, external service or Samgita runtime
is involved. Fixed YOLO is launch setup only; no security/permission behavior is
tested or configured.

Three independently authored marketplace/manifest/hook files remain byte-identical.
Before installation, the complete catalog is empty. Public `plugin/install`
must produce byte-identical cached files; two warm `hooks/list` calls require
exact ordinary key/event/handler/command/source/path/plugin metadata, including
the independently fixed `owned-hook-provenance@owned-hook-metadata` identifier.
After checked native shutdown, a different pinned PID reads the same configuration,
cache and catalog. Public uninstall removes the cache and restores the complete
empty catalog while original files remain. The cold-process helper restores
plugin-enabled config after initialization, so this proves post-initialize
catalog reload, not plugin-enabled startup or cold-after-uninstall behavior.

All 11 RPCs retain original successful-send bytes and original pre-Session replies,
unique typed IDs, exact expected sent maps/bytes and complete correlated result
envelopes. The exact method inventory excludes work-starting operations. Capture
overflow fails at 96 frames, 8 KiB outbound/64 KiB inbound and 1 MiB aggregate;
Session is bounded at 64 events/256 KiB. Five-second RPCs, 60-second case, three
4-KiB source files and 8-KiB config stay bounded. Saved original connections are
registered for fallback cleanup before initialization. Explicit close requires
owner DOWN/completion, closed Port and owned native PID disappearance.

The first focused run **1/1** correctly exposed a fixture-oracle error: PreCompact
cannot emit additional context, so its input `additionalContextLimit: 73` yields
an exact warning and null metadata. Pinned `hooks/src/engine/discovery.rs:541–560`
states this normalization. The input remains 73 in original and cached bytes;
the test now requires the full warning text/path and explicit null. No assertion
was removed, timeout increased, input dropped or access-control setting changed.
The failed preimage/result remains in `/tmp/samgita-v461-initial-failure.md`;
the authoring proposal remains historical. Independent source review found no
functional defect in the corrected final test.

Target: official Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The actual installed plugin supplies effective hook sources; discovery populates
`Some(plugin_id.as_key())` before separate executable registration, and the
catalog copies it into typed `HookMetadata.plugin_id`. Fifteen complete native
source files match the official archive. Only contract **4174**,
`schema:v2/HooksListResponse.json#/definitions/HookMetadata/properties/pluginId`,
gains scoped implemented evidence; node SHA256
`cd49941f1a90808c0c692f85bc803a6dd936c9153aaac4a725cf9030c3fc9089`
matches its canonical export/generated copy. Prior null-only evidence remains
historical; no alias, sibling field or whole method receives transferred credit.

All **13** final-source commands pass: focused **1/0**, reviewed 37-file ordinary
selection **59/0** at seeds `501432`/`987654`, dependency Python syntax, scoped
format, warning-free driver compile, root strict Credo, inventory consistency,
outside consumer **1/0** (seed `884152`), umbrella warning-free compile, root
format, forced Dialyzer and assets build. The consumer uses the real pin outside
the umbrella without Repo/Phoenix/platform configuration. All **851** guarded
sources stay exact; 850 prior sources are unchanged and only this test is added.

| Artifact | SHA256 |
| --- | --- |
| Final test | `5ed74e20be7e67f6d6070e092d8d8705ea501ceb763271a7f9e80dcf7d7ff0fe` |
| Final results | `3afded4a78c30aba1a813b9a149361e913f73db38f320ddb5243f5e31cf0c46c` |
| Source guard | `97797068968e2586d1dc44d3e03355f6a8e87317049c40cd88f1747617f89b6e` |
| Native source/node binding | `a4d99d3ae3eb442c9cf180c337e4059be95753b3d9a08a508d458e85145e7402` |
| Evidence binding | `3a7ae062d16e2fea5295bf169960e1a1c348d0623f1e1ef3f86cb6a72e797e38` |
| Source review | `253030613241992b6eb3d6a648e9d0271d991dd7bcb1243da39fb7103b11c6be` |

Runner `/tmp/samgita-v461-run.py`; results/guard/logs under
`/tmp/samgita-v461-functional-checks/initial/`; binder `/tmp/samgita-v461-bind.py`;
bindings under `/tmp/samgita-v461-binding/`; review `/tmp/samgita-v461-review.md`.
Inventory consistency and diff whitespace are rechecked after binding.

Contracts: **5,287 implemented / 1,240 missing / 94 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
This covers one local inert PreCompact plugin identifier/profile, not hook
execution, every metadata/optional/null variant, remote marketplaces, live
providers, other platforms/transports or full compatibility. Security/permission
tests/audits, broad/hosted workflows, A11, unavailable legacy producers,
external/platform and release gates remain incomplete. No publication or
deployment. Rollback removes this test and its one evidence binding only.
Continue the ordinary collaboration catalog outer-None profile proposed in
`/tmp/samgita-v462-proposed.patch`; its source-only proposal is not acceptance.
