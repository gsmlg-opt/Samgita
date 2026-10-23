# Environment and permission-profile discovery

`apps/samgita_codex_driver/test/environment_profiles_test.exs` contains six
actual pinned Codex `rust-v0.163.0` cases using independent stdio Sessions and
owned temporary configuration. Source/binary hashes match
[qualification](qualification.md). Every case requires zero model requests;
no remote executor, account or service is provisioned.

| Profile | Observed result |
| --- | --- |
| Local environment | `environment/info` returns the current local shell and exact owned `file://` cwd. Repeated `environment/status` is `ready`. |
| Unknown identity | Unknown IDs yield `unknown` status with detail, while info returns the exact native request error. They do not create environments. |
| Rejected registration and negotiation | Empty/reserved IDs, empty/disabled URLs and insecure nonloopback header-bearing endpoints are rejected without registration. Experimental negotiation disabled reaches actual upstream rejection for all three environment methods. Stable permission discovery still works. |
| Catalog and pagination | Builtin and configured profile order, nullable descriptions, omitted/null/zero limits and boundary/invalid cursors retain native results. |
| Trusted project cwd | Cwd-specific discovery includes only the appropriate trusted project catalog without writing a selected/default profile. |
| Allowed metadata | Cwd-dependent profile compilation changes `allowed` while retaining the profile entry. This establishes discovery metadata, not sandbox enforcement. |

`PermissionProfileSummary` has `id`, `description` and `allowed`; it has no
`enabled` field. The initial negotiation assertion encountered local driver
preflight. As in other native gate tests, `validation: :wire` now proves the
actual binary's exact rejection rather than substituting a local error.

Pinned source, relative to `codex-rs/`:

- `app-server/src/request_processors/environment_processor.rs:18-99` and
  `app-server-protocol/src/protocol/v2/environment.rs:38-147`.
- `app-server-protocol/src/protocol/v2/permissions.rs:391-423`: catalog shape;
  `app-server/src/request_processors/catalog_processor.rs:450-505`: pagination.
- `app-server/tests/suite/v2/permission_profile_list.rs:20,93,178,243` and
  `core/src/config/permission_profile_catalog.rs:47-95`: cwd/allowed profiles.
- `exec-server/src/environment.rs:509-526,568-584` and
  `exec-server/src/client.rs:439-456`: successful add installs a WebSocket
  transport and immediately starts connecting. `deferred_executor` does not
  make successful registration inert.

Scoped warnings-as-errors compile/format passed; **6 tests passed** at each seed
`501432` and `987654`. The integrated profile/plugin/filesystem/environment
run passed **22 tests**, seed `501432`, with strict Credo also passing. Its log
is `/tmp/samgita-operation-profiles-static-check.log`.

The environment and permission-list request/response entries have selected
implementation evidence, not full verification. Successful remote registration,
connecting/connected/failed remote states, remote shell/filesystem behavior and
other transport/OS/backend profiles remain unqualified. A supported owned local
executor fixture is a next implementation prerequisite; failure-only evidence
does not qualify remote success. No live credentials, remote changes or
deployment occurred.
