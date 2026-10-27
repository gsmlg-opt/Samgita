# Existing local plugin-search string-ID evidence

V453 corrects one evidence omission at `main`
`b7179a06d4d5a5114abdfd26ead15041edaff586`. No code, test, fixture or runtime
change is needed. Existing ordinary `native_plugin_search_scope_test.exs`
independently chooses unique string IDs before dispatch, preserves original
outgoing and incoming bytes/maps, checks whole sent requests and their encoded
bytes, matches the returned ID and requires exactly id/result response keys.

Twenty-four real plugin/search exchanges use independent inert local catalog
fixtures through held/restored catalogs and a distinct cold native process.
Expected selected candidate fields/ranking come from fixture literals. They
remain a selected PluginSummary projection, not whole-result conformance. The
complete inventory stays 30 correlated pairs, including six incidental non-search
pairs; those incidental calls receive no ID credit here. Original 32-frame per
direction, 4 KiB outgoing/64 KiB incoming, 1 MiB total, five-second RPC and
60-second module bounds remain. Provider/workspace/rollout/config controls,
hold/restore cleanup and checked owned-process shutdown remain unchanged.

Only **1464**, `schema:ClientRequest.json#/oneOf/73/properties/id`, gains scoped
implemented evidence. Exact node SHA256
`f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`
and parent method plugin/search are recomputed in the complete canonical export.
Same-hash sibling fields, RequestId alternatives, whole method/params/results
and other plugin methods gain nothing. Lookup uses unique strings in this
profile; it does not demonstrate integer-versus-string/float distinction,
reused IDs or cross-generation correlation.

Eight declaration/RPC/dispatch/search-processor/outgoing/transport source files
match the official archive at Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`. The actual native local search reads,
selects and ranks the supplied catalog data; generic typed response construction
retains its connection-scoped request ID. Remote backends are not credited.

Test SHA256 remains
`93602b891fcd506b256426212cd9638f500073982a21d3fe8970a3567a221e5c`.
All 417 V450 source hashes and nine successful log hashes remain exact; both
reviewed **58/0** ordinary command lists enable this unchanged file. No new
native/test run occurs. V450's focused **1/0** is the filesystem case. The
[filesystem record](filesystem-typed-id-qualification.md) binds the current
command/result/guard hashes and outside consumer; earlier V443/V447 evidence
remains historical. Inventory consistency and diff whitespace are checked.

Report `/tmp/samgita-v453-candidate.md`, SHA256
`bd862dad9d089caf6b418d3fda7292d7aad6bd432669a2e1bc3faa6f60d80a20`;
binder `/tmp/samgita-v453-bind.py`; source/node binding SHA256
`dad5ea6c34879fe57257f7f66af98be6e97aa0326bbb82835ffaf4b90b11e974`;
evidence SHA256
`c6e0b15aaf4d97ff8f505dde1a91ccc4c44d6369957d6e63d7c9c281381ea7fb`.

Contracts: **5,272 implemented / 1,269 missing / 80 blocked**; requirements
remain **462 implemented / 12 missing / 11 blocked**, zero verified in both.
No integer/all-string/concurrent/reconnect/pagination/remote-catalog or complete
PluginSummary/method/transport/OS/full-goal claim follows. Fixed YOLO remains
setup only; security/permission tests and audits, broad suites and hosted
workflows remain unrun. A11, unavailable producers, external/platform and release
gates remain incomplete. No publication or deployment. Rollback reverts this
one evidence binding and documentation. Continue permitted aggregate static
qualification and the next independently reachable native gap.
