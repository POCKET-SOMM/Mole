#!/usr/bin/env bats

setup_file() {
	PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	export PROJECT_ROOT

	TEST_HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-optimize-summary.XXXXXX")"
	export TEST_HOME
}

teardown_file() {
	if [[ "$TEST_HOME" == "${BATS_TEST_DIRNAME}/tmp-optimize-summary."* ]]; then
		rm -rf "$TEST_HOME"
	fi
}

@test "optimize dry-run summary reports outcomes instead of catalog size" {
	run env HOME="$TEST_HOME" MOLE_TEST_NO_AUTH=1 MOLE_ASSUME_VPN_ACTIVE=0 NO_COLOR=1 "$PROJECT_ROOT/mole" optimize --dry-run

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
    [[ "$output" == *"Preview only"* ]] || return 1
    [[ "$output" != *"Would apply"* ]] || return 1
    run env HOME="$TEST_HOME" "$PROJECT_ROOT/mole" history --json
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["sessions"][0]["items"] == 0'

}

@test "selected optimize failure reaches terminal exit and history contracts" {
    run env HOME="$TEST_HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_NO_AUTH=1 /bin/bash <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/tasks.sh"
source "$PROJECT_ROOT/lib/optimize/review.sh"
eval "$(sed -n '/^cleanup_all() {/,/^}/p' "$PROJECT_ROOT/bin/optimize.sh")"
show_optimization_summary() { printf 'failed=%s\n' "$(optimize_outcome_count failed)"; }
stop_inline_spinner() { :; }
stop_sudo_session() { :; }
opt_disk_verify() { optimize_task_result "$MOLE_OPTIMIZE_OUTCOME_FAILED"; }
export MOLE_CURRENT_COMMAND=optimize
optimize_outcomes_reset
log_operation_session_start optimize
trap 'cleanup_all "$?"' EXIT
mole_optimize_apply disk_verify
EOF
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"failed=1"* ]]
    run env HOME="$TEST_HOME" "$PROJECT_ROOT/mole" history --json
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | python3 -c 'import json,sys; s=json.load(sys.stdin)["sessions"][0]; assert s["items"] == 0 and s["failed_tasks"] == 1'
}

@test "optimize cleanup records startup and interrupt failures in history" {
	run env HOME="$TEST_HOME/cleanup-history" PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/optimize/outcomes.sh"
eval "$(sed -n '/^cleanup_all() {/,/^}/p' "$PROJECT_ROOT/bin/optimize.sh")"

stop_inline_spinner() { :; }
stop_sudo_session() { :; }
cleanup_temp_files() { :; }
log_operation_session_end() { :; }
log_operation() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }

optimize_outcomes_reset
cleanup_all 1
cleanup_all 130
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
	[[ "$output" == *"optimize|TASK_FAILED|session|exit status 1"* ]] || return 1
	[[ "$output" == *"optimize|TASK_FAILED|interrupted|exit status 130"* ]]
}

@test "optimize EXIT trap forwards the terminal status to cleanup" {
	run env PROJECT_ROOT="$PROJECT_ROOT" /bin/bash --noprofile --norc <<'EOF'
set -euo pipefail
grep -qF "trap 'cleanup_all \"\$?\"' EXIT" "$PROJECT_ROOT/bin/optimize.sh"
EOF

	[[ "$status" -eq 0 ]] || { echo "$output"; return 1; }
}
