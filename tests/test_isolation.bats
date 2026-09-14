#!/usr/bin/env bats

@test "browser version wrappers require explicit fixtures in either test mode" {
    local project
    project="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run env PROJECT_ROOT="$project" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
unset MOLE_CHROME_APP_PATHS MOLE_EDGE_APP_PATHS MOLE_BRAVE_APP_PATHS
# A recording replacement means this regression cannot itself delete anything.
_clean_chromium_old_versions() { printf 'REACHED:%s\n' "$*"; }
for mode in MOLE_TEST_MODE MOLE_TEST_NO_AUTH; do
    export MOLE_TEST_MODE=0 MOLE_TEST_NO_AUTH=0
    export "$mode=1"
    for browser in chrome edge brave; do
        result=$("clean_${browser}_old_versions")
        [[ -z "$result" ]] || { echo "HOST_FALLBACK:$mode:$result"; exit 1; }
    done
done
export MOLE_CHROME_APP_PATHS="$TMPDIR/fixture-chrome.app"
export MOLE_EDGE_APP_PATHS="$TMPDIR/fixture-edge.app"
export MOLE_BRAVE_APP_PATHS="$TMPDIR/fixture-brave.app"
for browser in chrome edge brave; do
    result=$("clean_${browser}_old_versions")
    [[ "$result" == REACHED:*"fixture-${browser}.app" ]] || exit 1
done
echo 'Fixture routing verified for all three browsers.'
EOF
    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"Fixture routing verified"* ]]
}
