# Owned native fixture startup

Target: Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, Linux musl executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
This extends the [metadata fixture repair](thread-metadata-qualification.md#background-plugin-fixture-repair).
It changes test launchers, not production driver defaults or Agent policy.

## Startup contract

Ordinary owned native test launches supply supported root CLI overrides
`features.plugins=false` and `features.recommended_plugins=false`. They preserve
fixture TOML and its existing feature-table appenders. The shared stdio starter,
owned transport listeners and inventoried direct stock-Codex launchers use the
same helper. Python/unshare wrapper arguments are not Codex CLI arguments and
are not rewritten.

Three local-plugin consumers explicitly opt into a different initialization
path: disable plugins in their exact owned config fragment, complete native
initialization, then atomically restore the original bytes before plugin calls.
Missing/duplicate fragments fail before process creation; initialization failure
also restores the file. Existing plugin install, selection, skill reload,
feature-toggle, model-content and cold-restart assertions remain. The dedicated
local/remote/share namespace profiles retain their own startup contracts.
Process guardians, borrowed-resource ownership and deadlines are unchanged.

The pinned startup calls `start_startup_warmups` in
`app-server/src/message_processor.rs:544-560`. The `plugins_enabled` gate in
`core-plugins/src/manager.rs:2824-2948` encloses curated synchronization and
related warmups. `core/src/config/mod.rs:1767-1779` derives that gate from the
effective feature. Curated paths and temporary clones come from
`core-plugins/src/startup_sync.rs:35-37,389`.

## Executed checks

`native_launch_isolation_test.exs` verifies the selected executable and cached
source-archive hashes. `CODEX_SOURCE_ARCHIVE` can select an external copy of the
same archive; its expected SHA256 is
`e57f1d4f914c71c3532a12d5c14f740909fca4e7e041fa1b3db71618c88e5567`.
Missing prerequisites fail explicitly. A positive precedence control enables
both plugin features in TOML, then requires the actual server's feature/config
responses to report both disabled, with an unrelated feature unchanged.
Initialization and confirmed close barriers check unchanged config bytes and
absence of source-defined curated checkout, lock, SHA and clone paths. The same
checks repeat with a new owned process; no model request is made.

The helper's three tests cover exact restoration, failed initialization and
rejected fragments. They do not merely compare an argument list to itself.
The combined startup suite, including all three real local-plugin consumers,
three-transport initialization, metadata, config, compaction, Projects, goals,
account, instructions and direct MCP, passed **95/0** at seeds `501432` and
`987654` (102.4/102.3s). Five explicit local/remote/share/revert/realtime profiles
passed **35/0**, seed `501432`, 82.4s. Commands, exits and full logs:
`/tmp/samgita-native-startup-adoption-v1-20261024/`. Initial scoped compile,
format and pure-helper results are retained in
`/tmp/samgita-native-followup-adoption-v1-20261024/`; that runner then correctly
failed its separate new thread-expectation tests. It is not an aggregate pass.

## Limits

These source gates, effective-setting checks and lifecycle snapshots establish
bounded startup behavior. They do not prove universal absence of attempted
network traffic. Trusted system Git bypasses a fixture PATH replacement
(`startup_sync.rs:81-84`), and HTTP fallback also exists. Local plugin activation
can enable later account-triggered synchronization; temporal initialization is
not a permanent network fence. The dedicated namespace profiles are separate
evidence. No general egress-isolation, complete compatibility or A11 claim is
made. All changed launchers still need the final combined-source and hosted
matrix; no schema status is promoted by this fixture change alone.
