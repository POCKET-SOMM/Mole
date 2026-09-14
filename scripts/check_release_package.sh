#!/bin/bash
# Verify extracted candidate archives behind filesystem and network boundaries.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEST_TEMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
case "$TEST_TEMP_ROOT" in
    /private/tmp | /private/var/folders/*/T) ;;
    *)
        echo 'Unexpected test temporary root; use a disposable macOS runner.' >&2
        exit 1
        ;;
esac
profile="$(cat "$SCRIPT_DIR/test_sandbox.sb")
(deny network-outbound (remote ip \"*:*\"))"
exec /usr/bin/sandbox-exec -D "PROJECT=$PROJECT_ROOT" -D "TEMPROOT=$TEST_TEMP_ROOT" \
    -p "$profile" /usr/bin/python3 -I "$SCRIPT_DIR/check_release_package.py" "$@"
