#!/usr/bin/env bash
# Builds and serves LearnHarness in production mode inside the codespace.
#
# Production mode, not `next dev`: the dev server blocks cross-origin requests
# to its dev assets unless the host is listed in allowedDevOrigins, and the
# forwarded *.app.github.dev address is not. `npm start` has no such gate.
#
#   server.sh build   build now and record the commit that was built
#   server.sh run     rebuild if the checkout changed since, then serve
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${LH_PORT:-3100}"
STAMP=.next/.lh-built-from

log() { echo "[server $(date -u +%FT%TZ)] $*"; }

source_id() {
	# The commit plus any uncommitted changes to tracked files.
	{ git rev-parse HEAD; git diff HEAD --stat; } | sha1sum | cut -d' ' -f1
}

build() {
	log "building"
	npm run build
	source_id > "$STAMP"
	log "build done"
}

case "${1:-}" in
build)
	build
	;;
run)
	if pgrep -f "next start.*-p $PORT" >/dev/null; then
		log "already running on $PORT"
		exit 0
	fi
	if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$(source_id)" ]; then
		build
	fi
	log "serving on $PORT (data: $LH_DATA_DIR)"
	exec npm start -- -p "$PORT" -H 0.0.0.0
	;;
*)
	echo "usage: $0 build|run" >&2
	exit 2
	;;
esac
