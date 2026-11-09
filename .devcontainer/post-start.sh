#!/usr/bin/env bash
# Runs every time the codespace starts: restore data if needed, then start
# the backup loop and the app. Both are detached so they keep running after
# this hook returns. Safe to re-run: each refuses to start a second copy.
set -euo pipefail
cd "$(dirname "$0")/.."
LOGS=/workspaces/.lh-logs
mkdir -p "$LOGS"

# Restore before the app starts, so the app never writes into an empty
# folder that the backup repo would then conflict with.
bash .devcontainer/data-sync.sh restore >>"$LOGS/data-sync.log" 2>&1 || true

setsid nohup bash .devcontainer/data-sync.sh loop >>"$LOGS/data-sync.log" 2>&1 < /dev/null &
setsid nohup bash .devcontainer/server.sh run >>"$LOGS/server.log" 2>&1 < /dev/null &

echo "LearnHarness is starting on port $LH_PORT (log: $LOGS/server.log)."
echo "Data backup log: $LOGS/data-sync.log"
grep -h 'BACKUP OFF' "$LOGS/data-sync.log" 2>/dev/null | tail -1 || true
