#!/usr/bin/env bats

@test "portable release source, hashes and archives preserve their contracts" {
    local project
    project="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    run env PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover \
        -s "$project/tests" -p package_release_test.py
    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"Ran 6 tests"* ]]
}

@test "portable removal never reaches installed Mole or Homebrew discovery" {
    local project fixture
    project="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    fixture="$(mktemp -d "$BATS_TEST_TMPDIR/portable.XXXXXX")"
    printf '%s\n' portable > "$fixture/PORTABLE"
    printf '%s\n' fixture > "$fixture/mole"
    run env PROJECT_ROOT="$project" PORTABLE_FIXTURE="$fixture" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/manage/remove.sh"
MOLE_ENTRY_SCRIPT="$PORTABLE_FIXTURE/mole"
# Positive trace below proves this recorder would detect reaching discovery.
brew_mole_formula_installed() { echo DISCOVERY_REACHED; return 1; }
command() { echo DISCOVERY_REACHED; return 1; }
for mode in false true; do
    result=$(remove_mole "$mode")
    [[ "$result" == *'portable Mole package'* && "$result" != *DISCOVERY_REACHED* ]] || exit 1
done
[[ $(command -v brew || true) == DISCOVERY_REACHED ]]
[[ -f "$PORTABLE_FIXTURE/mole" ]]
echo 'Portable removal kept the package and never discovered other installations.'
EOF
    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"never discovered other installations"* ]]
}
