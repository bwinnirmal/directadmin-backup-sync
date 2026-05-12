#!/usr/bin/env bash
# ============================================================
#  da-sync.sh — DirectAdmin Backup → SFTP Sync
#  Built by HostRainbow (https://hostrainbow.in)
#
#  What it does:
#    1. Finds today's DA backup folder
#    2. Uploads all archives to remote SFTP
#    3. Deletes old local/remote backup folders (retention)
#
#  Requirements:
#    - sshpass  (yum install sshpass -y)
#    - sftp     (included in openssh-clients)
#
#  Setup:
#    1. Edit the CONFIG section below
#    2. chmod +x da-sync.sh
#    3. Test:  bash da-sync.sh --dry-run
#    4. Cron:  45 3 * * * root bash /opt/da-sync/da-sync.sh
# ============================================================

# ============================================================
#  CONFIG — edit these values
# ============================================================

# Base path where DirectAdmin stores backups
# Found in DA Admin Panel → Admin Backup and Restore → Where
DA_BACKUP_BASE="/home/your-da-admin-user/admin_backups"

# Folder format — must match your DA "Where" setting exactly:
#
#   DA Panel Option       Set this value
#   ─────────────────────────────────────
#   Nothing (flat)      → nothing
#   Day of Week         → dow          (creates .../Monday)
#   Day of Month        → dom          (creates .../11)
#   Week of Month       → wom          (creates .../week-3)
#   Month               → month        (creates .../May)
#   Full Date           → fulldate     (creates .../2026-05-12)
#
DA_FOLDER_FORMAT="fulldate"

# SFTP destination credentials
# Works with Hetzner Storage Box, any SFTP server, or VPS
# IMPORTANT: Always use single quotes for SFTP_PASS
#            Double quotes will break passwords containing $ ! @ and other special chars
SFTP_HOST="uXXXXXX.your-storagebox.de"
SFTP_PORT="23"
SFTP_USER="uXXXXXX"
SFTP_PASS='your-sftp-password'

# Remote base path on SFTP server
# Use / or leave empty if using a Storage Box subuser
# (subuser root IS their allowed folder)
# Use a path like "backups/directadmin" for full accounts
REMOTE_PATH="/"

# Retention: how many daily backup folders to keep
KEEP_LOCAL=7     # local server  — 7 days
KEEP_REMOTE=14   # remote SFTP   — 14 days

# Log file path
LOG_FILE="/var/log/da-sync.log"

# ============================================================
#  END CONFIG — do not edit below this line
# ============================================================

set -uo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

TMPBATCH=$(mktemp /tmp/da-sync-batch.XXXXXX)
trap 'rm -f "$TMPBATCH"' EXIT

# ── Dependency check ──────────────────────────────────────────
command -v sshpass &>/dev/null || die "sshpass not installed. Run: yum install sshpass -y"
command -v sftp    &>/dev/null || die "sftp not found. Run: yum install openssh-clients -y"

# ── Resolve today's DA backup folder ─────────────────────────
case "${DA_FOLDER_FORMAT,,}" in
  nothing|none|"") BACKUP_DIR="${DA_BACKUP_BASE}" ;;
  dow)             BACKUP_DIR="${DA_BACKUP_BASE}/$(date +%A)" ;;
  dom)             BACKUP_DIR="${DA_BACKUP_BASE}/$(date +%-d)" ;;
  wom)             BACKUP_DIR="${DA_BACKUP_BASE}/week-$(( ($(date +%-d)-1)/7+1 ))" ;;
  month)           BACKUP_DIR="${DA_BACKUP_BASE}/$(date +%B)" ;;
  fulldate|*)      BACKUP_DIR="${DA_BACKUP_BASE}/$(date +%Y-%m-%d)" ;;
esac

FOLDER_NAME="$(basename "$BACKUP_DIR")"

# Build remote directory path
if [[ -z "${REMOTE_PATH}" || "${REMOTE_PATH}" == "/" ]]; then
  REMOTE_DIR="${FOLDER_NAME}"
else
  REMOTE_DIR="${REMOTE_PATH%/}/${FOLDER_NAME}"
fi

# ── Sanity checks ─────────────────────────────────────────────
[[ -d "$BACKUP_DIR" ]] || die "Backup folder not found: $BACKUP_DIR — DA may not have finished yet."

mapfile -t FILES < <(find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name "*.tar.gz" -o -name "*.tar.bz2" -o -name "*.tar.zst" -o -name "*.zip" \) | sort)

[[ ${#FILES[@]} -gt 0 ]] || die "No archive files found in $BACKUP_DIR"

# ── SFTP batch helper ─────────────────────────────────────────
# Uses sftp -b (batch file) — the reliable way to pass
# multiple sftp commands without heredoc/newline issues
sftp_batch() {
  > "$TMPBATCH"
  for line in "$@"; do
    echo "$line" >> "$TMPBATCH"
  done
  sshpass -p "${SFTP_PASS}" sftp \
    -o StrictHostKeyChecking=no \
    -o BatchMode=no \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -P "${SFTP_PORT}" \
    -b "${TMPBATCH}" \
    "${SFTP_USER}@${SFTP_HOST}" >> "$LOG_FILE" 2>&1
}

# ── Start ─────────────────────────────────────────────────────
log "========================================"
log "da-sync.sh — HostRainbow (hostrainbow.in)"
log "DRY_RUN : $DRY_RUN"
log "Source  : $BACKUP_DIR"
log "Remote  : ${SFTP_HOST}:${REMOTE_DIR}"
log "Files   : ${#FILES[@]}"
$DRY_RUN && log "DRY-RUN mode — no files will be transferred or deleted"

SYNCED=0; SKIPPED=0; ERRORS=0

# Create remote dated folder once (- prefix tells sftp to ignore errors)
if ! $DRY_RUN; then
  sftp_batch "-mkdir ${REMOTE_DIR}" || true
fi

# ── Upload loop ───────────────────────────────────────────────
for FILE in "${FILES[@]}"; do
  FNAME="$(basename "$FILE")"
  FSIZE="$(du -sh "$FILE" 2>/dev/null | cut -f1)"
  MARKER="${FILE}.synced"

  # Skip files already successfully uploaded in a previous run
  if [[ -f "$MARKER" ]]; then
    log "SKIP (already synced): $FNAME"
    SKIPPED=$(( SKIPPED + 1 )); continue
  fi

  log "UPLOAD: $FNAME ($FSIZE)"

  if $DRY_RUN; then
    log "DRY-RUN: would upload $FNAME → ${REMOTE_DIR}/${FNAME}"
    SYNCED=$(( SYNCED + 1 )); continue
  fi

  if sftp_batch "put ${FILE} ${REMOTE_DIR}/${FNAME}"; then
    touch "$MARKER"
    log "OK: $FNAME"
    SYNCED=$(( SYNCED + 1 ))
  else
    log "FAILED: $FNAME — will retry on next run"
    ERRORS=$(( ERRORS + 1 ))
  fi
done

# ── Local retention ───────────────────────────────────────────
log "--- Local retention: keeping $KEEP_LOCAL most recent ---"
if ! $DRY_RUN; then
  if [[ "${DA_FOLDER_FORMAT,,}" == "nothing" || "${DA_FOLDER_FORMAT,,}" == "none" ]]; then
    find "$DA_BACKUP_BASE" -maxdepth 1 -type f \
      \( -name "*.tar.gz" -o -name "*.tar.zst" \) -printf '%T@ %p\n' \
      | sort -n | head -n "-${KEEP_LOCAL}" | awk '{print $2}' \
      | while read -r F; do
          log "DELETE local: $F"
          rm -f "$F" "${F}.synced"
        done
  else
    find "$DA_BACKUP_BASE" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %p\n' \
      | sort -n | head -n "-${KEEP_LOCAL}" | awk '{print $2}' \
      | while read -r D; do
          log "DELETE local folder: $D"
          rm -rf "$D"
        done
  fi
fi

# ── Remote retention ──────────────────────────────────────────
log "--- Remote retention: keeping $KEEP_REMOTE most recent ---"
if ! $DRY_RUN; then
  LS_PATH=$([ "${REMOTE_DIR}" = "${FOLDER_NAME}" ] && echo "." || echo "${REMOTE_DIR%/*}")

  REMOTE_LIST=$(sftp_batch "ls ${LS_PATH}" 2>/dev/null \
    | grep -v '^sftp>' | grep -v '^$' | sort || true)

  COUNT=$(echo "$REMOTE_LIST" | grep -c '[^[:space:]]' || true)

  if [[ "$COUNT" -gt "$KEEP_REMOTE" ]]; then
    DELETE_COUNT=$(( COUNT - KEEP_REMOTE ))
    echo "$REMOTE_LIST" | head -n "$DELETE_COUNT" | while IFS= read -r DIR; do
      [[ -z "$DIR" ]] && continue
      DELPATH=$([ "${LS_PATH}" = "." ] && echo "${DIR}" || echo "${LS_PATH}/${DIR}")
      log "DELETE remote: ${DELPATH}"
      sftp_batch "rm ${DELPATH}/*" "rmdir ${DELPATH}" || true
    done
  else
    log "Remote has $COUNT folder(s) — no cleanup needed"
  fi
fi

# ── Summary ───────────────────────────────────────────────────
log "========================================"
log "Done — Synced: $SYNCED | Skipped: $SKIPPED | Errors: $ERRORS"
log "========================================"

[[ $ERRORS -gt 0 ]] && exit 1
exit 0
