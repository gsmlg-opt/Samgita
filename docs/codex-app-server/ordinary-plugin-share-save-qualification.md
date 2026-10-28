# Ordinary native plugin share/save

This profile uses real Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux-musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only the upload-metadata, object-upload and finalize dependencies are fixtures.
The app-server, tar packer and local mapping writer are native. No real account,
external upload, published plugin, model, command, MCP or hook execution occurs.

## Behavior and source ownership

One native process saves an owned plugin directory containing a literal manifest,
marker and genuine `skills/notes/SKILL.md` text. The dependency independently
inspects its uploaded tar.gz bytes. Filename, declared/actual byte size, exact
three file contents, upload file ID and JSON ETag must match the finalization
request. Only the returned ordinary remote plugin ID and share URL are selected
semantically; other response fields stay opaque correspondence data.

After confirmed native process/Port/owner shutdown, the test explicitly edits
only the skill text. A distinct cold native process preserves the local path
mapping and original source files without uploading. Its explicit second save
supplies the original returned ID, uploads the edited literal bytes, uses the
ID-specific finalize URL and new file ID/ETag, and retains the mapping. This is
an explicit update, with no implicit replay. The same dependency helper remains
alive across native restart; helper restart/recovery is unqualified.

The pinned [handler](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/plugins.rs#L1267)
reloads the owned config. The [save path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/remote/share.rs#L143)
calls the real [directory packer](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/plugin_bundle_archive.rs#L54),
uploads the native bytes and finalizes with the ETag from upload-url JSON.
Recording the [local path](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core-plugins/src/remote/share/local_paths.rs)
is best-effort upstream. This success case proves neither transactional mapping
recovery nor an implicit ID lookup from that file.

Complete original requests/replies, Wire decoding and Session returns agree.
Integer `-1` and string `"-1"` remain distinct. Ten correlated exchanges and the
entire outgoing inventory are accounted for across both native processes.
Only missing physical ClientRequest owners **1488–1492**, root78 and its
id/method/literal/params leaves, gain implemented evidence. The request/response
requirements already implemented gain supplemental evidence without a state
change. No alias, entire params/result schema or unobserved value gains credit.

Five complete producer/type files match the immutable official source archive,
whose SHA256 is `e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
The archive's save root is43; generated experimental root78 is selected by its
method and compared by exact subtree, rather than assuming equal array indices.
All five physical node hashes match the manifest. Source-binding artifact:
`/tmp/samgita-plugin-share-save-source-binding-20261028.json`, SHA256
`5be4f4eb0542b51a67b5ce25af741414db859e016527880722fd1b6e8c59c233`.

## Functional verification boundary

Owned launches use fixed YOLO `approval_policy="never"` and
`sandbox_mode="danger-full-access"`. Each process initializes with plugins and
sharing disabled in its owned TOML, then observes the explicit atomic feature
change before saving. No enabled-at-startup behavior is claimed. Omitted policy
inputs scope the ordinary content call; their defaults are not qualified.
Discoverability, share targets, access/publish policy and policy response fields
remain outside verification, including the missing discoverability-null owner.
No security, credential, authentication, authorization, approval or TLS test runs.

Capture is bounded to128 frames/1MiB, outgoing8KiB/incoming128KiB. HTTP input,
archive and journal are bounded to128KiB; extracted files16KiB, archive members16,
HTTP requests32 and journal events128. Case/RPC/socket deadlines stay60/5/5
seconds. Exact content-event order, frozen input hashes, unchanged source bytes,
empty workspace/model journal, no loaded threads/interactions and original warm
capture prefix are required. Explicit native/helper owner completion, closed
Ports and absent owned PIDs preserve the earlier process-cleanup repair.

## Focused evidence

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-ordinary-plugin-share-save-focused-20261028.py
```

The new exact case passes **1/0 at seeds501432 and987654**, on its first run at
each seed. Formatting and strict Credo pass; independent review finds no source
or scope defect in the formatted test/helper. No assertion, deadline or existing
test is removed. No runtime repair was needed.

| Artifact | SHA256 |
| --- | --- |
| Formatted test | `07326720dfd0813c5ce23db9f7d40611259f6959e34b33e2cf029af18ad33d4d` |
| Upload dependency | `939317eee012ed7d1ef3c84e42c088e2322236cf52454d35b280a4cbfe289376` |
| Independent review | `fe17f2047d12bbe3f9136de0fe290076211b078b75b3b3a62e318108ee669bc8` |
| Focused seed501432 log | `9fc974a5a05b536ee61cd93e6c00d7a6e868f1b55653a8d769aa61f21b4b8dd1` |
| Focused seed987654 log | `8bb160467a2929dbefcada2cf7f830c505a6c978efa00d5fc2abd5255b2a1610` |

Manifest totals are **5,608 implemented / 877 missing / 136 blocked** contracts
and **462 implemented / 12 missing / 11 blocked** requirements, zero globally
verified. Final combined-source functional checks are recorded below.
Full compatibility, prohibited/broad/hosted gates, A11 and unavailable native
emitters/external/OS success remain incomplete. No package is published, tagged,
released or deployed.

Rollback removes this test/helper and selector argument and restores the five
physical rows, two supplemental annotations and previous reviewed fingerprint.
No platform database, historical record, real installed plugin or other
repository changes occur. Real service success, failure atomicity, concurrent
writers, ambiguous-disconnect recovery and remote idempotency are unqualified.

## Final combined-source functional qualification

All **14 reviewed functional steps** pass on the frozen integrated source:

```sh
devenv shell --no-tui -- python3 -B scripts/codex/check_ordinary.py \
  --output /tmp/samgita-ordinary-plugin-share-save-final-20261028
python3 -B /tmp/samgita-plugin-share-save-final-binding-20261028.py
```

The **81 files / 145 real-native cases** pass at seeds501432 and987654,
in251.0/250.6seconds. Three selected WebSocket overflow/replay cases pass at
455834,501432,987654; the thirteen other mixed-file cases remain excluded.
The outside-umbrella consumer passes **1/0**, seed209958, with the pinned real
binary. Driver/root warnings-as-errors compile and formatting, inventory
consistency, strict Credo across612sources, Dialyzer and assets all pass.
No prohibited test, audit, broad suite or hosted workflow runs. This selection
does not rerun database recovery or close the required full release matrix.

All **1,709** guarded sources match before/after and final binding. Only two
test/helper files are added; among prior sources only the manifest and selector
change, with **1,705** other hashes identical. Every previous command is exact
after removing the one new file argument. Independent final source review and
the binding confirm exactly five missing-to-implemented physical owners and
two unchanged-state supplemental requirements. Zero rows become globally
verified, and no assertion, deadline or process-owner behavior is weakened.

| Final artifact | SHA256 |
| --- | --- |
| Evidence directory `results.json` | `15d3066e66360f531829917dce498c2d4c4f61e0ef7c8471d715dcbb45865507` |
| Evidence directory `source.json` | `32cc669d32a99448a7c92c21eb23a1cf8bb17aaf187ed1e738738bea82e6290e` |
| Final binding JSON | `1b0f58e1a1e66873524fc3e88ef688a22bc2feb6d1d54116e159338fcc8131ac` |
| Manifest/selector raw diff | `ecd57663e402995b310ddc74e3097e5c0aa20c6556eccd1580565114cd97612b` |
| Final integration review | `05aec2903505bcbe9e018d0b7ad873b373554b194e88aa9bc77378b7c57908f4` |
| Reviewed source fingerprint | `544b7d5183dbd93160ae21e3d9b9600d5d69e38db8f85701dfe3cbce75dff8c5` |

The complete goal stays active. Next ordinary implementation is real loaded
thread/null `app/list` context, then direct `plugin/skill/read` Unicode/null
content. Their source-reviewed drafts remain outside the repository and unrun;
no extra compatibility credit follows. AppInfo whole-array policy semantics,
prohibited gates, unreachable emitters, real external/OS success, A11 and
publication/release/deployment remain incomplete.
