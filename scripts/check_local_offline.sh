#!/bin/bash
# macOS runtime smoke checks. No installation or real cleanup is performed.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -x /usr/bin/sandbox-exec ]] || {
    echo 'macOS sandbox-exec is required' >&2
    exit 1
}
[[ -x "$PROJECT_ROOT/bin/analyze-go" && -x "$PROJECT_ROOT/bin/status-go" ]] || {
    echo 'Build this fork with make build before this check' >&2
    exit 1
}
# A mock HOME inside Darwin-managed /var/folders is intentionally protected by
# cleanup policy. Use a dedicated local scratch root for the apply fixture.
workspace=$(mktemp -d "/private/tmp/mole-offline-check.XXXXXX")
trap 'rm -rf "$workspace"' EXIT # SAFE: exact mktemp-created verification workspace containing only fixtures.
export HOME="$workspace/home" MOLE_TEST_NO_AUTH=1 MOLE_TEST_MODE=1
export MOLE_SKIP_FINDER_TESTS=1 TERM=xterm-256color
mkdir -p "$HOME/bin" "$HOME/scan"
printf identical > "$HOME/scan/a"
printf identical > "$HOME/scan/b"
printf different > "$HOME/scan/c"
cat > "$workspace/network-control.py" << 'PY'
import errno
import socket
import sys
sock = socket.socket()
sock.settimeout(1)
status = sock.connect_ex(('127.0.0.1', 9))
blocked = status in (errno.EPERM, errno.EACCES)
assert blocked == (sys.argv[1] == 'denied'), (status, sys.argv[1])
print('network control:', sys.argv[1], 'errno', status)
PY
profile="$(cat "$PROJECT_ROOT/scripts/test_sandbox.sb")
(deny network-outbound (remote ip \"*:*\"))"
test_temp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
_run_offline_fixture() {
    /usr/bin/sandbox-exec -D "PROJECT=$PROJECT_ROOT" -D "TEMPROOT=$test_temp_root" \
        -p "$profile" "$@"
}
/usr/bin/python3 "$workspace/network-control.py" allowed
_run_offline_fixture /usr/bin/python3 "$workspace/network-control.py" denied

for command in curl wget nc ncat; do
    cat > "$HOME/bin/$command" << 'SH'
#!/bin/bash
printf '%s\n' "$0 $*" >> "$HOME/network-attempts"
exit 99
SH
    chmod +x "$HOME/bin/$command"
done
export PATH="$HOME/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# Prove the request canary works before checking ordinary runtime paths.
curl positive-control || [[ $? -eq 99 ]]
[[ -s "$HOME/network-attempts" ]]
: > "$HOME/network-attempts"
for pass in cold warm; do
    for command in --help --version update; do
        _run_offline_fixture "$PROJECT_ROOT/mole" "$command" > "$workspace/$pass-$command"
    done
    _run_offline_fixture "$PROJECT_ROOT/mole" clean --dry-run > "$workspace/$pass-clean"
    _run_offline_fixture "$PROJECT_ROOT/mole" optimize --dry-run > "$workspace/$pass-optimize"
    _run_offline_fixture "$PROJECT_ROOT/mole" analyze --json "$HOME/scan" > "$workspace/$pass-analysis.json"
    _run_offline_fixture "$PROJECT_ROOT/mole" analyze --inventory "$HOME/scan" > "$workspace/$pass-inventory.json"
    _run_offline_fixture "$PROJECT_ROOT/mole" analyze --duplicates "$HOME/scan" > "$workspace/$pass-duplicates.json"
    status_rc=0
    _run_offline_fixture "$PROJECT_ROOT/mole" status --json > "$workspace/$pass-status.json" 2> "$workspace/$pass-status.err" || status_rc=$?
    if [[ $status_rc -ne 0 ]]; then
        [[ $status_rc -eq 1 ]] || exit "$status_rc"
        # macOS refuses the platform ps binary even under an allow-all sandbox.
        # The collector must preserve available JSON and report the failure.
        grep -q 'incomplete metrics:.*ps: operation not permitted' "$workspace/$pass-status.err"
        printf 'Status preserved partial JSON; macOS sandbox prevented process inspection.\n'
    fi
done
# Exercise a real selected fixture deletion with outbound traffic denied.
# The shared fixture supplies an absent owner; no installed application is touched.
# shellcheck disable=SC2016 # Expand fixture variables only inside the child shell.
if ! PROJECT_ROOT="$PROJECT_ROOT" _run_offline_fixture /bin/bash -c '
    source "$PROJECT_ROOT/tests/helpers/local_review.sh"
    mkdir "$cache/bincache-later"
    printf keep > "$cache/bincache-later/object"
    DRY_RUN=false; MOLE_DRY_RUN=0
    mole_review_apply 0 || exit $?
    [[ ! -e "$cache/bincache-one" && -f "$cache/bincache-later/object" ]]
' > "$workspace/selected-apply" 2>&1; then
    cat "$workspace/selected-apply" >&2
    echo 'Offline selected fixture application failed' >&2
    exit 1
fi
[[ ! -s "$HOME/network-attempts" ]]
/usr/bin/python3 - "$workspace" << 'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
for path in root.glob('*.json'):
    json.loads(path.read_text())
for phase in ('cold', 'warm'):
    report = json.loads((root / (phase + '-duplicates.json')).read_text())
    assert report['complete']
    assert len(report['identical_content_candidates']) == 1
    assert len(report['identical_content_candidates'][0]) == 2
assert all((root / 'home/scan' / name).exists() for name in ('a', 'b', 'c'))
print('Offline cold/warm CLI and JSON smoke checks passed; fixture files retained.')
PY
