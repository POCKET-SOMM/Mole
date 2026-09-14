#!/bin/bash
# In-memory selection; never serialize shell code or repeat discovery on apply.
MOLE_REVIEW_PATHS=()
MOLE_REVIEW_PARENTS=()
MOLE_REVIEW_PARENT_IDS=()
MOLE_REVIEW_IDS=()
MOLE_REVIEW_SIZES=()
MOLE_REVIEW_NAMES=()
MOLE_REVIEW_CONTAINERS=()
MOLE_REVIEW_ROOTS=()
MOLE_REVIEW_PROBES=()
MOLE_REVIEW_FAMILIES=()
MOLE_REVIEW_CONTAINER_PARENTS=()
MOLE_REVIEW_CONTAINER_PARENT_IDS=()
MOLE_REVIEW_CONTAINER_IDS=()
MOLE_REVIEW_ROOT_PARENTS=()
MOLE_REVIEW_ROOT_PARENT_IDS=()
MOLE_REVIEW_ROOT_IDS=()

mole_review_collect() {
    local guard="$1"
    shift
    [[ "$guard" == _dev_process_delete_guard_allows ]] || return 0
    [[ "${_MOLE_DEV_CACHE_PROCESS_PROBE:-}" == clang_module_cache_process_state ||
        "${_MOLE_DEV_CACHE_PROCESS_PROBE:-}" == pyinstaller_build_process_state ]] || return 0
    local name="${*: -1}" path size i validation_rc
    local -a paths=("${@:1:$#-1}")
    for path in "${paths[@]}"; do
        [[ $SECONDS -lt $_MOLE_REVIEW_DEADLINE ]] || return 124
        [[ -e "$path" && ! -L "$path" ]] || continue
        should_protect_path "$path" && continue
        is_path_whitelisted "$path" && continue
        validation_rc=0
        validate_path_for_deletion "$path" || validation_rc=$?
        [[ $validation_rc -ne 124 && $validation_rc -lt 128 ]] || return "$validation_rc"
        [[ $validation_rc -eq 0 ]] || continue
        "$guard" "$path" || return $?
        local remaining
        remaining=$(_mole_timeout_with_deadline "$MOLE_TIMEOUT_DISK_VERIFY_SEC" "$_MOLE_REVIEW_DEADLINE") || return $?
        size=$(get_path_size_kb "$path" "$remaining") || return $?
        [[ "$size" =~ ^[0-9]+$ ]] || return 2
        "$guard" "$path" || return $?
        [[ $SECONDS -lt $_MOLE_REVIEW_DEADLINE ]] || return 124
        _mole_snapshot_path_identity "$path" || return 2
        i=${#MOLE_REVIEW_PATHS[@]}
        MOLE_REVIEW_PATHS[i]="$path"
        MOLE_REVIEW_PARENTS[i]="$_MOLE_PATH_SNAPSHOT_PARENT"
        MOLE_REVIEW_PARENT_IDS[i]="$_MOLE_PATH_SNAPSHOT_PARENT_ID"
        MOLE_REVIEW_IDS[i]="$_MOLE_PATH_SNAPSHOT_TARGET_ID"
        MOLE_REVIEW_SIZES[i]="$size"
        MOLE_REVIEW_NAMES[i]="$name"
        MOLE_REVIEW_CONTAINERS[i]="$_MOLE_DEV_CACHE_CONTAINER"
        MOLE_REVIEW_ROOTS[i]="$_MOLE_DEV_CACHE_ROOT"
        MOLE_REVIEW_PROBES[i]="$_MOLE_DEV_CACHE_PROCESS_PROBE"
        MOLE_REVIEW_FAMILIES[i]="$_MOLE_DEV_PROCESS_GUARD_FAMILY"
        MOLE_REVIEW_CONTAINER_PARENTS[i]="$_MOLE_DEV_CACHE_CONTAINER_PARENT"
        MOLE_REVIEW_CONTAINER_PARENT_IDS[i]="$_MOLE_DEV_CACHE_CONTAINER_PARENT_ID"
        MOLE_REVIEW_CONTAINER_IDS[i]="$_MOLE_DEV_CACHE_CONTAINER_TARGET_ID"
        MOLE_REVIEW_ROOT_PARENTS[i]="$_MOLE_DEV_CACHE_ROOT_PARENT"
        MOLE_REVIEW_ROOT_PARENT_IDS[i]="$_MOLE_DEV_CACHE_ROOT_PARENT_ID"
        MOLE_REVIEW_ROOT_IDS[i]="$_MOLE_DEV_CACHE_ROOT_TARGET_ID"
    done
}

_mole_review_final_guard() {
    local path="$1" i="$_MOLE_REVIEW_INDEX"
    [[ "$path" == "${MOLE_REVIEW_PATHS[i]}" ]] || return 1
    mole_clean_process_guard "${MOLE_REVIEW_PROBES[i]}" 'Owner started' || return 1
    _mole_path_matches_identity "${MOLE_REVIEW_CONTAINERS[i]}" \
        "${MOLE_REVIEW_CONTAINER_PARENTS[i]}" "${MOLE_REVIEW_CONTAINER_PARENT_IDS[i]}" \
        "${MOLE_REVIEW_CONTAINER_IDS[i]}" || return 1
    _mole_path_matches_identity "${MOLE_REVIEW_ROOTS[i]}" \
        "${MOLE_REVIEW_ROOT_PARENTS[i]}" "${MOLE_REVIEW_ROOT_PARENT_IDS[i]}" \
        "${MOLE_REVIEW_ROOT_IDS[i]}" || return 1
    _mole_path_matches_identity "$path" "${MOLE_REVIEW_PARENTS[i]}" \
        "${MOLE_REVIEW_PARENT_IDS[i]}" "${MOLE_REVIEW_IDS[i]}"
}

mole_review_apply() {
    local i path rc=0 failed=0 removed=0
    local _MOLE_CLEAN_SECTION_DEADLINE=$((SECONDS + 30))
    local -a capacity_devices=() capacity_paths=() capacity_before=()
    local device known index before after
    for i in "$@"; do
        [[ $SECONDS -lt $_MOLE_CLEAN_SECTION_DEADLINE ]] || return 124
        [[ "$i" =~ ^[0-9]+$ && $i -lt ${#MOLE_REVIEW_PATHS[@]} ]] || return 2
        device="${MOLE_REVIEW_PARENT_IDS[i]%%:*}"
        known=false
        for ((index = 0; index < ${#capacity_devices[@]}; index++)); do
            [[ "${capacity_devices[index]}" != "$device" ]] || known=true
        done
        [[ "$known" == false ]] || continue
        capacity_devices+=("$device")
        capacity_paths+=("${MOLE_REVIEW_PARENTS[i]}")
        capacity_before+=("$(get_free_space_kb "${MOLE_REVIEW_PARENTS[i]}" || true)")
    done
    local _MOLE_REVIEW_PHASE=apply
    local _MOLE_SAFE_REMOVE_FINAL_GUARD=_mole_review_final_guard
    for i in "$@"; do
        [[ $SECONDS -lt $_MOLE_CLEAN_SECTION_DEADLINE ]] || return 124
        [[ "$i" =~ ^[0-9]+$ && $i -lt ${#MOLE_REVIEW_PATHS[@]} ]] || return 2
        local _MOLE_REVIEW_INDEX="$i"
        path="${MOLE_REVIEW_PATHS[i]}"
        local _MOLE_LOCAL_CACHE_ROOT="${MOLE_REVIEW_ROOTS[i]}"
        if ! _mole_review_final_guard "$path"; then
            printf 'Kept (ownership or identity changed): %q\n' "$path"
            failed=$((failed + 1))
            continue
        fi
        [[ $SECONDS -lt $_MOLE_CLEAN_SECTION_DEADLINE ]] || return 124
        rc=0
        # Exactly one frozen target; this does not repeat the family glob.
        clean_guarded_dev_cache_root "${MOLE_REVIEW_CONTAINERS[i]}" \
            "${MOLE_REVIEW_ROOTS[i]}" "${MOLE_REVIEW_PROBES[i]}" \
            "${MOLE_REVIEW_FAMILIES[i]}" "${MOLE_REVIEW_NAMES[i]}" "$path" || rc=$?
        [[ $rc -ne 124 && $rc -lt 128 ]] || return "$rc"
        if [[ $rc -ne 0 || -e "$path" || -L "$path" ]]; then
            printf 'Kept or incomplete: %q\n' "$path"
            failed=$((failed + 1))
        else
            removed=$((removed + 1))
        fi
    done
    log_operation_session_end clean "$removed" 0
    printf 'Removed: %s; kept or incomplete: %s. Sizes are estimates, not attributed free space.\n' "$removed" "$failed"
    for ((index = 0; index < ${#capacity_paths[@]}; index++)); do
        before="${capacity_before[index]}"
        after=$(get_free_space_kb "${capacity_paths[index]}" || true)
        if [[ "$before" =~ ^[0-9]+$ && "$after" =~ ^[0-9]+$ ]]; then
            printf 'Filesystem at %q: available capacity changed by %s bytes (includes concurrent activity).\n' \
                "${capacity_paths[index]}" "$(((after - before) * 1024))"
        fi
    done
    printf 'APFS volumes may share capacity; these readings are not additive.\n'
    [[ $failed -eq 0 ]] || return 3
}

mole_review_clean() {
    MOLE_REVIEW_PATHS=()
    export MOLE_CURRENT_COMMAND=clean
    mole_capture_invoking_project || return 2
    local _MOLE_REVIEW_PHASE=collect
    local _MOLE_REVIEW_DEADLINE=$((SECONDS + 30))
    local _MOLE_CLEAN_SECTION_DEADLINE="$_MOLE_REVIEW_DEADLINE"
    local requested_dry_run="$DRY_RUN"
    local DRY_RUN=true MOLE_DRY_RUN=1
    local _MOLE_LOCAL_CACHE_ROOT=""
    SYSTEM_CLEAN=false
    printf '\nLocal cleanup review\n'
    printf 'Browser data, apps, models, dependencies, sessions and system state are kept.\n'
    printf 'Only validated local compiler caches are eligible; deletion is permanent.\n\n'
    if [[ -n "$EXTERNAL_VOLUME_TARGET" ]]; then
        printf 'External volumes are inspection-only. Use mo analyze with the local volume path.\n'
        return 0
    fi
    log_operation_session_start clean
    local rc=0
    clean_pyinstaller_bincache || rc=$?
    [[ $rc -eq 0 ]] || return "$rc"
    clean_clang_module_cache || rc=$?
    [[ $rc -eq 0 ]] || return "$rc"
    local i
    for ((i = 0; i < ${#MOLE_REVIEW_PATHS[@]}; i++)); do
        printf '%s. %q (%s estimated; %s; rebuilt by local compiler)\n' \
            "$((i + 1))" "${MOLE_REVIEW_PATHS[i]}" \
            "$(bytes_to_human_kb "${MOLE_REVIEW_SIZES[i]}")" "${MOLE_REVIEW_NAMES[i]}"
    done
    if [[ ${#MOLE_REVIEW_PATHS[@]} -eq 0 ]]; then
        printf 'No eligible compiler caches found. Use mo analyze to inspect other storage.\n'
        log_operation_session_end clean 0 0
        return 0
    fi
    if [[ "$requested_dry_run" == true || ! -t 0 ]]; then
        printf '\nPreview only. Run mo clean in a terminal to select exact items.\n'
        log_operation_session_end clean 0 0
        return 0
    fi
    local selection="" answer="" index
    local -a selected=() tokens=()
    printf '\nSelect item numbers separated by spaces (Enter cancels): '
    IFS= read -r selection || return 130
    [[ -n "$selection" ]] || return 0
    read -r -a tokens <<< "$selection"
    for index in "${tokens[@]}"; do
        [[ "$index" =~ ^[1-9][0-9]{0,5}$ ]] || return 2
        [[ $index -le ${#MOLE_REVIEW_PATHS[@]} ]] || return 2
        index=$((index - 1))
        case " ${selected[*]:-} " in *" $index "*) continue ;; esac
        selected+=("$index")
        printf 'Selected: %q\n' "${MOLE_REVIEW_PATHS[index]}"
    done
    printf 'Permanently remove these %s compiler-cache items? Type delete: ' "${#selected[@]}"
    IFS= read -r answer || return 130
    [[ "$answer" == delete ]] || return 0
    DRY_RUN=false
    MOLE_DRY_RUN=0
    mole_review_apply "${selected[@]}"
}
