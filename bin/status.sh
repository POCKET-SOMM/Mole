#!/bin/bash
# Mole - Status command.
# Runs the Go system status panel.
# Shows live system metrics.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/local_policy.sh"
GO_BIN="$SCRIPT_DIR/status-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

echo "Bundled status binary not found. Build this fork locally with make build; no download was attempted." >&2
exit 1
