#!/usr/bin/env bats
# Child scripts intentionally expand their own HOME; Bats cases are isolated.
# shellcheck disable=SC2016,SC2030,SC2031

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export HOME="$BATS_TEST_TMPDIR/home"
    export MOLE_TEST_NO_AUTH=1 MOLE_TEST_MODE=1 TERM=xterm-256color
    mkdir -p "$HOME"
}


@test "ordinary update cannot download or replace the local fork" {
    mkdir -p "$HOME/bin"
    for cmd in curl wget brew; do
        printf '#!/bin/bash\nprintf "%%s\\n" invoked >> "$HOME/network-attempts"\nexit 99\n' > "$HOME/bin/$cmd"
        chmod +x "$HOME/bin/$cmd"
    done
    run env PATH="$HOME/bin:$PATH" "$PROJECT_ROOT/mole" update --force --nightly
    [ "$status" -eq 0 ]
    [[ "$output" == *"does not download or replace itself"* ]]
    [ ! -e "$HOME/network-attempts" ]
}

@test "maintenance guards retain resources even with an empty whitelist" {
    source "$PROJECT_ROOT/lib/core/common.sh"
    export MOLE_CURRENT_COMMAND=clean
    WHITELIST_PATTERNS=()
    for path in "$HOME/Library/Caches/Google/Chrome/Cache" "$HOME/Apps/Editor.app/Contents" "$HOME/.cache/huggingface/model" "$HOME/.Trash/document"; do
        mkdir -p "$path"
        should_protect_path "$path"
        run safe_remove "$path" true
        [ "$status" -ne 0 ]
        [ -d "$path" ]
    done
}

@test "purge keeps downloaded dependencies and their nested build artifacts" {
    source "$PROJECT_ROOT/lib/core/common.sh"
    export MOLE_CURRENT_COMMAND=purge
    for path in "$HOME/project/node_modules/pkg/dist" "$HOME/project/.venv/lib" "$HOME/project/Pods/build" "$HOME/project/vendor/pkg/bin"; do
        mole_local_cleanup_protected "$path"
    done
    run mole_local_cleanup_protected "$HOME/project/.pytest_cache"
    [ "$status" -eq 1 ]
}

@test "review captures one candidate and dry-run leaves its contents intact" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/tests/helpers/local_review.sh"
        [[ "${MOLE_REVIEW_PATHS[0]}" == "$cache/bincache-one" ]] || exit 1
        [[ -f "$cache/bincache-one/object" ]] || exit 1
    '
    [ "$status" -eq 0 ]
}

@test "review applies a frozen selection and leaves later discoveries intact" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/tests/helpers/local_review.sh"
        mkdir -p "$cache/bincache-later"
        printf keep > "$cache/bincache-later/object"
        DRY_RUN=false; MOLE_DRY_RUN=0
        mole_review_apply 0 || exit $?
        [[ ! -e "$cache/bincache-one" ]] || exit 1
        [[ -f "$cache/bincache-later/object" ]] || exit 1
    '
    [ "$status" -eq 0 ] || { printf "%s\n" "$output" >&3; return 1; }
}

@test "review refuses a replaced object" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/tests/helpers/local_review.sh"
        mv "$cache/bincache-one" "$cache/original"
        mkdir "$cache/bincache-one"
        printf keep > "$cache/bincache-one/new"
        DRY_RUN=false; MOLE_DRY_RUN=0
        rc=0; mole_review_apply 0 || rc=$?
        [[ $rc -eq 3 && -f "$cache/bincache-one/new" && -f "$cache/original/object" ]] || exit 1
    '
    [ "$status" -eq 0 ]
}

@test "review refuses a newly running or unknown owner" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/tests/helpers/local_review.sh"
        DRY_RUN=false; MOLE_DRY_RUN=0
        pyinstaller_build_process_state() { return 0; }
        rc=0; mole_review_apply 0 || rc=$?
        [[ $rc -eq 3 && -f "$cache/bincache-one/object" ]] || exit 1
        pyinstaller_build_process_state() { return 2; }
        rc=0; mole_review_apply 0 || rc=$?
        [[ $rc -eq 3 && -f "$cache/bincache-one/object" ]] || exit 1
    '
    [ "$status" -eq 0 ]
}

@test "cloud locations are refused before probing their filesystem" {
    source "$PROJECT_ROOT/lib/core/common.sh"
    run_with_timeout() { printf probe > "$HOME/probed"; return 0; }
    run mole_path_is_local "$HOME/Library/CloudStorage/provider/file"
    [ "$status" -eq 1 ]
    [ ! -e "$HOME/probed" ]
    run mole_path_is_local "$HOME"
    [ "$status" -eq 1 ]
    [ -e "$HOME/probed" ]
}

@test "PATH symlink into Downloads prevents automatic deletion" {
    source "$PROJECT_ROOT/lib/core/common.sh"
    mkdir -p "$HOME/bin" "$HOME/Downloads/tool" "$HOME/unrelated"
    printf '#!/bin/sh\nexit 0\n' > "$HOME/Downloads/tool/run"
    chmod +x "$HOME/Downloads/tool/run"
    ln -s "$HOME/Downloads/tool/run" "$HOME/bin/tool"
    PATH="$HOME/bin:/usr/bin:/bin" mole_preserves_command_target "$HOME/Downloads/tool"
    run env PATH="$HOME/bin:/usr/bin:/bin" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash -c '
        source "$PROJECT_ROOT/lib/core/common.sh"
        export MOLE_CURRENT_COMMAND=installer
        safe_remove "$HOME/Downloads/tool" true
    '
    [ "$status" -ne 0 ]
    [ -f "$HOME/Downloads/tool/run" ]
    run mole_preserves_command_target "$HOME/unrelated"
    [ "$status" -eq 1 ]
}

@test "review cancellation starts no later selected action" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/tests/helpers/local_review.sh"
        mkdir "$cache/bincache-two"
        MOLE_REVIEW_PATHS=()
        clean_pyinstaller_bincache || exit $?
        [[ ${#MOLE_REVIEW_PATHS[@]} -eq 2 ]] || exit 1
        clean_guarded_dev_cache_root() { printf called >> "$HOME/applied"; return 124; }
        DRY_RUN=false; MOLE_DRY_RUN=0
        rc=0; mole_review_apply 0 1 || rc=$?
        [[ $rc -eq 124 && "$(cat "$HOME/applied")" == called ]] || exit 1
        [[ -f "$cache/bincache-one/object" && -d "$cache/bincache-two" ]] || exit 1
    '
    [ "$status" -eq 0 ] || { printf "%s\n" "$output" >&3; return 1; }
}

@test "noninteractive maintenance cannot use cached sudo to widen its preview" {
    mkdir "$HOME/bin"
    printf '#!/bin/bash\nprintf called >> "$HOME/sudo-calls"\nexit 0\n' > "$HOME/bin/sudo"
    chmod +x "$HOME/bin/sudo"
    run env PATH="$HOME/bin:$PATH" "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Local cleanup review"* ]]
    run env PATH="$HOME/bin:$PATH" "$PROJECT_ROOT/mole" optimize --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Preview only"* ]]
    [ ! -e "$HOME/sudo-calls" ]
}

@test "installer scan discards partial producer output and propagates cancellation" {
    mkdir "$HOME/Downloads"
    touch "$HOME/Downloads/fixture.dmg"
    run /bin/bash -c '
        source "$PROJECT_ROOT/bin/installer.sh"
        mole_path_is_local() { return 0; }
        fd() { printf "%s\0" "$HOME/Downloads/fixture.dmg"; return 124; }
        run_with_timeout() { shift; "$@"; }
        handle_candidate_file() { printf unexpected > "$HOME/candidate"; }
        rc=0; scan_installers_in_path "$HOME/Downloads" || rc=$?
        [[ $rc -eq 124 && ! -e "$HOME/candidate" ]] || exit 1
        scan_all_installers() { printf "%s\n" "$HOME/Downloads/fixture.dmg"; return 124; }
        rc=0; collect_installers || rc=$?
        [[ $rc -eq 124 && ${#INSTALLER_PATHS[@]} -eq 0 ]] || exit 1
    '
    [ "$status" -eq 0 ] || { printf "%s\n" "$output" >&3; return 1; }
}

@test "placeholder flags prevent probing capacity or reading contents" {
    source "$PROJECT_ROOT/lib/core/common.sh"
    run_with_timeout() {
        shift
        if [[ "$1" == /usr/bin/stat ]]; then printf "1073741824\n"; else printf unexpected > "$HOME/capacity-probe"; fi
    }
    run mole_path_is_local "$HOME/placeholder"
    [ "$status" -eq 1 ]
    [ ! -e "$HOME/capacity-probe" ]
}

@test "ordinary installer scan failure cannot be reported as an empty success" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/bin/installer.sh"
        scan_all_installers() { printf "%s\n" "$HOME/partial.dmg"; return 1; }
        show_installer_menu() { printf unexpected > "$HOME/menu-opened"; }
        rc=0; perform_installers || rc=$?
        [[ $rc -eq 3 && ${#INSTALLER_PATHS[@]} -eq 0 && ! -e "$HOME/menu-opened" ]] || exit 1
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installer scan incomplete (status 1)"* ]]
    [[ "$output" != *"Great!"* ]]
}

@test "local and PATH probe cancellation propagates through the deletion sink" {
    run /bin/bash -c '
        source "$PROJECT_ROOT/lib/core/common.sh"
        export MOLE_CURRENT_COMMAND=clean
        export _MOLE_LOCAL_CACHE_ROOT="$HOME/cache"
        mkdir -p "$HOME/cache/target"
        printf keep > "$HOME/cache/target/object"
        for probe in local command; do
            for cancellation in 124 130; do
                MOLE_CLEAN_CANCEL_STATUS=0
                mole_path_is_local() {
                    if [[ "$probe" == local ]]; then return "$cancellation"; fi
                    return 0
                }
                mole_preserves_command_target() { return "$cancellation"; }
                rc=0; safe_remove "$HOME/cache/target" true || rc=$?
                [[ $rc -eq $cancellation && -f "$HOME/cache/target/object" ]] || exit 1
            done
        done
    '
    [ "$status" -eq 0 ] || { printf "%s\n" "$output" >&3; return 1; }
}
