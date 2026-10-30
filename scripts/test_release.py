"""Functional coverage for coordinated versions and standalone package staging."""

from pathlib import Path
import shutil
import tempfile
import unittest

import release


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="samgita-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "checkout"
        for path in release.manifests():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(release.ROOT / path, self.root / path)
        self.current = release.VERSION.search((self.root / "mix.exs").read_text()).group(2)
        for name, files in release.PACKAGE_FILES.items():
            for item in files:
                source = release.ROOT / "apps" / name / item
                target = self.root / "apps" / name / item
                if item == "mix.exs":
                    continue
                if source.is_dir():
                    shutil.copytree(source, target)
                else:
                    shutil.copy2(source, target)
        self.output = Path(self.temporary.name) / "packages"
        major = int(self.current.split(".")[0]) + 1
        self.next_version = f"{major}.2.3"

    def test_updates_both_root_versions_all_apps_and_sibling_requirements(self):
        release.prepare(self.root, self.next_version, self.output)
        for path in release.manifests():
            source = (self.root / path).read_text()
            versions = [m.group(2) for m in release.VERSION.finditer(source)]
            self.assertEqual(versions, [self.next_version] * (2 if path == Path("mix.exs") else 1))
        for name, dependency in release.SIBLINGS.items():
            source = (self.root / "apps" / name / "mix.exs").read_text()
            self.assertIn(f'{{:{dependency}, "~> {self.next_version}", path: "../{dependency}"}}', source)

    def test_staged_packages_use_hex_requirements_and_preserve_publishable_inputs(self):
        release.prepare(self.root, self.current, self.output)
        for name, files in release.PACKAGE_FILES.items():
            staged = self.output / name
            self.assertEqual({p.name for p in staged.iterdir()}, set(files))
            self.assertEqual((staged / "LICENSE").read_bytes(), (release.ROOT / "LICENSE").read_bytes())
            self.assertNotRegex((staged / "mix.exs").read_text(), r"\bpath:")
            for item in files:
                if item == "mix.exs":
                    continue
                source = self.root / "apps" / name / item
                paths = source.rglob("*") if source.is_dir() else [source]
                for path in paths:
                    if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                        self.assertEqual(path.read_bytes(), (staged / path.relative_to(source.parent)).read_bytes())

    def test_generated_python_cache_is_excluded_from_package_sources(self):
        cache = self.root / "apps/samgita_codex_driver/priv/__pycache__"
        cache.mkdir(exist_ok=True)
        (cache / "local.pyc").write_bytes(b"generated-cache")
        release.prepare(self.root, self.current, self.output)
        self.assertFalse((self.output / "samgita_codex_driver/priv/__pycache__").exists())

    def test_same_version_is_valid_for_initial_publication(self):
        before = {path: (self.root / path).read_bytes() for path in release.manifests()}
        release.prepare(self.root, self.current, self.output)
        self.assertEqual(before, {path: (self.root / path).read_bytes() for path in release.manifests()})

    def test_inconsistent_version_does_not_partially_update_manifests(self):
        path = self.root / "apps/samgita/mix.exs"
        path.write_text(path.read_text().replace(f'version: "{self.current}"', 'version: "999.0.0"'))
        before = {path: (self.root / path).read_bytes() for path in release.manifests()}
        with self.assertRaisesRegex(ValueError, "unexpected version declarations"):
            release.prepare(self.root, self.next_version, self.output)
        self.assertEqual(before, {path: (self.root / path).read_bytes() for path in release.manifests()})
        self.assertFalse(self.output.exists())

    def test_missing_package_input_leaves_versions_unchanged(self):
        (self.root / "apps/samgita_protocol/LICENSE").unlink()
        with self.assertRaisesRegex(ValueError, "missing package input"):
            release.prepare(self.root, self.next_version, self.output)
        self.assertIn(f'version: "{self.current}"', (self.root / "mix.exs").read_text())
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
