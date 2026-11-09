#!/usr/bin/env bash
# Backs up the learning data folder ($LH_DATA_DIR) to a private GitHub repo.
#
#   data-sync.sh restore   if the data folder is empty, clone the backup into it
#   data-sync.sh once      commit and push now if anything changed
#   data-sync.sh loop      `once` every $LH_SYNC_INTERVAL seconds (default 300)
#
# Needs the Codespaces secret LH_DATA_TOKEN: a fine-grained token with
# Contents read/write on the backup repo only. The codespace's own
# GITHUB_TOKEN covers just this repo, not the backup. Without the token the
# app still runs, and this script logs "BACKUP OFF" and does nothing.
#
# The backup repo is LH_DATA_REPO (owner/name), default
# "$GITHUB_USER/learnharness-data". Keys and sign-ins are never backed up:
# they live in $LH_AUTH_FILE's folder, outside the data folder, and the
# data repo's .gitignore excludes credential-shaped files as a second guard.
set -uo pipefail

DATA="${LH_DATA_DIR:?LH_DATA_DIR is not set}"
REPO="${LH_DATA_REPO:-${GITHUB_USER:-}/learnharness-data}"
INTERVAL="${LH_SYNC_INTERVAL:-300}"
REMOTE="${LH_DATA_REMOTE:-https://github.com/$REPO.git}"
BRANCH=main
LOCK=/tmp/lh-data-sync.lock

log() { echo "[data-sync $(date -u +%FT%TZ)] $*"; }

# Supply the token for github.com only to this script's git calls. The empty
# credential.helper first clears the codespace's own helper, whose token
# cannot reach the backup repo. The token is never written to disk.
g() {
	git -c credential.helper= \
		-c 'credential.helper=!f() { echo username=x-access-token; echo "password=$LH_DATA_TOKEN"; }; f' \
		-c user.name="LearnHarness backup" \
		-c user.email="backup@learnharness.invalid" \
		-C "$DATA" "$@"
}

ready() {
	if [ -z "${LH_DATA_TOKEN:-}" ]; then
		log "BACKUP OFF: the Codespaces secret LH_DATA_TOKEN is not set. Learning data is NOT being backed up. See .devcontainer/README.md."
		return 1
	fi
	if [ "$REPO" = "/learnharness-data" ]; then
		log "BACKUP OFF: set LH_DATA_REPO (owner/name); GITHUB_USER is empty."
		return 1
	fi
	return 0
}

write_repo_rules() {
	if [ ! -f "$DATA/.gitignore" ]; then
		cat > "$DATA/.gitignore" <<'EOF'
# Never back up keys or sign-ins (they should not be in this folder at all).
auth.json
*credentials.json*
.env*
# Debug captures can hold raw provider traffic; keep them local.
debug/
# Half-written files from the app's atomic writes.
*.tmp-*
EOF
	fi
	if [ ! -f "$DATA/.gitattributes" ]; then
		cat > "$DATA/.gitattributes" <<'EOF'
# The graph ledgers are append-only JSONL: on a merge, keep both sides' lines.
graph/*.jsonl merge=union
EOF
	fi
}

restore() {
	ready || return 0
	mkdir -p "$DATA"
	if [ -d "$DATA/.git" ]; then
		log "restore: $DATA is already a backup checkout"
		return 0
	fi
	if [ -n "$(ls -A "$DATA")" ]; then
		# Existing local data and no checkout yet: adopt the folder as the
		# backup only if the backup repo is still empty.
		g init -q -b "$BRANCH"
		g remote add origin "$REMOTE"
		if g ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
			log "BACKUP OFF: $DATA already has data and $REPO already has history. Not merging them automatically. Move one aside and re-run: bash .devcontainer/data-sync.sh restore"
			rm -rf "$DATA/.git"
			return 1
		fi
		write_repo_rules
		log "restore: adopting existing data in $DATA as the first backup"
		return 0
	fi
	log "restore: cloning $REPO into $DATA"
	if ! git -c credential.helper= \
		-c 'credential.helper=!f() { echo username=x-access-token; echo "password=$LH_DATA_TOKEN"; }; f' \
		clone -q "$REMOTE" "$DATA" 2>&1; then
		log "BACKUP OFF: could not clone $REPO. Check that the repo exists and LH_DATA_TOKEN can read it."
		return 1
	fi
	# An empty backup repo clones with no branch yet.
	g symbolic-ref HEAD "refs/heads/$BRANCH"
	write_repo_rules
	log "restore: done"
}

once() {
	ready || return 0
	[ -d "$DATA/.git" ] || { restore || return 0; }
	[ -d "$DATA/.git" ] || return 0
	write_repo_rules
	[ -n "$(g status --porcelain)" ] || return 0
	g add -A
	g commit -q -m "Backup $(date -u +%FT%TZ)" || return 0
	if g push -q origin "HEAD:$BRANCH" 2>&1; then
		log "pushed $(g rev-parse --short HEAD)"
		return 0
	fi
	# Someone else pushed (another codespace, or a manual change): merge and retry.
	log "push rejected; merging remote changes"
	if g pull -q --no-rebase --no-edit origin "$BRANCH" 2>&1 && g push -q origin "HEAD:$BRANCH" 2>&1; then
		log "pushed after merge $(g rev-parse --short HEAD)"
	else
		g merge --abort 2>/dev/null
		log "BACKUP FAILED: could not merge with $REPO. Local data is untouched; resolve by hand in $DATA."
	fi
}

case "${1:-}" in
restore) restore ;;
once) once ;;
loop)
	exec 9>"$LOCK"
	if ! flock -n 9; then
		log "another backup loop is already running"
		exit 0
	fi
	# Secrets only change on a codespace restart, so one notice is enough.
	ready || exit 0
	log "backup loop started: $DATA -> $REPO every ${INTERVAL}s"
	while true; do
		once
		sleep "$INTERVAL"
	done
	;;
*)
	echo "usage: $0 restore|once|loop" >&2
	exit 2
	;;
esac
