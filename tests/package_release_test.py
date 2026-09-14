"""Release artifact contracts use only disposable fixtures and local commands."""

import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("package_release", ROOT / "scripts/package_release.py")
packaging = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(packaging)
CHECK_SPEC = importlib.util.spec_from_file_location("check_release_package", ROOT / "scripts/check_release_package.py")
checking = importlib.util.module_from_spec(CHECK_SPEC)
CHECK_SPEC.loader.exec_module(checking)


class PackagingTests(unittest.TestCase):
    def test_verifier_rejects_archive_escape_and_links_before_extraction(self):
        with tempfile.TemporaryDirectory() as fixture:
            for variant in ("traversal", "symlink", "hardlink"):
                archive_path = Path(fixture) / (variant + ".tar.gz")
                target = Path(fixture) / variant
                target.mkdir()
                with tarfile.open(archive_path, "w:gz") as archive:
                    member = tarfile.TarInfo("../escape" if variant == "traversal" else "package/escape")
                    if variant == "traversal":
                        member.size = 1
                        archive.addfile(member, io.BytesIO(b"x"))
                    else:
                        member.type = tarfile.SYMTYPE if variant == "symlink" else tarfile.LNKTYPE
                        member.linkname = "../../outside"
                        archive.addfile(member)
                with self.assertRaises(ValueError):
                    checking.extract(archive_path, target)
                self.assertEqual(list(target.iterdir()), [])

    def test_inventory_excludes_prebuilt_helpers_and_private_root_files(self):
        for name in ("mole", "bin/clean.sh", "cmd/analyze/main.go", "lib/core/local_policy.sh"):
            self.assertTrue(packaging.selected_source(name), name)
        for name in ("bin/analyze-go", "bin/status-darwin-arm64", ".env", "AGENTS.local.md", "dist/example"):
            self.assertFalse(packaging.selected_source(name), name)
        for name in ("../private", "/etc/passwd", "docs/line\nbreak"):
            with self.assertRaises(ValueError):
                packaging.selected_source(name)

    def test_snapshot_rejects_symlink_to_external_file(self):
        with tempfile.TemporaryDirectory() as fixture:
            root = Path(fixture) / "repo"
            root.mkdir()
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            secret = Path(fixture) / "outside"
            secret.write_text("must not enter archive")
            (root / "mole").symlink_to(secret)
            snapshot = Path(fixture) / "snapshot"
            snapshot.mkdir()
            with self.assertRaisesRegex(ValueError, "symlink refused"):
                packaging.copy_source(root, snapshot)
            self.assertFalse((snapshot / "mole").exists())

    def test_checksum_detects_modified_and_missing_payload(self):
        with tempfile.TemporaryDirectory() as fixture:
            root = Path(fixture)
            payload = root / "tool"
            payload.write_text("reviewed content")
            packaging.write_checksums(root)
            command = ["/usr/bin/shasum", "-a", "256", "-c", "CHECKSUMS.sha256"]
            self.assertEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)
            payload.write_text("changed content")
            self.assertNotEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)
            payload.unlink()
            self.assertNotEqual(subprocess.run(command, cwd=root, capture_output=True).returncode, 0)

    def test_archive_is_stable_and_keeps_executable_mode(self):
        with tempfile.TemporaryDirectory() as fixture:
            root = Path(fixture) / "package"
            root.mkdir()
            binary = root / "mole"
            binary.write_text("fixture")
            binary.chmod(0o755)
            first, second = Path(fixture) / "a.tar.gz", Path(fixture) / "b.tar.gz"
            packaging.archive_tree(root, first)
            os.utime(binary, (200, 200))
            packaging.archive_tree(root, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with tarfile.open(first) as archive:
                self.assertEqual(archive.getmember("package/mole").mode, 0o755)
                self.assertEqual(archive.getmember("package/mole").uid, 0)

    def test_builder_clears_ambient_fetch_and_build_configuration(self):
        previous = os.environ.get("GOFLAGS")
        try:
            os.environ["GOFLAGS"] = "-mod=mod"
            env = packaging.build_environment("amd64")
            self.assertEqual(env["GOFLAGS"], "")
            for name in ("GOPROXY", "GOSUMDB", "GOTELEMETRY", "GOENV", "GOWORK"):
                self.assertEqual(env[name], "off", name)
            self.assertEqual(env["GOTOOLCHAIN"], "local")
            self.assertEqual(env["GOARCH"], "amd64")
        finally:
            if previous is None:
                os.environ.pop("GOFLAGS", None)
            else:
                os.environ["GOFLAGS"] = previous


if __name__ == "__main__":
    unittest.main()
