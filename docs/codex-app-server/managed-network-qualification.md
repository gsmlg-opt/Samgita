# Disabled managed-network metadata

Status: selected actual-native implementation evidence; complete compatibility
and network enforcement remain unqualified. The target is immutable Codex
`rust-v0.163.0`, source `83086188ae0614bd882818ff1aa23f3194962012`, Linux binary
SHA256 `399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.

`native_managed_network_requirements_test.exs` uses the existing managed-policy
fixture, with a proved private user/mount/network namespace and read-only
`/etc/codex/requirements.toml`. It never starts a thread, turn or proxy. The
user config explicitly disables the network-proxy feature, Apps, plugins,
recommendations, shell snapshots and update checks. Every present network
policy has `enabled = false`; dangerous, upstream and local-binding flags are
false. Hostnames are synthetic `.invalid` metadata; socket paths are owned,
never-created fixture paths.

Five actual-native cases prove:

- Exact canonical thirteen-field network metadata, including inert ports,
  allow/deny maps and lexically sorted compatibility lists.
- Absent network versus a sparse object, explicit nullable scalar fields,
  canonical empty maps versus empty legacy lists.
- Legacy duplicate collapse and deny precedence, without rewriting its source.
- Requirements-file reload, exact complete response changes, restoration and
  cold restart, while owned user-config bytes remain unchanged.
- Sixteen malformed-policy cases: boolean types, unsigned port types/ranges,
  unknown permissions and conflicting canonical/legacy representations. Each
  returns a native internal parse error and recovers exactly after restoring
  the valid policy. Failed reads do not write user config or start work.

Every observation also requires empty loaded-thread state, no pending request,
interaction or uncertain operation, absent owned socket paths and empty TCP/TCP6
tables in the proved private native network namespace. This establishes no
observed socket during this disabled metadata journey. It does not qualify a
proxy listener, runtime allow/deny enforcement, real network service or every
internal persistence store. Cleanup proves both owned processes have exited.

The source contract is
[the API metadata type](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server-protocol/src/protocol/v2/config.rs#L713-L750),
[canonical/legacy normalization](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/config/src/config_requirements.rs#L465-L570)
and [the response projection](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/app-server/src/request_processors/config_processor.rs#L812-L878).
`configRequirements/read` reloads fresh thread-agnostic layers; it reports
requirements rather than running a model or enforcing an execution policy.

Validation ran serially through `devenv shell --no-tui --` with `MIX_ENV=test`
and the exact binary. From the driver:

```sh
mix compile --warnings-as-errors
mix test test/native_prediction_boundary_test.exs test/native_managed_network_requirements_test.exs --seed 501432
mix test test/native_prediction_boundary_test.exs test/native_managed_network_requirements_test.exs --seed 987654
mix format --check-formatted test/native_prediction_boundary_test.exs test/native_managed_network_requirements_test.exs
```

Both combined runs passed **11/0** (six prediction cases plus five network
cases), 12.5/12.4s, with namespace preflight and strict Credo. The initial run
passed both native repeats but failed two string-readability checks. Sigils keep
the same TOML bytes; the repeated native and strict static checks pass. Commands,
exits and full logs: `/tmp/samgita-native-prediction-network-20261024-attempt02/`.

Only seventeen exact owning contracts gain `implemented` evidence: the network
field, thirteen network metadata fields, domain `allow`, and Unix-socket
`allow`/`deny`. No sibling schema, union wrapper or fully verified status changes.
True enabled/dangerous flags, all deployment profiles, runtime enforcement and
external services remain unqualified. Final combined-source and hosted checks
remain required; this unit does not close A11 or authorize release/deployment.
