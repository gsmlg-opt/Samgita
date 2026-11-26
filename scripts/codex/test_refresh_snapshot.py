"""Functional regression checks for staging a snapshot refresh."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import refresh_snapshot


class RefreshSnapshotTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="samgita-refresh-functional-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.snapshot = self.root / "apps/samgita_protocol_codex/priv/upstream/current"
        self.manifest = self.root / "docs/codex-app-server/compatibility-manifest.json"
        self.fixtures = self.root / "apps/samgita_protocol_codex/test/fixtures/native/contracts.json"
        for path in (self.snapshot / "source.json", self.manifest, self.fixtures):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("original\n")
        for name in refresh_snapshot.CARRIED:
            path = self.snapshot / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("retained dependency source\n")
        self.cache = self.root / "tmp/codex/candidate"
        self.cache.mkdir(parents=True)
        self.generator = self.cache / "codex"
        self.before = self.contents()

    def contents(self):
        return {str(path.relative_to(self.root)): path.read_bytes()
                for path in self.root.rglob("*") if path.is_file()}

    def generate(self, command, **_kwargs):
        scripts = Path(command[2]).parent
        staged = scripts.parents[1]
        snapshot = staged / self.snapshot.relative_to(self.root)
        if "--generate" in command:
            (snapshot / "candidate.json").write_text('{"generated": true}\n')
            (staged / self.manifest.relative_to(self.root)).write_text("candidate inventory\n")
        elif scripts.joinpath("generate_fixtures.py") == Path(command[2]):
            fixtures = staged / self.fixtures.relative_to(self.root)
            fixtures.parent.mkdir(parents=True)
            fixtures.write_text("candidate fixtures\n")
        return subprocess.CompletedProcess(command, 0)

    def refresh(self, run):
        with patch.object(refresh_snapshot, "ROOT", self.root), \
             patch.object(refresh_snapshot, "SNAPSHOT", self.snapshot), \
             patch.object(refresh_snapshot.subprocess, "run", side_effect=run):
            refresh_snapshot.regenerate({"version": "candidate"}, self.generator, self.cache)

    def test_generation_failure_preserves_snapshot_inventory_and_fixtures(self):
        def fail(command, **kwargs):
            self.generate(command, **kwargs)
            raise subprocess.CalledProcessError(1, command)

        with self.assertRaises(subprocess.CalledProcessError):
            self.refresh(fail)
        self.assertEqual(self.contents(), self.before)

    def test_checked_generation_installs_the_matching_artifacts(self):
        commands = []

        def run(command, **kwargs):
            commands.append(command)
            return self.generate(command, **kwargs)

        self.refresh(run)
        self.assertEqual(len(commands), 3)
        self.assertEqual(commands[-1][-1], "--check")
        self.assertEqual(json.loads((self.snapshot / "source.json").read_text()),
                         {"version": "candidate"})
        self.assertTrue((self.snapshot / "candidate.json").is_file())
        self.assertEqual(self.manifest.read_text(), "candidate inventory\n")
        self.assertEqual(self.fixtures.read_text(), "candidate fixtures\n")
        self.assertEqual(list(self.cache.parent.iterdir()), [self.cache])


if __name__ == "__main__":
    unittest.main()
