#!/usr/bin/env bash
# Full backup of the ZayPOS database → verified → gzip → Cloudflare R2. Run nightly by
# zaypos-backup.timer and before every release. Keeps BACKUP_RETENTION_DAYS (30) on R2
# (never fewer than the 7 newest) and 3 days locally in ./backups.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env

exec 9> "$ZAYPOS_DIR/backups/.lock"
flock -n 9 || die "another backup is running"

mssql_running || die "SQL Server is not running"
ts=$(date -u +%Y%m%dT%H%M%SZ)
name="zaypos-$ts.bak"
inside="/var/opt/mssql/backup/$name"
local_file="$ZAYPOS_DIR/backups/$name.gz"
key="$R2_PREFIX/$name.gz"

cleanup() { dc exec -T mssql rm -f "$inside" > /dev/null 2>&1 || true; }
trap cleanup EXIT

log "Backing up $DB_NAME → $name"
dc exec -T mssql mkdir -p /var/opt/mssql/backup
# Express has no backup compression: gzip below. CHECKSUM: detect page corruption now, not at restore.
sql -Q "SET NOCOUNT ON; BACKUP DATABASE [$DB_NAME] TO DISK = N'$inside' WITH INIT, CHECKSUM, STATS = 50;"
sql -Q "SET NOCOUNT ON; RESTORE VERIFYONLY FROM DISK = N'$inside' WITH CHECKSUM;"

dc exec -T mssql cat "$inside" | gzip -6 > "$local_file.part"
gzip -t "$local_file.part"
mv "$local_file.part" "$local_file"
size=$(du -h "$local_file" | cut -f1)
log "Compressed: $local_file ($size)"

r2 s3 cp "/backups/$name.gz" "s3://$R2_BACKUP_BUCKET/$key" --only-show-errors
r2 s3api head-object --bucket "$R2_BACKUP_BUCKET" --key "$key" > /dev/null
log "Uploaded: r2://$R2_BACKUP_BUCKET/$key"

# --- retention on R2: delete older than N days, but always keep the 7 newest ---
days="${BACKUP_RETENTION_DAYS:-30}"
cutoff=$(date -u -d "-$days days" +%Y%m%dT%H%M%SZ)
mapfile -t keys < <(r2 s3 ls "s3://$R2_BACKUP_BUCKET/$R2_PREFIX/" | awk '{print $4}' | grep -E '^zaypos-[0-9]{8}T[0-9]{6}Z\.bak\.gz$' | sort -r)
for ((i = 7; i < ${#keys[@]}; i++)); do
  k=${keys[$i]}
  stamp=${k#zaypos-}; stamp=${stamp%.bak.gz}
  if [[ "$stamp" < "$cutoff" ]]; then
    r2 s3 rm "s3://$R2_BACKUP_BUCKET/$R2_PREFIX/$k" --only-show-errors
    log "Pruned r2://$R2_BACKUP_BUCKET/$R2_PREFIX/$k"
  fi
done

# --- local copies: 3 days ---
find "$ZAYPOS_DIR/backups" -maxdepth 1 -name 'zaypos-*.bak.gz' -mtime +2 -print -delete | sed 's/^/removed local /'

if [[ -n "${BACKUP_PING_URL:-}" ]]; then
  curl -fsS -m 10 --retry 3 "$BACKUP_PING_URL" > /dev/null || log "warning: BACKUP_PING_URL ping failed"
fi
log "Backup OK: $key"
