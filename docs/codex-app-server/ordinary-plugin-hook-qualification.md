# Native installed-plugin Hook source

V502 follows `ca7c3bb` on `main`, against official `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012` and executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The driver, neutral core and upstream implementation remain unchanged.

`native_plugin_hook_test.exs` uses native `plugin/install` to install one owned
local plugin. Only its inert synchronous PostToolUse observer comes from the
plugin; the existing finite real printf command and ordinary user PreToolUse
observer remain. The marketplace/source lives in an owned catalog directory,
separate from the empty execution workspace. Original and native-cached plugin
manifest/hooks bytes must remain equal and frozen throughout both turns.

Both original native post-hook envelopes require `source: "plugin"`, the exact
installed cached `hooks/hooks.json` path, independently prescribed run ID with
native tool-use suffix, display order, event, sync mode, status, empty entries
and timing. The user pre-hook keeps its distinct source/path. The real hook
stdin and command process independently bind the thread/turn/use IDs, output
and actual Unicode file/stdout effects. Full native command/turn/Hook maps,
three finite provider requests, final summary, independent watcher causal
chains and confirmed owner/Port/hook/command/native PID cleanup remain required.
Only stock Codex produces app-server messages; no fixture manufactures them.

The pinned production path is local installation
`app-server/src/request_processors/plugins.rs:1481–1528` and
`core-plugins/src/manager.rs:2076–2130`, followed by loader1204–1310 and
`plugin/load_outcome.rs:185–194`. Session configuration consumes active plugin
Hook sources. `hooks/src/engine/discovery.rs:247–299,666–739` assigns Plugin
source and constructs executable handlers; dispatcher78–100,233–254 preserves
it in running/completed summaries. The Sync public gate and app-server
`bespoke_event_handling.rs:1147–1168` emit the actual native notifications.
Seventeen complete producer files are archive-equal in
`/tmp/samgita-v502-source-evidence.json`, SHA256
`b9df0146495bbc8f1b27e387b7cc7a1a60e6f03ecbe4fa5005fe7f096d639e20`.

Independent source review found a duplicate temporary startup TOML key before
any native run: the shared local-plugin initializer inserts
`recommended_plugins=false`, which the draft also declared. Integration removes
only the redundant fixture declaration; the initializer and explicit CLI false
override remain. Fixture SHA256 is
`c53c41c18947e0170e58a7ef0dda2d63f1398960b5bc4c70203a0b11f5a8f567`.
No runtime failure, policy change or bypass is claimed for that source correction.

The ordinary fixed positive setup is the already reviewed native current-hash
configuration. No trust/admission state, credential, authentication, permission
or approval behavior is asserted or varied. All original caps/deadlines stay:
60s case,20s journey,5s observation/request,1s Hook,128 events/frames,64KiB
inbound and2MiB aggregate. Source/cache comparisons are bounded to4KiB.

The combined focused command with
`native_config_warning_envelope_test.exs` passes **3/0** at seeds501432/987654,
5.1/4.7s, in the verified Devenv test environment. Root strict Credo passes
across593 files. Logs: `/tmp/samgita-v502-v503-focus-501432.log` and
`/tmp/samgita-v502-v503-focus-987654-credo.log`. Final combined-source checks
pass in the [final combined-source selection](ordinary-mcp-control-ids-qualification.md#final-combined-source-qualification-for-v502v505).

Only physical owner2262,
`ServerNotification.json#/definitions/HookSource/enum/5`, value `plugin`, is
mapped to scoped implemented evidence; canonical SHA256
`4f63c83e2bb43c041b0ce8ee2f0c8fe5b78660903c654548e64eb70382882080`.
No catalog/history alias, project/managed source, remote plugin, async/executor
path or full plugin compatibility inherits evidence. Project source2259 is
outside this case. Nothing becomes verified. Full-goal, prohibited/hosted,
A11 and external/OS gates remain incomplete. Rollback removes test/fixture/
evidence additions without changing persisted platform data. No publication,
deployment, external repository or live credential change occurs.
