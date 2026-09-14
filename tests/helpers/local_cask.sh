#!/bin/bash
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/uninstall/batch.sh"
mode="$1"
mkdir -p "$HOME/Applications/Fixture.app" "$HOME/Library/Application Support/Fixture"
printf keep > "$HOME/Library/Application Support/Fixture/data"
start_inline_spinner() { :; }
stop_inline_spinner() { :; }
get_file_owner() { whoami; }
get_path_size_kb() { echo 100; }
drain_pending_input() { :; }
print_summary_block() { printf '%s\n' "$@"; }
get_brew_cask_name() { echo fixture; }
find_app_files() { printf '%s\n' "$HOME/Library/Application Support/Fixture"; }
find_app_system_files() { :; }
get_diagnostic_report_paths_for_app() { :; }
run_with_timeout() {
    shift
    "$@"
}
unexpected_action() {
    printf '%s\n' "$*" >> "$HOME/cask-actions"
    return 1
}
brew() { unexpected_action brew "$@"; }
brew_uninstall_cask() { unexpected_action hook "$@"; }
ensure_sudo_session() { unexpected_action sudo "$@"; }
force_kill_app() { unexpected_action kill "$@"; }
stop_launch_services() { unexpected_action launch "$@"; }
remove_login_item() { unexpected_action login "$@"; }
mole_delete() { unexpected_action delete "$@"; }
remove_apps_from_dock() { unexpected_action dock "$@"; }
refresh_launch_services_after_uninstall() { unexpected_action refresh "$@"; }
is_brew_cask_installed() { [[ "$mode" != absent ]]; }
# Positive control establishes the side-effect recorder is live.
unexpected_action control || true
[[ "$(cat "$HOME/cask-actions")" == control ]]
: > "$HOME/cask-actions"
apps_data=()
if [[ "$mode" == sibling ]]; then
    mkdir -p "$HOME/Applications/Sibling.app"
    apps_data=("0|$HOME/Applications/Sibling.app|Sibling|com.example.fixture|0|Never|0")
fi
[[ "$mode" != dry ]] || export MOLE_DRY_RUN=1
selected_apps=("0|$HOME/Applications/Fixture.app|Fixture|com.example.fixture|0|Never")
files_cleaned=0 total_items=0 total_size_cleaned=0
rc=0
printf '\n' | batch_uninstall_applications > "$HOME/cask-output" 2>&1 || rc=$?
cat "$HOME/cask-output"
[[ $rc -eq 3 ]]
[[ -d "$HOME/Applications/Fixture.app" && -f "$HOME/Library/Application Support/Fixture/data" ]]
[[ ! -s "$HOME/cask-actions" ]]
[[ "$mode" != sibling || -d "$HOME/Applications/Sibling.app" ]]
grep -q 'Homebrew hooks do not expose a complete local mutation plan' "$HOME/cask-output"
