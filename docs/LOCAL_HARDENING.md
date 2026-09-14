# Local maintenance fork

This checkout implements a conservative fork of Mole 1.54.0, based on
`2a56747424fc9bb8440c45e5104695993d02337b`. It deliberately supports fewer
automatic maintenance operations. Installing the original upstream package
does not include these changes.

## Behavior

| Command | Local fork behavior |
|---|---|
| Bare menu, help, version | Local display; no scheduled version check or cached upstream update offer. |
| `mo update` | Guidance only, including force/nightly options. No download or replacement. The standalone installer's update action behaves the same way. |
| `mo clean` | Review only validated PyInstaller binary caches and Clang module caches. Select exact numbered items, then type `delete`. No administrator access. |
| `mo clean --dry-run`, piped `mo clean` | Preview only. No target mutation or saved approval file. |
| `mo clean --external PATH` | Inspection guidance; automatic external-volume cleanup is unavailable. |
| `mo optimize` | Select one bounded disk verification or the two documented Finder `.DS_Store` preferences, then type `apply`. No automatic task catalog execution. |
| `mo optimize --dry-run`, piped `mo optimize` | Preview only. No preference, database, service, or system change. |
| `mo purge` | Existing selected-action workflow with mandatory exclusions for downloaded dependencies, environments, toolchains, app contents, models, the invoking project, and PATH command targets. Cloud and nonlocal roots are refused. |
| `mo installer` | Existing installer selection and identity checks, with local scan roots and final PATH-command protection. |
| `mo uninstall` | Existing deliberate app selection and exact bundle/sibling safeguards. Homebrew casks are kept because hooks lack a complete mutation plan. No package autoremove or post-uninstall Dock/LaunchServices rebuild. Incomplete batches return nonzero. |
| `mo analyze` | Local disk inspection and existing deliberate Trash actions. Installed app contents, Git internals, cloud locations, active environments, invoking projects and executable PATH targets are protected. A cache name or old access timestamp never means safe to delete. |
| `mo status` | Local metrics. If collection is incomplete, JSON preserves available metrics, reports the error on stderr and exits nonzero. |
| `mo history`, completion, Touch ID, self-removal | Existing local behavior. Configuration and removal commands still require their own explicit invocation and existing previews/confirmations. |

Broad app/browser cache sweeps, old app versions, session and credential stores,
models, downloaded dependencies, virtual environments, active toolchain state,
swap, system update staging and automatic Trash emptying are outside `clean`.
An empty or custom whitelist cannot expand that policy. Ad hoc Trash removal
and whole-app uninstall remain deliberate actions with their own safeguards.

Both supported compiler caches already existed upstream. Their existing owner
and process checks remain in place. Collection records exact paths, parent and
target identities, ownership evidence and size estimates in memory. Application
uses only selected records and repeats the guards at the deletion boundary.
Later discoveries are not added. Changed identity, a running owner or an
inconclusive probe keeps the item. Cancellation stops subsequent actions.
Compiler-cache deletion is permanent and is labeled before selection.

The Finder task writes `DSDontWriteNetworkStores=true` and
`DSDontWriteUSBStores=true` in the current user's `com.apple.desktopservices`
domain. This is a persistent preference, not cache cleanup. The disk task
verifies; it does not repair. Other optimize handlers remain in the source for
upstream regression coverage but are not offered by the command.

## Privacy and offline operation

The inspected upstream runtime had no first-party telemetry uploader. This
patch removes automatic update traffic and imposes process-local offline and
no-analytics defaults for child tools; it does not change the user's global
tool settings. Ordinary commands never install missing tools or Go helpers.
Unsupported owner mutations, including cask hooks, remain unavailable.

Operation history, debug logs and scan metadata stay local in Mole's existing
configuration/cache/log directories. They can contain filenames and app names.
They are not uploaded. macOS security history is preserved.

This policy covers Mole and the processes it starts. It is not a firewall for
other applications or macOS services. An executable provided through PATH or a
modified local dependency is still part of the machine's trust boundary.

## Storage inspection

```sh
mo analyze --inventory
mo analyze --inventory ~/Developer
mo analyze --duplicates ~/.lmstudio/models
```

`--inventory` starts with known local roots: package/model stores, application
storage, developer directories, Downloads, Trash, installed applications,
Python frameworks, Homebrew/Unix installations, Shared and VM storage. Darwin
temp/cache roots come from `getconf`. Explicit cache/environment variables add
configured roots. Arbitrary tool hooks are not executed to discover paths;
inspect other custom locations by giving their path explicitly.

An explicit inventory lists one level of children and measures each within a
budget. Rows include location, allocated-byte estimate, modification date,
retention explanation and completeness/error information. The overall budget
is 30 seconds, with 3 seconds per inventory bucket and 100,000 entries per
walk. Large roots may require narrower explicit scans. The analyzer's existing
interactive navigation remains available for exploration.
Walk and hash deadlines are checked between filesystem operations; an individual
blocked kernel/filesystem call is not preempted by a Go context deadline.

Two completed, consecutive, comparable inventory scans can report growth.
Roots, identities, schema and row sets must agree. One bounded local metadata
baseline is stored in the analyzer cache with an exclusive publication lock;
partial or older scans cannot replace newer completed measurements. It is
never used to authorize deletion. Inspecting a different scope replaces the
comparison baseline. Directory mtime is not a size cache or evidence of use.

`--duplicates` requires an explicit directory. It first groups same-size files,
then compares SHA-256 content hashes with a shared 30-second and 8-GiB read
budget. It rechecks file identity, size and modification time and refuses
placeholders before reading content. Hardlink aliases are not counted as
independent copies. Results are candidates only; no deduplication is offered.
GGUF and MLX variants are not duplicates because they share a model name.

Cloud-managed storage, dataless placeholders, network filesystems, directory
symlinks and protected CoreSimulator Volumes/Cryptex trees are excluded.
Missing references, old modification/commit dates and old access metadata do
not establish disuse. Worktree and Git pack removal is never recommended from
those signals.

All sizes are estimates. APFS clones, hardlinks, snapshots and concurrent
activity prevent exact attribution of freed space. Cleanup samples available
capacity on the target filesystem before and after application and labels the
observed change separately. Shared APFS capacity readings are never summed.
The startup Data volume is used for ordinary user-space capacity. A Trash move
on the same filesystem usually does not immediately release space. Existing
snapshot reporting remains informational.

The two new inspection flags require explicit invocation because full inventory
and content hashing are too expensive to run automatically on every TUI start.
Existing JSON keys are retained; `cleanable` is now false because names cannot
establish safety. New inventory JSON is a separate versioned format.

## Build and verification

Runtime needs the bundled Go helpers, not an installed Go compiler. A local
source build or source installation needs a supported Go toolchain and the
pinned modules prepared beforehand. `make build` uses `GOTOOLCHAIN=local`,
`GOPROXY=off`, `GOSUMDB=off` and `-mod=readonly`; missing dependencies fail rather
than download. The local installer rebuilds helpers from this source, avoiding
a stale or upstream binary paired with the hardened shell. It refuses remote
source fallback and never removes a stale Homebrew installation automatically.
Existing checksum/attestation mismatch refusal code is preserved.

```sh
make build
MOLE_TEST_NO_AUTH=1 MOLE_SKIP_FINDER_TESTS=1 ./scripts/test.sh
MOLE_TEST_NO_AUTH=1 MOLE_SKIP_FINDER_TESTS=1 bash scripts/test_sandbox.sh go test ./...
bash scripts/check_local_offline.sh
```

The runner now enforces a macOS filesystem sandbox as well as a disposable HOME.
A legacy browser test previously escaped HOME isolation; see
[the incident record](TEST_ISOLATION_INCIDENT.md). Use the sandbox wrapper for
individual Bats or Go tests too.

The offline smoke script uses the same write boundary, a temporary HOME, cold/warm state, a localhost
positive control and macOS outbound-IP denial. It exercises help, version,
update, maintenance previews, analysis, inventory, duplicate inspection and
status, followed by an actual selected compiler-cache deletion in a temporary
fixture. It also records unexpected network-tool invocation. On this Mac,
macOS refuses `/bin/ps` even under an allow-all sandbox, so the status check
verifies honest partial JSON and a nonzero result for that restriction.
This is bounded runtime coverage, not proof about every possible installed
third-party executable. Native Finder/Trash authorization tests require a
separate integration run and remain disabled during automated verification.

The regression fixtures also exercise actual selected cache application,
replacement races, process changes, cancellation, custom whitelists, cask
refusal, PATH symlinks and cached-sudo scope. Legacy updater fixtures explicitly
expose the archived implementation only inside mocked installations so its
verification failures continue to be tested. Production update routing is
tested separately and cannot invoke it.

No distribution channel is configured for this fork. Installation on the Mac,
publication and any real cleanup are separate decisions.
