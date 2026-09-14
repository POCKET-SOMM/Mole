#!/usr/bin/env python3
"""Build local, portable release candidates; never tag, download, or publish."""

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile


ROOT = Path(__file__).resolve().parent.parent
TOOLCHAIN = "go1.27.1"
MINIMUM_MACOS = "14.0"
SOURCE_ROOTS = {"bin", "lib", "cmd", "internal", "scripts", "tests", "docs"}
SOURCE_FILES = {
    "mole", "mo", "install.sh", "Makefile", "go.mod", "go.sum", "LICENSE",
    "README.md", "CONTRIBUTING.md", "SECURITY.md", "SECURITY_AUDIT.md",
    "TRADEMARK.md", "AGENTS.md", ".shellcheckrc", ".gitleaks.toml", ".gitignore",
}


def run(args, **kwargs):
    return subprocess.run(args, check=True, timeout=600, **kwargs)


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def selected_source(name):
    path = Path(name)
    if path.is_absolute() or ".." in path.parts or any(ord(c) < 32 for c in name):
        raise ValueError("Unsafe source path: " + repr(name))
    if name in SOURCE_FILES:
        return True
    if path.parts[0] not in SOURCE_ROOTS:
        return False
    # Compiled helpers are always freshly built from the snapshot.
    return path.parts[0] != "bin" or path.suffix == ".sh"


def copy_source(root, snapshot):
    inventory = run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=root, stdout=subprocess.PIPE,
    ).stdout.decode().split("\0")
    for name in sorted(set(filter(None, inventory))):
        if not selected_source(name):
            continue
        source = root / name
        if not source.exists() and not source.is_symlink():
            continue  # A tracked deletion is absent from this candidate.
        for component in [source, *source.parents]:
            if component == root:
                break
            if component.is_symlink():
                raise ValueError("Source symlink refused; inspect " + name)
        if not source.is_file():
            raise ValueError("Source is not a regular file: " + name)
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o755 if source.stat().st_mode & 0o111 else 0o644)
    # Required inputs prevent an incomplete inventory from becoming a package.
    for name in ("mole", "go.mod", "go.sum", "LICENSE", "scripts/check_release_minos.sh"):
        if not (snapshot / name).is_file():
            raise ValueError("Missing required source: " + name)


def file_manifest(root):
    return {
        path.relative_to(root).as_posix(): {
            "sha256": digest(path), "mode": oct(stat.S_IMODE(path.stat().st_mode)),
        }
        for path in sorted(root.rglob("*")) if path.is_file()
    }


def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def write_checksums(root, name="CHECKSUMS.sha256"):
    lines = [
        digest(path) + "  " + path.relative_to(root).as_posix() + "\n"
        for path in sorted(root.rglob("*"))
        if path.is_file() and path != root / name
    ]
    (root / name).write_text("".join(lines))


def archive_tree(root, target):
    # Stable file ordering, ownership and times, with no host extended attributes.
    with target.open("xb") as output:
        with gzip.GzipFile(fileobj=output, mode="wb", filename="", mtime=0) as zipped:
            with tarfile.open(fileobj=zipped, mode="w|") as archive:
                for path in [root, *sorted(root.rglob("*"))]:
                    info = archive.gettarinfo(str(path), arcname=str(path.relative_to(root.parent)))
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    info.mode = 0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644
                    if info.isfile():
                        with path.open("rb") as content:
                            archive.addfile(info, content)
                    else:
                        archive.addfile(info)


def build_environment(architecture):
    env = os.environ.copy()
    env.update({
        "GOTOOLCHAIN": "local", "GOPROXY": "off", "GOSUMDB": "off",
        "GOTELEMETRY": "off", "GOENV": "off", "GOWORK": "off", "GOFLAGS": "",
        "CGO_ENABLED": "0", "GOOS": "darwin", "GOARCH": architecture,
        "GOAMD64": "v1", "GOARM64": "v8.0", "GOEXPERIMENT": "",
    })
    return env


def prepare_dependencies(source, go):
    env = build_environment("arm64")
    run([go, "mod", "vendor"], cwd=source, env=env)
    goroot = Path(run([go, "env", "GOROOT"], cwd=source, env=env,
                      stdout=subprocess.PIPE, text=True).stdout.strip())
    notices = ["Go runtime and standard library\n\n" + (goroot / "LICENSE").read_text()]
    for path in sorted((source / "vendor").rglob("*")):
        if path.is_file() and path.name.upper().startswith(("LICENSE", "COPYING", "NOTICE", "COPYRIGHT")):
            notices.append(path.relative_to(source).as_posix() + "\n\n" + path.read_text(errors="replace"))
    (source / "THIRD_PARTY_NOTICES.txt").write_text("\n\n".join(notices) + "\n")


def package_runtime(source, package, architecture, metadata, go):
    package.mkdir()
    for name in ("mole", "LICENSE", "TRADEMARK.md", "THIRD_PARTY_NOTICES.txt"):
        shutil.copy2(source / name, package / name)
    for name in ("bin", "lib"):
        shutil.copytree(source / name, package / name)
    for command in ("analyze", "status"):
        run([
            go, "build", "-trimpath", "-buildvcs=false", "-mod=vendor",
            "-ldflags=-s -w", "-o", str(package / "bin" / (command + "-go")),
            "./cmd/" + command,
        ], cwd=source, env=build_environment(architecture))
    binaries = [package / "bin" / (name + "-go") for name in ("analyze", "status")]
    inspection = run([
        "/bin/bash", str(source / "scripts/check_release_minos.sh"),
        "--max", MINIMUM_MACOS, *map(str, binaries),
    ], stdout=subprocess.PIPE, text=True).stdout
    print(inspection, end="", flush=True)
    write_json(package / "RELEASE.json", {
        **metadata, "architecture": architecture, "minimum_macos_target": MINIMUM_MACOS,
        "minimum_os_inspection": inspection.replace(str(package) + "/", ""),
        "developer_id_signed": False, "notarized": False, "attestation": None,
    })
    (package / "PORTABLE").write_text("Portable local maintenance fork. Removal is manual.\n")
    shutil.copy2(source / "docs/TEAM_QUICKSTART.md", package / "README.md")
    shutil.copy2(source / "docs/LOCAL_HARDENING.md", package / "BEHAVIOR.md")
    shutil.copy2(source / "docs/TEST_ISOLATION_INCIDENT.md", package / "TEST_ISOLATION_INCIDENT.md")
    (package / "mo-team").write_text(
        '#!/bin/bash\nset -euo pipefail\n'
        'PACKAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\n'
        'exec "$PACKAGE_DIR/mole" "$@"\n'
    )
    (package / "verify.sh").write_text(
        '#!/bin/bash\nset -euo pipefail\n'
        'cd "$(dirname "${BASH_SOURCE[0]}")"\n'
        '/usr/bin/shasum -a 256 -c CHECKSUMS.sha256 > /dev/null\n'
        'printf "%s\\n" "Package checksums verified."\n'
    )
    for name in ("mo-team", "verify.sh"):
        (package / name).chmod(0o755)
    write_checksums(package)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory for candidate artifacts")
    args = parser.parse_args()
    output = args.output.absolute()
    if output.exists() or output.is_symlink():
        parser.error("Output already exists; choose a new directory to preserve previous artifacts.")
    go = shutil.which("go")
    if go is None:
        parser.error("Prepare Go " + TOOLCHAIN + " and pinned modules before packaging.")
    compiler = run([go, "version"], env=build_environment("arm64"), stdout=subprocess.PIPE, text=True).stdout.strip()
    if compiler.split()[2:3] != [TOOLCHAIN]:
        parser.error("Expected " + TOOLCHAIN + "; found " + compiler + ". Prepare the declared toolchain.")
    commit = run(["git", "rev-parse", "HEAD"], cwd=ROOT, stdout=subprocess.PIPE, text=True).stdout.strip()
    dirty = bool(run(
        ["git", "status", "--porcelain", "--untracked-files=normal"],
        cwd=ROOT, stdout=subprocess.PIPE,
    ).stdout)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.mkdir()  # Exclusive creation: an existing candidate is never replaced.
    # A failed build leaves no CHECKSUMS.sha256 or BUILD_COMPLETE receipt.
    with tempfile.TemporaryDirectory(prefix="mole-package-") as scratch:
        source = Path(scratch) / "source"
        source.mkdir()
        copy_source(ROOT, source)
        versions = re.findall(r'^VERSION="([0-9][0-9A-Za-z.+-]*)"$', (source / "mole").read_text(), re.M)
        if len(versions) != 1:
            raise ValueError("Expected exactly one source VERSION; inspect mole before packaging.")
        version = versions[0]
        source = source.rename(source.with_name("mole-team-" + version + "-source"))
        prepare_dependencies(source, go)
        manifest = file_manifest(source)
        source_hash = hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()
        metadata = {
            "repository": "POCKET-SOMM/Mole", "version": version,
            "baseline_commit": commit, "working_tree_dirty": dirty,
            "source_manifest_sha256": source_hash, "compiler": compiler,
            "status": "candidate-unverified", "build_flags": ["-trimpath", "-buildvcs=false", "-mod=vendor", "-ldflags=-s -w"],
        }
        write_json(source / "SOURCE_MANIFEST.json", {**metadata, "files": manifest})
        archive_tree(source, output / (source.name + ".tar.gz"))
        for architecture in ("arm64", "amd64"):
            package = Path(scratch) / ("mole-team-" + version + "-darwin-" + architecture)
            package_runtime(source, package, architecture, metadata, go)
            archive_tree(package, output / (package.name + ".tar.gz"))
        write_json(output / "BUILD.json", metadata)
    write_checksums(output)
    (output / "BUILD_COMPLETE").write_text("Built candidate artifacts only; release verification remains required.\n")
    print("Candidate artifacts: " + str(output), flush=True)


if __name__ == "__main__":
    main()
