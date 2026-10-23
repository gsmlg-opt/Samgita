"""Offline integrity tests; synthetic payloads are never executed."""
import hashlib
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import fetch_pin


class BundledSandboxIntegrityTest(unittest.TestCase):
    payload = b"synthetic resource bytes; never an executable\n"

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="samgita-pin-integrity-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.archive = self.root / "sidecar.tar.gz"
        self.destination = self.root / "codex-resources/bwrap"
        pin = patch.object(fetch_pin, "BWRAP_SHA256", hashlib.sha256(self.payload).hexdigest())
        pin.start()
        self.addCleanup(pin.stop)

    def write_archive(self, names=None, payload=None, link=False):
        with tarfile.open(self.archive, "w:gz") as archive:
            for name in names or [fetch_pin.BWRAP_MEMBER]:
                member = tarfile.TarInfo(name)
                member.mode = 0o755
                if link:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "../outside"
                    archive.addfile(member)
                else:
                    content = self.payload if payload is None else payload
                    member.size = len(content)
                    archive.addfile(member, io.BytesIO(content))

    def test_installs_exact_bytes_and_reuses_verified_cache(self):
        self.write_archive()
        fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(self.destination.read_bytes(), self.payload)
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o755)
        before = self.destination.stat().st_mtime_ns
        self.archive.unlink()
        fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(self.destination.stat().st_mtime_ns, before)
        self.assertEqual(list(self.destination.parent.iterdir()), [self.destination])

    def test_replaces_corrupt_cached_bytes_only_after_verification(self):
        self.write_archive()
        self.destination.parent.mkdir()
        self.destination.write_bytes(b"corrupt")
        fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(self.destination.read_bytes(), self.payload)

    def test_wrong_payload_never_replaces_cached_file(self):
        self.write_archive(payload=b"different resource")
        self.destination.parent.mkdir()
        self.destination.write_bytes(b"preserve original")
        with self.assertRaisesRegex(SystemExit, "payload SHA-256 mismatch"):
            fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(self.destination.read_bytes(), b"preserve original")

    def test_extra_and_path_selected_members_are_rejected_without_extraction(self):
        for names in [[fetch_pin.BWRAP_MEMBER, "extra"], ["../outside"], ["/absolute"], ["other"]]:
            with self.subTest(names=names):
                self.write_archive(names=names)
                with self.assertRaisesRegex(SystemExit, "archive members"):
                    fetch_pin.install_bwrap(self.archive, self.destination)
                self.assertFalse(self.destination.parent.exists())
                self.assertFalse((self.root / "outside").exists())

    def test_archive_link_is_not_a_regular_resource(self):
        self.write_archive(link=True)
        with self.assertRaisesRegex(SystemExit, "archive members"):
            fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertFalse(self.destination.parent.exists())

    def test_destination_link_preserves_outside_file(self):
        self.write_archive()
        outside = self.root / "outside"
        outside.write_bytes(b"preserve outside")
        self.destination.parent.mkdir()
        self.destination.symlink_to(outside)
        with self.assertRaisesRegex(SystemExit, "symlinks"):
            fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(outside.read_bytes(), b"preserve outside")

    def test_destination_directory_link_preserves_outside_directory(self):
        self.write_archive()
        outside = self.root / "outside"
        outside.mkdir()
        self.destination.parent.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(SystemExit, "symlinks"):
            fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(list(outside.iterdir()), [])

    def test_nonexecutable_cached_resource_fails_closed(self):
        self.destination.parent.mkdir()
        self.destination.write_bytes(self.payload)
        self.destination.chmod(0o644)
        with self.assertRaisesRegex(SystemExit, "verification failed"):
            fetch_pin.install_bwrap(self.archive, self.destination)
        self.assertEqual(self.destination.stat().st_mode & 0o777, 0o644)


if __name__ == "__main__":
    unittest.main()
