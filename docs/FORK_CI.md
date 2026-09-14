# Fork CI and distribution

This policy applies to `POCKET-SOMM/Mole`. A fork can run GitHub Actions and later publish its own releases. Upstream credentials, package destinations and release assets do not become this fork's distribution channel.

## Retained checks

Only `check.yml` and `test.yml` remain. They run for pull requests, pushes to main/dev, and manual dispatch. Both declare `contents: read`, use full commit pins for the official checkout/setup-go actions, disable stored checkout credentials, bound job time and cancel superseded checks.

Checks cover formatting, lint, destructive-sink annotations, secrets scanning, builds, fixture tests and exercised offline runtime paths. The core compatibility job builds the Go helpers before using CLI fixtures. Bats verification uses the macOS write-restricted test sandbox. Native checks forbidden by that boundary are explicitly skipped and need a disposable integration runner. Each Bats case has a 120-second limit. Native process-list and installer-lock checks are not certified by a passing sandboxed run.

The YAML policy checker rejects added workflows, permission escalation, tag/scheduled triggers, credential contexts, unpinned/unapproved actions, stored checkout credentials and known publishing commands. Actionlint separately validates workflow semantics. These source checks do not prove arbitrary future shell code harmless; changes still require review.

GitHub runners download verification tools and pinned Go modules during preparation. This is distinct from Mole's offline runtime. Go telemetry and Homebrew analytics are disabled on those disposable runners. Local and cross-build Make targets use prepared dependencies and refuse fetching.

## Removed inherited configuration

- Tag release and Homebrew Core submission workflow.
- Scheduled contributor commits, bundle-audit issue creation and separate scheduled CodeQL workflow.
- Dependabot's scheduled PR configuration, upstream CODEOWNERS assignment and funding account metadata.
- Upstream release-reaction helper and publishing instructions in agent skills.
- README release badges, upstream installation/update commands and unrelated upstream account promotion.

The manual bundle audit, minimum-OS check and checksum/attestation refusal logic remain useful source tools. Manual cross-build targets write local binaries only. No tag, upload, release, package submission or nightly distribution is configured. Original license and attribution remain.

## GitHub state verified on 13 September 2026

The fork had zero GitHub releases, zero tags, zero registered workflows and zero workflow runs when inspected. Nothing needed release deletion. Its Actions default token previously had write access and could approve pull requests. The repository setting was changed and read back as:

```json
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
```

Actions remains enabled for read-only verification. The YAML/source changes are local and uncommitted until reviewed and pushed; no hosted run has validated this candidate. Branch protection and account secrets were not modified. The first hosted run must be checked at the exact pushed commit before treating CI as verified.

See [the local behavior guide](LOCAL_HARDENING.md) and [the test isolation incident](TEST_ISOLATION_INCIDENT.md). A future release needs an explicit fork artifact, signing, installation and update plan.

## Local candidate packaging

`make package-candidate OUTPUT=/absolute/new/directory` builds portable arm64 and
amd64 archives plus corresponding source and checksums using the declared prepared
toolchain. `scripts/check_release_package.sh` verifies the actual archives under
filesystem and outbound-IP restrictions. These are local preparation tools, not a
publishing workflow. See [the first release plan](RELEASE_PLAN.md). Native checks,
signing, a clean source commit and hosted CI remain release gates.

The read-only validation workflow also defines archive build/smoke checks on
`macos-14`, `macos-26` and `macos-15-intel`, using Go 1.27.1. These are current
[GitHub-hosted runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
It executes the matching runtime on each runner, inspects the other architecture,
and does not upload artifacts or publish releases. Hosted execution is still pending.
