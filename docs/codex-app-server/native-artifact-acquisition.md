# Locked platform native artifact acquisition

This repairs CI dependency acquisition, not Codex behavior or full conformance.
The retained MDEx native version, checksum and compile-time verification remain
unchanged. No dependency is patched, audit suppressed, TLS verification disabled
or HTTP header limit raised.

## Reproduction and cause

Selected conformance at `e82f32f` in
[40034198690](https://github.com/gsmlg-opt/Samgita/actions/runs/40034198690)
passed native wire, driver and outside-consumer checks, then failed before
platform tests while RustlerPrecompiled 0.9.0 acquired `mdex_native` 0.2.8.
The actual retained OTP `:httpc.request/4` independently reproduces
`{:header_too_long, {:max, 10240}}` for the official release redirect.
The measured GitHub 302 headers total 10,877 bytes, including a 9,217-byte
Content-Security-Policy and 1,017-byte Location. Final asset headers total
921 bytes. This establishes acquisition failure before native loading; it
does not implicate platform behavior. A first scratch probe used nonexistent
request/3 and was corrected before recording this reproduction.

## Repair and boundary

`scripts/codex/prime_platform_nif.py` primes the documented
`RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH`. It derives the exact version from root
`mix.lock`, requires exactly one SHA256 from that locked dependency's checksum
file, and downloads the unchanged Linux x86_64 GNU/default/NIF 2.15 archive.
HTTPS redirects are restricted to GitHub and its release-asset host. The body
is bounded to 16 MiB; no account credential is sent or signed redirect logged.
Checksum mismatch, missing/duplicate checksum, oversized body and corrupt
existing cache fail closed. Corrupt cache is preserved for diagnosis. Verified
bytes are published atomically. RustlerPrecompiled verifies its own checksum
again before extraction and loading.

The selected Linux conformance job initializes a scratch cache through
`$RUNNER_TEMP`/`$GITHUB_ENV`, after checkout and before dependency resolution.
Job-level `env` cannot use the `runner` context; the initial draft's use was
caught in source review and removed. Priming occurs after root `mix deps.get`
and before platform compilation. Other package graphs and version pins are
unchanged. This helper is deliberately scoped to this declared runner/variant;
it does not qualify other architectures, libc or MDEx feature variants.

## Evidence

The six deterministic downloader tests passed, followed by all 37 inventory
and script regressions. They cover cache hit without credentials, corrupt
download/cache, missing/duplicate checksum, size bound and forbidden redirect.
These tests use inert bytes and are not native-code qualification.

The exact official archive was then acquired into an empty scratch cache and
loaded by an independent, initially empty MDEx consumer outside the umbrella:

```sh
python3 -B scripts/codex/prime_platform_nif.py --cache-dir /tmp/samgita-codex-nif-prefetch-20261024
```

In `/tmp/samgita-mdex-native-prefetch-proof-20261024`, using the verified Devenv
environment, `MIX_ENV=test` and that explicit cache variable:

```sh
mix deps.get
mix compile --warnings-as-errors
mix run --no-start -e '{:module, MDExNative.Native} = :code.ensure_loaded(MDExNative.Native); IO.puts("Cold verified MDEx native load passed")'
```

All three cold-consumer commands passed. Local logs are
`/tmp/samgita-httpc-red-20261024.log`,
`/tmp/samgita-cold-deps-20261024.log`,
`/tmp/samgita-cold-compile-20261024.log` and
`/tmp/samgita-cold-load-20261024.log`.
Hosted success still requires a new selected-conformance run on the pushed
repair. Earlier native/profile/aggregate results do not substitute for it.
Completeness, A11, external integration, publication and deployment remain
separate unmet gates.
