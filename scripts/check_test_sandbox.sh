#!/bin/bash
# Exercise the OS boundary against self-created canaries, never real app files.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fixture="$(mktemp -d "$PROJECT_ROOT/tests/tmp-sandbox-check.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT # SAFE: exact mktemp-created canary directory
mkdir "$fixture/allowed"
printf 'keep\n' > "$fixture/canary"
TEST_TEMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
/usr/bin/sandbox-exec -D "PROJECT=$fixture/allowed" -D "TEMPROOT=$TEST_TEMP_ROOT" \
    -f "$SCRIPT_DIR/test_sandbox.sb" /usr/bin/python3 - "$fixture" << 'PY'
import os
import pathlib
import sys

fixture = pathlib.Path(sys.argv[1])
(fixture / 'allowed' / 'positive-control').write_text('allowed')
for operation in ('overwrite', 'unlink'):
    try:
        if operation == 'overwrite':
            (fixture / 'canary').write_text('damaged')
        else:
            os.unlink(fixture / 'canary')
    except PermissionError:
        continue
    raise SystemExit('Sandbox failed to deny ' + operation)
escape = fixture / 'allowed' / 'escape'
escape.symlink_to(fixture / 'canary')
try:
    escape.write_text('damaged through symlink')
except PermissionError:
    pass
else:
    raise SystemExit('Sandbox failed to deny a symlink escape')
assert (fixture / 'canary').read_text() == 'keep\n'
print('Sandbox allowed fixture writes and denied overwrite, deletion and symlink escape.')
PY
