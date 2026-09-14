#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-brew-uninstall-home.XXXXXX")"
    export HOME

    # Prevent AppleScript permission dialogs during tests
    MOLE_TEST_MODE=1
    export MOLE_TEST_MODE
}

teardown_file() {
    if [[ "$HOME" == "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        rm -rf "$HOME"
    fi
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    # Safety: refuse to operate on a real home directory.
    if [[ "$HOME" != "${BATS_TEST_DIRNAME}/tmp-"* ]]; then
        printf 'FATAL: HOME is not a test temp dir: %s\n' "$HOME" >&2
        return 1
    fi
    mkdir -p "$HOME/Applications"
    mkdir -p "$HOME/Library/Caches"
    # Create fake Caskroom
    mkdir -p "$HOME/Caskroom/test-app/1.2.3/TestApp.app"
}

@test "get_brew_cask_name detects an exact resolved Caskroom app" {
    mkdir -p "$HOME/Applications/TestApp.app"
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"
# Mock external evidence, not the production function being tested. No actual
# Homebrew installation is required or queried by this deterministic first stage.
brew() { echo unexpected-brew-call >&2; return 99; }
resolve_path() {
    [[ "$1" == "$HOME/Applications/TestApp.app" ]] || return 1
    printf '%s\n' '/opt/homebrew/Caskroom/test-app/1.0.0/TestApp.app'
}
get_brew_cask_name "$HOME/Applications/TestApp.app"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "test-app" ]]
}

@test "get_brew_cask_name handles non-brew apps" {
    mkdir -p "$HOME/Applications/ManualApp.app"

    result=$(
        /bin/bash << EOF
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"
# Mock brew to return nothing for this
brew() { return 1; }
export -f brew
get_brew_cask_name "$HOME/Applications/ManualApp.app" || echo "not_found"
EOF
    )

    [[ "$result" == "not_found" ]]
}

@test "brew detection requires brew info to mention the exact selected app path" {
    mkdir -p "$HOME/Applications/Owned.app" "$HOME/Applications/Other.app" "$HOME/Applications/SameName.app"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

brew() {
    case "$*" in
        "list --cask")
            printf '%s\n' "mixed" "owned" "samename" "standard"
            ;;
        "info --cask owned")
            printf 'app "%s"\n' "$HOME/Applications/Owned.app"
            ;;
        "info --cask samename")
            printf '%s\n' 'app "/Applications/SameName.app"'
            ;;
        "info --cask standard")
            printf '%s\n' 'Standard.app (App)'
            ;;
        "info --cask mixed")
            printf '%s\n' 'Mixed.APP (App)'
            ;;
        *)
            return 1
            ;;
    esac
}
export -f brew

owned=$(_detect_cask_via_brew_list "$HOME/Applications/Owned.app" "Owned.app")
[[ "$owned" == "owned" ]] || exit 1
! _detect_cask_via_brew_list "$HOME/Applications/Other.app" "Other.app"
! _detect_cask_via_brew_list "$HOME/Applications/SameName.app" "SameName.app"
! get_brew_cask_name "$HOME/Applications/SameName.app"
standard=$(_detect_cask_via_brew_list "/Applications/Standard.app" "Standard.app")
[[ "$standard" == "standard" ]] || exit 1
mixed=$(_detect_cask_via_brew_list "/Applications/Mixed.APP" "Mixed.APP")
[[ "$mixed" == "mixed" ]] || exit 1
EOF

    [ "$status" -eq 0 ]
}

@test "Homebrew detection preserves timeout and signal probe statuses" {
    mkdir -p "$HOME/Applications/Probe.app"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

brew() { printf '%s\n' probe; }
run_with_timeout() { return "${PROBE_RC:?}"; }

PROBE_RC=124
rc=0
is_brew_cask_installed probe || rc=$?
[[ $rc -eq 124 ]] || exit 1
rc=0
_detect_cask_via_brew_list "$HOME/Applications/Probe.app" "Probe.app" || rc=$?
[[ $rc -eq 124 ]] || exit 1
rc=0
get_brew_cask_name "$HOME/Applications/Probe.app" || rc=$?
[[ $rc -eq 124 ]] || exit 1

PROBE_RC=143
rc=0
is_brew_cask_installed probe || rc=$?
[[ $rc -eq 143 ]] || exit 1
rc=0
_detect_cask_via_brew_list "$HOME/Applications/Probe.app" "Probe.app" || rc=$?
[[ $rc -eq 143 ]] || exit 1
rc=0
get_brew_cask_name "$HOME/Applications/Probe.app" || rc=$?
[[ $rc -eq 143 ]]
EOF

    [ "$status" -eq 0 ]
}

@test "brew uninstall preserves an interrupted app size probe" {
    mkdir -p "$HOME/Applications/Probe.app"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

brew() { printf 'UNEXPECTED_BREW\n'; }
get_path_size_kb() { return 124; }
rc=0
brew_uninstall_cask probe "$HOME/Applications/Probe.app" || rc=$?
printf 'RC=%s\n' "$rc"
[[ $rc -eq 124 ]]
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
    [[ "$output" == *"RC=124"* ]] || return 1
    [[ "$output" != *"UNEXPECTED_BREW"* ]]
}

@test "Caskroom symlink detection rejects a mismatched app bundle name" {
    mkdir -p "$HOME/Applications"
    ln -s "/opt/homebrew/Caskroom/real-cask/1.0/Real.app" "$HOME/Applications/Fake.app"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"
resolve_path() { printf '%s\n' "/opt/homebrew/Caskroom/real-cask/1.0/Real.app"; }
! _detect_cask_via_resolved_path "$HOME/Applications/Fake.app"
! _detect_cask_via_symlink_check "$HOME/Applications/Fake.app"
EOF

    [ "$status" -eq 0 ] || {
        echo "$output"
        return 1
    }
}

# This fork keeps casks because owner hooks have no complete mutation plan.
# Standalone legacy helper tests below still pin its argv and refusal behavior.
@test "cask selection keeps app and data without hooks or sudo" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash "$PROJECT_ROOT/tests/helpers/local_cask.sh" plain
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "cask selection keeps both same-identity installs" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash "$PROJECT_ROOT/tests/helpers/local_cask.sh" sibling
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "cask selection never falls back when package state is absent" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash "$PROJECT_ROOT/tests/helpers/local_cask.sh" absent
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "cask dry-run keeps files and starts no package or system actions" {
    run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash "$PROJECT_ROOT/tests/helpers/local_cask.sh" dry
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "brew_uninstall_cask passes cask token as argv without shell evaluation" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

debug_log() { :; }
get_path_size_kb() { echo "100"; }
run_with_timeout() { shift; "$@"; }
is_brew_cask_installed() { return 1; }

brew() {
    printf '<%s>\n' "$@" >> "$HOME/brew_argv.log"
    return 0
}
export -f brew

cask_name='bad"; touch "$HOME/pwned"; #'
brew_uninstall_cask "$cask_name"

[[ ! -e "$HOME/pwned" ]] || exit 1
grep -Fx '<bad"; touch "$HOME/pwned"; #>' "$HOME/brew_argv.log"
EOF

    [ "$status" -eq 0 ]
}

@test "_detect_cask_via_caskroom_search handles empty uniq array expansion under set -u" {
    mkdir -p "$BATS_TEST_TMPDIR/TestCaskApp.app"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" TEST_APP_PATH="$BATS_TEST_TMPDIR/TestCaskApp.app" /bin/bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/brew.sh"

find() {
    echo "/opt/homebrew/Caskroom/test-cask-app/1.0.0/TestCaskApp.app"
}
run_with_timeout() {
    shift
    "$@"
}
_mole_brew_probe() {
    echo "test-cask-app"
    return 0
}

_detect_cask_via_caskroom_search "$TEST_APP_PATH"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == "test-cask-app" ]]
}
