# Native Gateway login and private Secret Service persistence

The independent Session drives stock Codex `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, binary SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
The final profile passes **1 test / zero failures** at seeds `501432` and
`987654`, 5.4/8.7 seconds. This qualifies selected native client behavior using
an owned synthetic OAuth issuer and a real private GNOME Secret Service. It is
not real-account, external-issuer, token-rotation or full compatibility evidence.

## Behavior and ownership

`native_gateway_success_profile.exs` connects `SamgitaCodexDriver.Session` directly
to the native WebSocket UDS. The controller's stdin accepts fixture controls;
it never emits, proxies or rewrites app-server messages. The only copied native
frame is the observed authorization handoff, used to validate the genuine
loopback callback. The HTTP dependency verifies state, redirect, client, body,
S256 PKCE, absent primary credentials and exactly one token exchange before
issuing fixed synthetic tokens. No model turn, browser or paid task starts.

The test observes pending login, duplicate rejection, the correlated empty
successful result, exactly one public `succeeded` notice, passive readiness and
idle cancellation. Native Codex creates `secrets/gateway_oauth.age` and its own
passphrase in the real unlocked private keyring. Metadata-only SearchItems
proves one native item; the fixture never retrieves that secret. After closing
the client and confirming the first native process has stopped, a second native
process reads readiness using the same storage and bus. Ciphertext digest and
keyring-item identity stay unchanged, with no second handoff or token exchange.

Primary `account/logout` acknowledges and emits the exact null account projection.
For this provider, `requires_openai_auth=false`; the independent Gateway store
and readiness remain unchanged. This pin has no Gateway-delete/logout RPC.
Removing disposable fixture storage during teardown is not app-server logout.

The fixture creates mode-0700 HOME/XDG/control directories, an EXTERNAL-auth
filesystem session bus with no activation directories, and an explicitly absent
system-bus address. The real daemon's bus owner PID, unlocked default collection,
version and executable digest are checked. A private user/network namespace has
only loopback and no default routes. After configuring loopback, `setpriv`
irreversibly clears every capability set and locks `noroot`/`no_new_privs` before
starting any service or native process. All five zero masks and `NoNewPrivs=1`
are asserted. There is no host keyring/bus fallback or native sandbox override.

Native restart occurs only after known login completion. Client close preserves
the borrowed native server; explicit controller restart owns process shutdown.
Cleanup has a shared 0.65-second budget and uses only recorded direct children.
The original production Stdio cleanup remains unchanged. The test confirms all
recorded PIDs are gone, no cleanup errors, deletion of owned secret directories
and canary-free bounded diagnostics. Sanitized state/logs are retained in
`/tmp/sg-gw-*-diagnostics`; credentials and keyring storage are excluded.

## Reproductions and corrections

The private keyring prerequisite initially failed before any Codex process:
GNOME reported `failed dropping capabilities - -11`. Matching GNOME50 source
`daemon/gkd-capability.c:99-120` invokes
`capng_change_id(..., CAPNG_DROP_SUPP_GRP | CAPNG_CLEAR_BOUNDING)` when namespace
root has capabilities. libcap-ng0.9.3 `src/cap-ng.c:1296-1300` returns -11 when
`setgroups(0,NULL)` is forbidden by the namespace's `setgroups=deny`. This is not
errno EAGAIN or a D-Bus readiness delay. Clearing capabilities before exec selects
GNOME's supported unprivileged branch. The unchanged prerequisite deadlines then
pass real service ownership, unlocked collection, encrypted keyring and reaping.

Initial and diagnostic Session runs each failed **1/1** during setup. The native
listener was already ready: the draft incorrectly required `lstat` to identify
a socket. Pinned `app-server-transport/src/transport/unix_socket.rs:94-119` and
`unix_socket_tests.rs:385-428` show the native rendezvous is a symlink. The fixture
now verifies its exact deterministic owned target, socket type, UID and 0600 mode,
then requires native shutdown to remove alias, physical socket and lock. It does
not unlink an arbitrary target. Teardown also incorrectly required the control
directory to remain present; GNOME removes its own control socket and directory
(`gkd-control-server.c:395-402`, `gkd-util.c:73-78,150-152`). Only this known owned
directory may already be absent; present symlinks remain rejected.

The corrected native startup then reached login; its first and diagnostic runs
each failed **1/1** because the control validator omitted the genuine native
`emittedAtMs` envelope field. The controller now preserves it and validates its
positive integer value, matching upstream `outgoing_message.rs:950-983`.
No production protocol or deadline changed. All failed-run PIDs were checked
gone; no ambiguous login was retried. Final native runs and static checks pass.

Local GNOME50.0 came from existing pinned Nixpkgs
`c8f90650c15282fa8656a041bfbbd2403997a9a7`, without changing repository manifests.
Its executable wrapper SHA256 is
`9432989b2d37c874a84a47b6a34d9a33e4638e5ade38150e256440957d29fec8`.
Source references use GNOME commit `2ff8b070763ae025b90916a7b98643865819b451`
and official libcap-ng tag `v0.9.3`. The CI profile explicitly installs real
GNOME/D-Bus/GLib tools and records its actual daemon version/digest; local success
does not establish that CI profile until its run completes.

## Commands and evidence limits

In verified Devenv, from `apps/samgita_codex_driver`, with `MIX_ENV=test`, exact
`CODEX_BINARY`, and executable `GNOME_KEYRING_DAEMON`/`GDBUS` overrides where the
tools are absent from PATH:

```sh
mix compile --warnings-as-errors
mix test test/native_gateway_success_profile.exs --seed 501432
mix test test/native_gateway_success_profile.exs --seed 987654
mix format --check-formatted test/native_gateway_success_profile.exs
```

Both Python files pass AST parsing; required namespace preflight and scoped root
strict Credo pass. Final logs:
`/tmp/samgita-gateway-success-envelope-fix-*-20261024.log`. Earlier prefixes
`gateway-success-initial`, `gateway-success-diagnostic`,
`gateway-success-native-fix` and `gateway-success-callback-diagnostic` retain
failures. The diagnostic controller run also identified the exact symlink and
control-directory assertions; it is not a driver acceptance test.

Only `server_response:account/gatewayOAuth/login` and the actual `succeeded`
status contract newly advance to scoped implemented. Existing Gateway rows gain
this evidence without inferring backend use or credential refresh. No row becomes
fully verified. Multi-owner privacy, pending disconnect/reconciliation, daemon
restart/reboot, rotation/expiry, real providers, other OS profiles, A11 and final
aggregate/hosted gates remain incomplete. Core/driver consumers gain no GNOME,
Repo, Phoenix, platform configuration or automatic-listener dependency.
