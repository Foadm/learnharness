#!/usr/bin/env bash
# Runs once when the codespace is created: install, restore data, build.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p "$LH_DATA_DIR" "$(dirname "$LH_AUTH_FILE")" /workspaces/.lh-logs
chmod 700 "$(dirname "$LH_AUTH_FILE")"
[ -f "$LH_AUTH_FILE" ] || { echo '{}' > "$LH_AUTH_FILE"; chmod 600 "$LH_AUTH_FILE"; }

npm ci

# Restore learning data from the backup repo before the app first starts.
bash .devcontainer/data-sync.sh restore || true

bash .devcontainer/server.sh build
