#!/bin/bash
# Run verification with installed apps and real user state read-only.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
[[ $# -gt 0 ]] || {
    echo 'Usage: scripts/test_sandbox.sh command [args...]' >&2
    exit 2
}
if [[ ! -x /usr/bin/sandbox-exec ]]; then
    echo 'Test isolation requires macOS sandbox-exec; use a disposable macOS runner.' >&2
    exit 1
fi
TEST_TEMP_ROOT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
case "$TEST_TEMP_ROOT" in
    /private/tmp | /private/var/folders/*/T) ;;
    *)
        echo "Refusing unexpected test temporary root: $TEST_TEMP_ROOT" >&2
        exit 1
        ;;
esac
exec /usr/bin/sandbox-exec -D "PROJECT=$PROJECT_ROOT" -D "TEMPROOT=$TEST_TEMP_ROOT" \
    -f "$SCRIPT_DIR/test_sandbox.sb" "$@"
