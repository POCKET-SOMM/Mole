# Mole local maintenance fork

A conservative, offline maintenance fork of [Mole by Tw93 and contributors](https://github.com/tw93/Mole), based on version 1.54.0. This repository is `POCKET-SOMM/Mole`.

Read [the local behavior and build guide](docs/LOCAL_HARDENING.md) before using it. This fork has no published releases, automatic updater, or configured distribution channel. The upstream Homebrew package and upstream release assets do not contain these changes.

## What it does

- Inspect local disk usage, storage inventories and potential duplicate files.
- Preview two supported compiler-cache families and require explicit selection before cleanup.
- Preserve browser state, app interiors, models, downloaded dependencies and active project state during automatic maintenance.
- Retain deliberate app uninstall and Trash actions with their existing safeguards.
- Keep operation history local and disable automatic update downloads.

## Build and review

Mole's upstream minimum is macOS 12 or newer. The actual minimum for a locally built helper also depends on the Go toolchain used. Intel and Apple Silicon source builds are supported; GitHub checks are configured for macOS 14 and the current hosted runner; the first hosted run remains pending.

Prepare the Go version and modules specified by `go.mod` on a connected development machine. Tool and module preparation uses the internet; runtime and `make build` do not download dependencies.

```sh
make build
./mole --help
./mole clean --dry-run
./mole analyze --json ~/Developer
```

The source installer builds from this checkout. Review its options and destination before installing. `mo update` provides local build guidance and does not replace the installation.

## Team release preparation

The first candidate is a portable terminal package for Apple Silicon and Intel,
with compiled helpers and corresponding source. It requires no Go or network
access to run. It is not a graphical Mac app. See the [release plan](docs/RELEASE_PLAN.md)
and [team quickstart](docs/TEAM_QUICKSTART.md) for compatibility and outstanding gates.

With the declared Go 1.27.1 toolchain and pinned modules already prepared:

```sh
make package-candidate OUTPUT=/absolute/path/to/a/new/candidate-directory
bash scripts/check_release_package.sh /absolute/path/to/a/new/candidate-directory
```

Both commands enforce the test filesystem sandbox; the artifact verifier also
denies outbound IP connections. The builder preserves previous output directories,
records dirty source snapshots honestly, and never tags or publishes. Checksum
verification, native integration, signing and review are required before rollout.

## Verification and CI

```sh
./scripts/check.sh --format
bash scripts/check_test_sandbox.sh
TERM=xterm-256color MOLE_TEST_NO_AUTH=1 MOLE_SKIP_FINDER_TESTS=1 ./scripts/test.sh
bash scripts/check_local_offline.sh
```

The test runner applies a macOS sandbox before executing repository code. Installed apps and real profiles are read-only; temporary files and this checkout remain writable. Run individual Bats or Go commands through `bash scripts/test_sandbox.sh ...`. A fake HOME and `MOLE_TEST_NO_AUTH=1` alone do not provide filesystem isolation. See [the test incident record](docs/TEST_ISOLATION_INCIDENT.md).

[CI policy](docs/FORK_CI.md) keeps read-only checks with pinned actions and no stored checkout credentials. Inherited release publishing, scheduled account automation and upstream maintainer assignments are removed. Creating a fork does not prevent using CI or publishing future releases under the fork's own identity.

## License and attribution

Mole is open source under [GPL-3.0](LICENSE). Original copyright and attribution are retained. This fork is independent of the upstream project and the separately distributed Mole Mac app. Historical upstream review notes and fixtures may still refer to upstream releases; they are not installation or publication instructions for this fork.
