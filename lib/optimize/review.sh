#!/bin/bash
# A fixed, reviewable task selection. Other legacy tasks are unavailable here.
mole_optimize_review() {
    load_whitelist optimize
    optimize_outcomes_reset
    log_operation_session_start optimize
    printf '\nLocal maintenance review\n\n'
    printf '1. Verify the startup filesystem (read-only, bounded; no repair).\n'
    printf '2. Set Finder DSDontWriteNetworkStores and DSDontWriteUSBStores to true\n'
    printf '   in com.apple.desktopservices for this user. Persistent preference;\n'
    printf '   undo by restoring these two preferences in the same domain.\n\n'
    printf 'Browser databases, saved sessions, security history and system caches are kept.\n'
    if [[ "${MOLE_DRY_RUN:-0}" == 1 || ! -t 0 ]]; then
        printf 'Preview only. Run mo optimize in a terminal to select a task.\n'
        return 0
    fi
    local choice="" action="" answer=""
    printf '\nChoose one task (Enter cancels): '
    IFS= read -r choice || return 130
    case "$choice" in
        '') return 0 ;;
        1) action=disk_verify ;;
        2) action=prevent_network_dsstore ;;
        *)
            printf 'Unknown task; no changes made.\n' >&2
            return 2
            ;;
    esac
    printf 'Run the selected task %s? Type apply: ' "$choice"
    IFS= read -r answer || return 130
    [[ "$answer" == apply ]] || return 0
    mole_optimize_apply "$action"
}

mole_optimize_apply() {
    local action="$1" rc=0
    case "$action" in disk_verify | prevent_network_dsstore) ;; *) return 2 ;; esac
    local MOLE_ENABLE_DISK_VERIFY=1
    local MOLE_OPTIMIZE_SUDO_AVAILABLE=false
    execute_optimization "$action" || rc=$?
    show_optimization_summary
    [[ $rc -eq 0 ]] || return "$rc"
    optimize_outcomes_succeeded
}
