---
name: release-flow
description: "Assess distribution readiness for this local Mole fork. No publishing channel is configured."
---

# Fork distribution policy

No distribution channel is configured for `POCKET-SOMM/Mole`. The inherited tag publisher, Homebrew submission job, scheduled account automation and automatic upstream updater are disabled or removed. A tag or push to main does not publish a fork release or nightly build.

For release assessment, read `docs/FORK_CI.md` and `docs/LOCAL_HARDENING.md`. Inspect the exact fork remote and current GitHub state. Do not reuse `tw93/Mole`, upstream maintainer tokens, Homebrew destinations, app marketing, or upstream assets as a release of this fork.

For a future explicitly requested release, first prepare a concrete plan identifying the fork repository, version and source commit, supported macOS/toolchain versions, artifacts, checksums, signing/attestation, installation verification and any update or package channel. Review existing authorization before requesting additional permission. No tag, upload, account message or package submission is implicit in preparing that plan.

Manual `make release-amd64` and `make release-arm64` targets only build local files from prepared dependencies. Run `scripts/check_release_minos.sh` on any artifact proposed for distribution; the declared source minimum does not prove the output's minimum OS. Keep checksum/attestation verification fail-closed. Run verification through the sandboxed runner; see the test isolation incident record.

Release-note drafts belong to `.claude/skills/release-notes/SKILL.md`. Preserve the `.agents/skills` discovery symlinks.
