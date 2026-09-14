# Test isolation incident, 13 September 2026

An inherited test run during the local hardening work reached the real Google Chrome installation. The operator later reported crashes when opening new windows; restarting Chrome resolved them. This is separate from the earlier, unexplained Chrome language change.

## Evidence and mechanism

The recorded failing test was `clean_browsers never enters Firefox cleanup while Firefox is running` in `tests/clean_user_core.bats`. Its output in `/private/tmp/mole-hardening-tools/full-tests2.log`, around lines 775–807, includes:

```text
Chrome old versions · 2 dirs, 1.47GB
/bin/bash: line 594: files_cleaned: unbound variable
```

The test replaced HOME and mocked `pgrep` as running for Firefox only. The Chrome wrapper retained its hardcoded `/Applications/Google Chrome.app` fallback. Only `safe_clean` was mocked; old-version pruning calls `safe_remove` directly. The helper counts successful removals before printing the above line, then failed on an unset accounting variable. `MOLE_TEST_NO_AUTH=1` blocks authorization prompts, not unprivileged file deletion.

The real Chrome framework Versions directory had a modification timestamp of 15:09:32 CEST that day, consistent with the test work, and contained only version `152.0.7977.83` and its Current symlink when inspected. The deletion likely explains the later new-window crashes, but no crash report confirmed the precise failure mechanism. The exact removed version numbers were not recovered. The code path identifies app framework directories; no Chrome profile deletion was found in that path.

The earlier implementation report incorrectly stated that all cleanup used fixtures. That report has been corrected. A passing suite did not demonstrate host isolation. No Chrome repair, profile reset or reinstall was performed during investigation; the user restarted Chrome themselves.

## Corrective changes

- Chrome, Edge and Brave old-version wrappers return without discovering installed apps in either test mode unless explicit app fixture paths are supplied.
- The broad browser test file explicitly points all three browsers at its fake HOME.
- A regression records dispatch instead of deleting anything. It demonstrates that all three original wrappers reached real app fallback paths, the corrected wrappers refuse absent overrides, and explicit fixtures still reach the helper.
- `scripts/test.sh` enters the macOS sandbox before sourcing repository code and gives runner-level code a disposable HOME. Individual checks use `scripts/test_sandbox.sh`.
- The sandbox denies writes outside this checkout and temporary roots, restricts signals to the sandbox, and blocks native app-control executables. A canary check proves allowed fixture writes and denied overwrite/deletion outside the permitted workspace.
- Uninstall unit tests also replace system app-discovery roots with fixture roots; the earlier sandboxed run exposed those remaining host reads.
- Idle-process tests use explicit process-table fixtures. Native checks unavailable under the sandbox remain visibly skipped; they must not be made green by dropping isolation. This includes three Go process-list checks, two Bats installer-lock integrations and the standalone fixture-installation smoke. Status JSON tests verify the exact partial-result refusal instead of treating it as success.
- The offline harness uses the same filesystem boundary plus outbound-IP denial.

The sandbox is an additional test boundary, not a malware containment guarantee. Tests can mutate the checkout and temporary roots. Legacy test mode alone remains insufficient for arbitrary directly sourced cleanup code. Do not execute the unsandboxed legacy suite on a personal Mac.
