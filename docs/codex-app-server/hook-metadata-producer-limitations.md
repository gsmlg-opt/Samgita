# Pinned hooks/list cannot emit prompt or agent metadata

V445 records a source-only upstream boundary at `main`
`32035d3e793d599e6040e334dfefccb78440af7d`. In unmodified Codex
`rust-v0.163.0`, `hooks/list` cannot produce metadata with `handlerType: prompt`
or `handlerType: agent`. The public protocol retains both variants and the UI
can render them, but the native response's internal input type and exhaustive
converter can express only Command and McpTool. A mock response, unsupported
warning, configuration declaration or empty list is not native positive evidence.

Target source commit is `83086188ae0614bd882818ff1aa23f3194962012`.
The official cached source archive SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
This review does not change the pin or execute an alternate producer.

## Complete audited production path

1. `protocol/common.rs:904–908` declares the typed `hooks/list` request and
   HooksListResponse. `message_processor.rs:1552–1554` dispatches it to the
   catalog processor; `catalog_processor.rs:150–157` returns its typed result.
2. The sole production HooksListResponse constructor,
   [catalog_processor.rs:614–678](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L614),
   either returns an empty hooks vector after config failure or calls
   `codex_hooks::list_hooks`, then `hooks_to_info` for every metadata record.
3. The sole production metadata builder,
   [hooks_to_info:72–110](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/catalog_processor.rs#L72),
   exhaustively converts only Command and McpTool. Its input
   [HookListEntryHandler:195–220](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/engine/mod.rs#L195)
   is a closed two-variant enum. There is no wildcard, JSON tag injection,
   alternate trait conversion or Prompt/Agent internal representation.
4. `registry.rs:304–319` implements the only list entry point: disabled listing
   returns an empty default; enabled listing calls `discover_handlers`. It does
   not select a legacy/executor execution engine or injected execution callback.
5. `discovery.rs:94–295,452–476` routes requirement configuration, every selected
   JSON/TOML config layer and plugin hook sources through the same matcher
   normalization. Its [Prompt/Agent branches:637–656](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/hooks/src/engine/discovery.rs#L637)
   unconditionally continue with `not supported yet` before the sole internal
   list-entry push at 697–716. The intermediate normalized kind also has only
   Command/McpTool.
6. `protocol/v2/plugin.rs:559–605` serializes the actual flattened typed variant.
   The common typed payload conversion and outgoing response serialization do
   not replace it. Therefore they cannot synthesize the unavailable variants.

The bounded audit text-searched all **5,259 Rust files**, including hidden and
ignored source paths, for complete response/metadata/internal-type identifiers,
constructors, conversion/list entry points and raw handler tags. Relevant
definitions and bodies were read. The closed-type proof above supplies the
positive boundary; a negative text search alone would be insufficient. It does
not claim every line of every source file was manually reviewed.

All 5,259 local Rust files match the archive byte-for-byte, with matching path
sets. Nineteen relevant whole source/manifest hashes also match. The audit
examines this pinned Rust native path, including platform-independent list
dispatch, rather than patched binaries, other versions or third-party servers.

Other examined references do not provide an alternate route:

- `config_processor.rs:701–791` constructs ConfiguredHookHandler for the config
  requirements response, a separate model and call path.
- `declarations.rs:11–31` produces PluginHookDeclaration keys/event names, with
  no metadata handler type.
- TUI RPC/startup/browser code consumes metadata or supplies empty fallbacks.
  Prompt/Agent rendering arms and constructors inside cfg(test) are consumers
  and fixtures, not app-server producers.
- Effective-plugin-change code consumes the same closed internal list result.
  Cargo resolves the native server to this one workspace hooks crate; no
  alternate target-specific list representation is selected.

## Exact blocked contracts and durable provenance

Only the following six canonical owners change from missing to **blocked**.
Prefix: `schema:v2/HooksListResponse.json#/definitions/HookMetadata/`.

| Index | Suffix | Node SHA256 |
| --- | --- | --- |
| 4160 | `oneOf/2` | `91e14528b95a3d0f0ed85d518e2808d35eb5951e0c459e9b5684774189face32` |
| 4161 | `oneOf/2/properties/handlerType` | `f8d424b88cd311fef8f8a702736876f537af43bdc7bbe60ab106ce2b9025c190` |
| 4162 | `oneOf/2/properties/handlerType/enum/0` | `60b5693ef09527a4bcf56d65322b1fa843bbda2534ddbf928150ee3267d52e97` |
| 4163 | `oneOf/3` | `54fa5af1b7a67226acac4dea5d355e561fad54158502c9bea057229fabd4bf46` |
| 4164 | `oneOf/3/properties/handlerType` | `a28d1636a0b280883d7acc3c5dcbbab62fdaaf7237708f3d75ce0d7a46cb44da` |
| 4165 | `oneOf/3/properties/handlerType/enum/0` | `6cf85bf41d9570deed965109eed6c05c9512f6d79e321c70f3f3d900c8d06c74` |

The unchanged canonical export matches its generated pinned export, SHA256
`891dd10ef7f78e59631fce05fff2becddb8004b3c0338dbbbd6b4f17ef1fa64f`.
Relevant whole-file hashes, relative to the pin's `codex-rs/`:

| Source | SHA256 |
| --- | --- |
| `app-server-protocol/src/protocol/common.rs` | `ee03e7b76763ac658f4af3d36c0c1a26c00dff6ee9256d474dd85fa740143cc3` |
| `app-server-protocol/src/protocol/v2/plugin.rs` | `9e4686a275660635aa8328e54162bdced484ffb3ec059e372f6e272bc7430436` |
| `app-server/src/message_processor.rs` | `96d57b0cb554802211460637993c2e57e27440b1052ca5f12ac79e1bbaf54449` |
| `app-server/src/request_processors/catalog_processor.rs` | `c6da0f910aeb88616a9aeaf6568bffe50f5cf8ed506eca4a23aa377bd7baa336` |
| `app-server/src/outgoing_message.rs` | `784e9f538eea4def26e33532206541bcecce0f94bea2c8fd2b7cb30463602617` |
| `hooks/src/lib.rs` | `df594069f8ed09e14bece62ec5f1404c8fa9df88c9131d513d382b895a52a5f4` |
| `hooks/src/registry.rs` | `58234cd87d1172e5adcd13db77bbd9ff12ae183967184ca7e826fa8f44a2713b` |
| `hooks/src/engine/mod.rs` | `250fc2ba39822e2b83d270b302de3fabfd6ef3d6ec386e10bab2143ee2fbf7ba` |
| `hooks/src/engine/discovery.rs` | `763704f5ae5f227d186dae8f5339edd6fde4f4a54c88c8ffb5ef9ad1b5a368eb` |
| `config/src/hook_config.rs` | `b7ac42b2a895a00b6aa491eee1d3eb04d8a147ba0e77e016bde42381e067d1c0` |
| `hooks/src/declarations.rs` | `9eb3068f41ed965258195220074530d44934681da7d69b821b84e87ab76e3af1` |
| `app-server/src/request_processors/config_processor.rs` | `a1f1037ce2e0b3875d22454bb867c58f3936a92020a33f45164012397f2c2b6a` |
| `tui/src/hooks_rpc.rs` | `77dc41d222747937507ee86b97df04784a3db1624a4872ed2a43677fcfd69ca6` |
| `tui/src/startup_hooks_review.rs` | `15a7b1ccbd2f045052a6933bb39680168f3e7c78ae2b2baba16112b828ade819` |
| `tui/src/bottom_pane/hooks_browser_view.rs` | `d393de6970dce7cd9c9241b4072c31f730923b1f3219bb0a84ca559f4236a48f` |
| `app-server/src/effective_plugin_change.rs` | `77d51bb86625cf2754378ec3e74086ada06fd9f303327f4acc5f236f2a21b131` |
| `Cargo.toml` | `b017f28f91f7506b730c247ffb3dab5250d9848514c194331fd774836d480f0b` |
| `hooks/Cargo.toml` | `13c244a381eb28ff7ce3fc2af33827edd331bbaf2b2a47859b90da27d3629fc5` |
| `app-server/Cargo.toml` | `b42b0fcb26e284d66c32411f8995512337e3a826a8aefcd2ae6bad7e5e708b0c` |

Source report `/tmp/samgita-v445-candidate.md`, SHA256
`3326807ffcba665f5b0f71d30ae271da6284f685f244cfe8c78b193610f226e0`;
binder `/tmp/samgita-v445-bind.py`; complete source/node binding
`/tmp/samgita-v445-binding/source.json`, SHA256
`924f3f2ccda6320c8dc538c06cebfdfb27f59f2094792d09470ff1e8ccf9b8e5`;
evidence JSON SHA256
`3c1ec2c928d9fc749e9339ac1e95ba25de875f243013a99861feb649f94e7843`.
Inventory consistency and final diff are checked. No new runtime or test runs;
all 415 source hashes and nine V443 check logs remain exact. Their **55/0 twice
and outside consumer 1/0** remain prior equivalent-source evidence, not new
tests of these unavailable variants.

Contract counts become **5,248 implemented / 1,301 missing / 72 blocked**;
requirements remain **462 implemented / 12 missing / 11 blocked**, zero verified.
Schema identity, planned checks and codec accessibility remain intact; these
six rows retain empty verified-tests and transport-coverage lists. An upstream
implementation plus an explicitly accepted target revision is required for
positive native acceptance. No local workaround, manufactured emitter, target
change or scope waiver occurs. Security/permission tests and audits, broad and
hosted checks remain unrun. A11, legacy/external/platform/full-goal and release
gates remain incomplete. No publication or deployment. Rollback reverts only
the six classifications and this source evidence; runtime and records do not
change. Continue independent ordinary functionality.
