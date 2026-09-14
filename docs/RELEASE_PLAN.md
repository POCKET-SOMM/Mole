# First team release candidate

The proposed first release is `1.54.0-team.1-rc.1` of `POCKET-SOMM/Mole`.
It packages the existing terminal application. It does not contain the separately
distributed Mole Mac app or a new graphical interface.

## Artifacts and source

- Portable archives for macOS arm64 (Apple Silicon) and amd64 (Intel).
- Shell entrypoint and libraries bundled with helpers compiled from the same
  source snapshot, with no build, installation, or network dependency at runtime.
- Corresponding source archive with vendored Go dependencies, original and third-party license notices, source-file
  hashes, build metadata, per-package file checksums, and archive SHA-256 checksums.
- Manual download and folder replacement for updates; keep the previous folder
  for rollback. No background component, automatic updater, or PATH modification.

The package builder snapshots only the declared source roots from Git's tracked
and nonignored file inventory. It excludes generated binaries and rejects
symlinks and unexpected file types in the selected source. Review the source
manifest before sharing. A dirty source tree is recorded as a candidate snapshot,
never represented as the contents of its baseline commit.

Vendoring uses only the already prepared module cache and fails if dependencies
are unavailable. Helpers build with `-mod=vendor`, `-trimpath`, `-buildvcs=false`
and `-ldflags='-s -w'`. The source archive includes that vendor tree and
`SOURCE_MANIFEST.json`. With Go 1.27.1 prepared, the source archive can rebuild
each helper offline, for example:

```sh
GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
  go build -mod=vendor -trimpath -buildvcs=false -ldflags='-s -w' -o bin/analyze-go ./cmd/analyze
```

Use the sandbox wrapper around manual build verification. Repeat for `./cmd/status`
and the desired architecture. Go itself is a separate build prerequisite; users
of the runtime archive do not need it.

The initial compatibility target is macOS 14 and newer. The prepared build
toolchain is Go 1.27.1. Build metadata records the actual compiler and each binary's
Mach-O minimum OS; minimum-OS inspection is a build gate, not native compatibility
certification. Both architectures still need native integration on disposable Macs.

## Verification before publishing

1. Review and commit the final source, then rebuild from that clean commit.
2. Pass the complete sandboxed fixture suite and static checks on that source.
3. Verify actual extracted archives without Go or network access: hashes, version,
   help, maintenance previews, analyzer JSON, and retained fixture files.
4. On disposable macOS runners, verify native process collection, Finder/Trash,
   authorization and installation/removal behavior. Never bypass the test sandbox
   on a personal Mac to turn a skipped native test into a pass.
5. Decide signing and notarization before broad distribution. Current candidate
   archives have no Developer ID signature, notarization, or build attestation.
   SHA-256 detects changes against a trusted manifest; it does not authenticate an
   unauthenticated download. Do not advise bypassing Gatekeeper or clearing quarantine.
6. Verify hosted CI on the exact committed source. Publish only after these gates
   and review of the concrete artifacts and release notes.

## Distribution decision

The existing fork is public. A release there will be public. Restricted team
downloads require a separate private repository or internal artifact store.
No publisher is configured, and preparing these artifacts does not upload,
tag, push, or publish anything. Keep manual updates for this pilot.

## Portable behavior

Run the entrypoint inside the extracted folder. No global `mo` command is installed.
The packaged `remove` command only explains how to move that folder to Trash; it
does not search for another Mole installation or delete shared configuration.
Existing local history, configuration and cache locations are retained and may
be shared with an existing Mole installation. Automatic shell-completion setup
is not part of the portable installation procedure.
