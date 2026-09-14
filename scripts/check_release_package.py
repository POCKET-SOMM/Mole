#!/usr/bin/env python3
"""Artifact smoke checks; invoke via check_release_package.sh for OS isolation."""

import errno
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import subprocess
import argparse
import tarfile
import tempfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checksum(path):
    with path.open("rb") as source:
        return hashlib.sha256(source.read()).hexdigest()


def extract(archive_path, destination):
    # The verifier never follows archive links or writes outside its fixture.
    with tarfile.open(archive_path) as archive:
        members = archive.getmembers()
        require(len(members) < 10000, "archive member limit")
        require(sum(member.size for member in members) < 256 * 1024 * 1024, "archive size limit")
        seen = set()
        for member in members:
            name = Path(member.name)
            require(not name.is_absolute() and ".." not in name.parts, "unsafe archive path")
            require(member.isfile() or member.isdir(), "archive links or special files refused")
            require(member.name not in seen, "duplicate archive path")
            require(not member.mode & 0o7000, "special permission bits refused")
            seen.add(member.name)
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)
                target.chmod(member.mode & 0o777)
    roots = list(destination.iterdir())
    require(len(roots) == 1 and roots[0].is_dir(), "expected one package root")
    return roots[0]


def execute(package, env, *args):
    result = subprocess.run(
        [str(package / "mo-team"), *args], cwd=package, env=env,
        stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
    )
    if result.returncode:
        raise RuntimeError(str(args) + ": " + result.stderr + result.stdout)
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", type=Path)
    artifacts = parser.parse_args().artifacts.resolve()
    require((artifacts / "BUILD_COMPLETE").is_file(), "incomplete build")
    with socket.socket() as probe:
        probe.settimeout(1)
        require(probe.connect_ex(("127.0.0.1", 9)) in (errno.EPERM, errno.EACCES), "network boundary missing")
    subprocess.run(
        ["/usr/bin/shasum", "-a", "256", "-c", "CHECKSUMS.sha256"],
        cwd=artifacts, check=True, timeout=30,
    )
    host_arch = "arm64" if platform.machine() == "arm64" else "amd64"
    source_archives = list(artifacts.glob("*-source.tar.gz"))
    require(len(source_archives) == 1, "expected exactly one source archive")
    with tempfile.TemporaryDirectory(prefix="mole-artifact-check-", dir="/private/tmp") as scratch:
        workspace = Path(scratch)
        source_root = workspace / "source"
        source_root.mkdir()
        source = extract(source_archives[0], source_root)
        source_manifest = json.loads((source / "SOURCE_MANIFEST.json").read_text())
        files = source_manifest["files"]
        require(hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest() == source_manifest["source_manifest_sha256"], "Source manifest fingerprint mismatch; rebuild and inspect the source archive.")
        for name, record in files.items():
            require(checksum(source / name) == record["sha256"], name)
        for architecture in ("arm64", "amd64"):
            archives = list(artifacts.glob("*-darwin-" + architecture + ".tar.gz"))
            require(len(archives) == 1, "expected exactly one runtime per architecture")
            extract_root = workspace / architecture
            extract_root.mkdir()
            package = extract(archives[0], extract_root)
            subprocess.run(["/bin/bash", str(package / "verify.sh")], check=True, timeout=30)
            metadata = json.loads((package / "RELEASE.json").read_text())
            require(metadata["architecture"] == architecture, "Runtime architecture metadata mismatch; inspect RELEASE.json.")
            require(metadata["source_manifest_sha256"] == source_manifest["source_manifest_sha256"], "Runtime and source snapshots differ; rebuild both together.")
            for name in files:
                if name in ("mole", "LICENSE", "TRADEMARK.md", "THIRD_PARTY_NOTICES.txt") or name.startswith(("bin/", "lib/")):
                    require(checksum(package / name) == files[name]["sha256"], "Runtime differs from source: " + name)
            for binary in ("analyze-go", "status-go"):
                machine = subprocess.check_output(["/usr/bin/lipo", "-archs", str(package / "bin" / binary)], text=True).strip()
                require(machine == {"arm64": "arm64", "amd64": "x86_64"}[architecture], machine)
            if architecture != host_arch:
                print(architecture + ": source, checksums and Mach-O architecture verified; native execution pending", flush=True)
                continue
            home = workspace / "home"
            home.mkdir()
            scan = home / "scan"
            scan.mkdir()
            for name in ("one", "two"):
                (scan / name).write_text("identical local fixture")
            env = os.environ.copy()
            env.update({"HOME": str(home), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "xterm-256color", "MOLE_TEST_NO_AUTH": "1", "MOLE_SKIP_FINDER_TESTS": "1"})
            require(shutil.which("go", path=env["PATH"]) is None, "runtime test must not have Go")
            require(metadata["version"] in execute(package, env, "--version"), "Runtime version differs from RELEASE.json; rebuild the package.")
            execute(package, env, "--help")
            execute(package, env, "update")
            execute(package, env, "clean", "--dry-run")
            execute(package, env, "optimize", "--dry-run")
            require("portable Mole package" in execute(package, env, "remove"), "Portable removal guidance is missing; inspect the package marker and remove dispatcher.")
            for args in (("--json",), ("--inventory",), ("--duplicates",)):
                json.loads(execute(package, env, "analyze", *args, str(scan)))
            status = subprocess.run(
                [str(package / "mo-team"), "status", "--json"], cwd=package,
                env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=60,
            )
            json.loads(status.stdout)
            if status.returncode:
                require(status.returncode == 1 and "incomplete metrics:" in status.stderr
                        and "ps: operation not permitted" in status.stderr, status.stderr)
                print("Status returned valid partial JSON; native process collection remains unverified.", flush=True)
            require(all((scan / name).is_file() for name in ("one", "two")), "Read-only checks removed a fixture; inspect runtime behavior before sharing.")
            subprocess.run(["/bin/bash", str(package / "verify.sh")], check=True, timeout=30)
            print(architecture + ": extracted runtime passed offline previews, version, removal guidance and analyzer JSON without Go", flush=True)
    print("Artifact smoke checks passed. Native integration, signing and publication are separate gates.", flush=True)


if __name__ == "__main__":
    main()
