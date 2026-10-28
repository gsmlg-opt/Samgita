# Ordinary Apps request IDs

V537 continues from `5e27ddc` with stock `rust-v0.163.0`, source
`83086188ae0614bd882818ff1aa23f3194962012`, executable SHA256
`399ff69c431c066e40de318fba45c2b07f45a76b19939d247ee4828fc70c4215`.
Only two existing ordinary tests change. Production driver, helpers, schemas,
configuration and platform data remain unchanged.

## Real correlation with retained business oracles

The nine existing `app/read` calls use numeric/string twins `-1`/`"-1"` and
`1`/`"1"` in one warm connection, a Unicode string, then zero, signed i64 minimum,
signed i64 maximum and another Unicode string in a distinct cold process.
The three existing `app/list` calls use negative/positive integers and a Unicode
cold ID. Strict original request/reply pinning, Wire round trips, per-ID capture
lookup and exact outgoing ID sequences preserve JSON types through actual native
handlers. Generated control IDs cannot collide with the explicit business IDs.

All independent metadata, ordered/deduplicated/missing-ID, cache promotion/hiding,
backend-batch and cold-refetch oracles remain. The read case still accounts for
nineteen outgoing envelopes/seventeen request-reply pairs; the list case retains
thirteen/eleven and three genuinely emitted updates. Every prior bound, idle
assertion and native/dependency Port/owner/PID cleanup remains. No new RPC,
dependency, model/tool operation or fabricated app-server message is introduced.

Only physical ClientRequest ID owners **1519** (`app/read`) and **1524**
(`app/list`) gain scoped implemented evidence. `app/installed` owner1529,
RequestId-definition aliases, response schemas and other envelopes receive none.
Fixed YOLO remains inert setup; no security or permission behavior is tested.

## Immutable source and independent review

Six complete official ID-route files/eighteen excerpts trace the typed
String-or-i64 RequestId through both dispatch paths and the common native result
serializer. Fifteen earlier producer files are rechecked; sixteen unique whole
official files match the archive. The retained ClientRequest has172 variants
versus105 in the public archive: whole roots differ. Matching actual methods
proves retained83/read equals archive48 and retained84/list equals archive49,
including complete envelopes and RequestId. Both selected canonical ID nodes
have SHA256 `f1fb3724bb7835add8ed79ef8a7e1acaf3c9c5761502e6ae54c85d0c7f6c82e7`.

Independent source review confirms exactly the declared ID-only edits; reversing
them restores each complete baseline. Formatting changes layout only. Existing
60-second case/5-second RPC deadlines and all buffer bounds are unchanged.

## Focused native evidence

From the verified environment, formatting and both two-case runs pass:

```sh
devenv shell --no-tui -- python3 -B /tmp/samgita-v537-focused.py
```

That recipe runs `mix format` on exactly the two changed files, then
`mix test test/native_ordinary_apps_read_metadata_test.exs test/native_ordinary_catalog_metadata_notification_test.exs --warnings-as-errors --seed <seed>`
from the standalone driver at seeds `501432` and `987654`, **2/0 each**.
The [combined final-source qualification](ordinary-app-pagination-qualification.md#final-combined-source-functional-qualification)
also passes all **14 reviewed steps**, including **138 actual-native cases twice**,
three selected WebSocket seeds, outside consumer **1/0** and static/build checks.
Its binding preserves this exact formatted read test and the list ID delta after
adding pagination; all other earlier business oracles remain. These results do
not establish the complete compatibility matrix.

| Artifact | SHA256 |
| --- | --- |
| `/tmp/samgita-v537-source-evidence.json` | `4628e0740708f2e6e413e54b3016a2d7d69c868672c4482b295b8e0e34aff9ea` |
| `/tmp/samgita-v537-independent-review.json` | `c41328d3b2be4f37f72d92c408af2576b931c67ddbacb3ae1515fc0db4ec8dd2` |
| Formatted read test | `7e03af3c19c1a164545fbc128d0e052328a53d390d6b1625b75e3c4671b32fdc` |
| Formatted list test before pagination | `30f2ba890be7b0429b6e3bb2a16626d13d5b09cd01223801d8a419bf42c3b1c2` |
| `/tmp/samgita-v537-focused-501432.log` | `5c55dbc8e1963248d8c1b21caf045c4deb7e2719e843c740007ee1483e551f14` |
| `/tmp/samgita-v537-focused-987654.log` | `f300705febd75e897b7c41e7d455efe2cf25b7997cccc8ab332e32e0cd7b25ad` |
| `/tmp/samgita-v537-focused-results.json` | `02dd500b8b889e7e40bdc36854bb8f3608c0aeced0a4d32088962936a9e561e5` |

## Rollback and limits

Rollback restores these two tests/manifest rows and the reviewed fingerprint.
No migration or historical data change is involved. Counts after this unit:
**5,573 implemented / 918 missing / 130 blocked** contracts; requirements remain
**462 implemented / 12 missing / 11 blocked**, **zero globally verified**.
Other OS/transports, real backends, A11, unavailable emitters and full compatibility
remain incomplete. Prohibited tests/audits and hosted workflows remain unrun;
no tag, publication or deployment occurs.
