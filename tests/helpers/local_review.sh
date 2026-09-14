#!/bin/bash
# Shared fixture setup, executed in a child shell so CLI traps cannot replace Bats traps.
source "$PROJECT_ROOT/bin/clean.sh"
export MOLE_CURRENT_COMMAND=clean MOLE_DRY_RUN=1
_MOLE_REVIEW_PHASE=collect
_MOLE_REVIEW_DEADLINE=$((SECONDS + 30))
_MOLE_CLEAN_SECTION_DEADLINE="$_MOLE_REVIEW_DEADLINE"
DRY_RUN=true
pyinstaller_build_process_state() { return 1; }
cache="$HOME/Library/Application Support/pyinstaller"
mkdir -p "$cache/bincache-one"
printf 'compiled fixture\n' > "$cache/bincache-one/object"
clean_pyinstaller_bincache || exit $?
[[ ${#MOLE_REVIEW_PATHS[@]} -eq 1 ]] || exit 1
