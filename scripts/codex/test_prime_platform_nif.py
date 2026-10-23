"""Downloader integrity/error tests, not native Codex conformance evidence."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest

import prime_platform_nif as prefetch


class Response(io.BytesIO):
    status = 200


class Opener:
    def __init__(self, body):
        self.body = body
        self.requests = []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        return Response(self.body)


class PrimePlatformNifTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="samgita-nif-integrity-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.cache = self.root / "cache"
        self.body = b"synthetic owned archive bytes, never loaded as native code"
        (self.root / "mix.lock").write_text('"mdex_native": {:hex, :mdex_native, "0.2.8"},\n')
        checksum_dir = self.root / "deps/mdex_native"
        checksum_dir.mkdir(parents=True)
        self.name = "libmdex_native_nif-v0.2.8-nif-2.15-x86_64-unknown-linux-gnu.so.tar.gz"
        self.checksums = checksum_dir / "checksum-Elixir.MDExNative.Native.exs"
        self.checksums.write_text('%{"' + self.name + '" => "sha256:' +
                                  hashlib.sha256(self.body).hexdigest() + '"}\n')

    def test_verified_download_and_cache_hit_send_no_credentials(self):
        opener = Opener(self.body)
        path = prefetch.prime(self.root, self.cache, opener)
        self.assertEqual(path.read_bytes(), self.body)
        self.assertEqual(prefetch.prime(self.root, self.cache, opener), path)
        self.assertEqual(len(opener.requests), 1)
        request, timeout = opener.requests[0]
        self.assertEqual(request.full_url, "https://github.com/leandrocp/mdex_native/releases/download/v0.2.8/" + self.name)
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual(timeout, 30)

    def test_bad_download_is_not_published_to_cache(self):
        with self.assertRaisesRegex(ValueError, "downloaded artifact checksum"):
            prefetch.prime(self.root, self.cache, Opener(b"corrupted"))
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_corrupt_existing_cache_is_preserved_and_fails_closed(self):
        self.cache.mkdir()
        path = self.cache / self.name
        path.write_bytes(b"preserve for diagnosis")
        opener = Opener(self.body)
        with self.assertRaisesRegex(ValueError, "existing cached artifact checksum"):
            prefetch.prime(self.root, self.cache, opener)
        self.assertEqual(path.read_bytes(), b"preserve for diagnosis")
        self.assertEqual(opener.requests, [])

    def test_missing_or_duplicate_package_checksum_sends_nothing(self):
        checksum = self.checksums.read_text()
        for contents in ("%{}", checksum + checksum):
            self.checksums.write_text(contents)
            opener = Opener(self.body)
            with self.assertRaisesRegex(ValueError, "exactly one"):
                prefetch.prime(self.root, self.cache, opener)
            self.assertEqual(opener.requests, [])

    def test_oversized_archive_is_rejected_before_cache_publication(self):
        with self.assertRaisesRegex(ValueError, "bounded download"):
            prefetch.prime(self.root, self.cache, Opener(b"x" * (prefetch.MAX_BYTES + 1)))
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_redirect_rejects_downgrades_credentials_and_unapproved_hosts(self):
        redirect = prefetch.ReleaseRedirect()
        for url in ("http://github.com/a", "https://other.example/a", "https://user:pass@github.com/a"):
            with self.assertRaisesRegex(ValueError, "unexpected release redirect"):
                redirect.redirect_request(None, None, 302, "redirect", {}, url)


if __name__ == "__main__":
    unittest.main()
