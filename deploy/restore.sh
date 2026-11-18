#!/usr/bin/env bash
# Restore a backup from R2 (or ./backups) into a SEPARATE database for a restore test.
#   ./restore.sh list                         backups on R2, newest first
#   ./restore.sh latest [db]                  newest backup  → db (default ZayPOS_restoretest)
#   ./restore.sh zaypos-<stamp>.bak.gz [db]   that backup    → db
#   ./restore.sh drop [db]                    delete the test database again
# The production database (ZayPOS) is refused here: see runbook §5 for a real restore.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env

cmd="${1:-}"
target="${2:-ZayPOS_restoretest}"
[[ "$target" =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] || die "bad database name '$target'"
if [[ "${target,,}" == "${DB_NAME,,}" && "${ZAYPOS_RESTORE_PRODUCTION:-}" != "I understand" ]]; then
  die "refusing to restore over the production database $DB_NAME. Restore tests go to another name (default ZayPOS_restoretest)."
fi
mssql_running || die "SQL Server is not running"

list_r2() {
  r2 s3 ls "s3://$R2_BACKUP_BUCKET/$R2_PREFIX/" | awk '{print $4}' | grep -E '^zaypos-[0-9]{8}T[0-9]{6}Z\.bak\.gz$' | sort -r
}

case "$cmd" in
  list)
    list_r2
    exit 0
    ;;
  drop)
    [[ "${target,,}" != "${DB_NAME,,}" ]] || die "will not drop $DB_NAME"
    sql -Q "IF DB_ID(N'$target') IS NOT NULL BEGIN ALTER DATABASE [$target] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$target]; END"
    log "Dropped $target"
    exit 0
    ;;
  latest)
    file=$(list_r2 | head -n 1)
    [[ -n "$file" ]] || die "no backups found on r2://$R2_BACKUP_BUCKET/$R2_PREFIX/"
    ;;
  zaypos-*.bak.gz)
    file="$cmd"
    [[ "$file" =~ ^zaypos-[0-9]{8}T[0-9]{6}Z\.bak\.gz$ ]] || die "bad backup name '$file'"
    ;;
  *)
    sed -n '2,7p' "$0"
    exit 2
    ;;
esac

# 1. Get the file (local copy if we still have it, else download from R2).
if [[ -s "$ZAYPOS_DIR/backups/$file" ]]; then
  log "Using local backups/$file"
else
  log "Downloading r2://$R2_BACKUP_BUCKET/$R2_PREFIX/$file"
  r2 s3 cp "s3://$R2_BACKUP_BUCKET/$R2_PREFIX/$file" "/backups/$file" --only-show-errors
fi
gzip -t "$ZAYPOS_DIR/backups/$file" || die "$file is corrupt (gzip test failed)"

# 2. Copy into the SQL Server container (decompressed).
inside="/var/opt/mssql/backup/restore-$$.bak"
cleanup() { dc exec -T mssql rm -f "$inside" > /dev/null 2>&1 || true; }
trap cleanup EXIT
dc exec -T mssql mkdir -p /var/opt/mssql/backup
gunzip -c "$ZAYPOS_DIR/backups/$file" | dc exec -T mssql sh -c "cat > '$inside'"

# 3. Logical file names from the backup, then RESTORE ... WITH MOVE to new files.
mapfile -t files < <(sql -h -1 -W -s '|' -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'$inside';" | awk -F'|' 'NF > 2 {print $1 "|" $3}')
moves=""
for f in "${files[@]}"; do
  logical=${f%%|*}; type=${f##*|}
  case "$type" in
    D) moves+="MOVE N'$logical' TO N'/var/opt/mssql/data/${target}.mdf', " ;;
    L) moves+="MOVE N'$logical' TO N'/var/opt/mssql/data/${target}_log.ldf', " ;;
    *) die "unexpected file type '$type' in backup" ;;
  esac
done
[[ -n "$moves" ]] || die "could not read the file list from $file"

log "Restoring $file → $target"
sql -Q "IF DB_ID(N'$target') IS NOT NULL ALTER DATABASE [$target] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
        RESTORE DATABASE [$target] FROM DISK = N'$inside' WITH ${moves} REPLACE, CHECKSUM, RECOVERY, STATS = 25;
        ALTER DATABASE [$target] SET MULTI_USER;"

# 4. Prove it is usable: integrity check + what is in it.
log "DBCC CHECKDB($target)"
sql -Q "DBCC CHECKDB([$target]) WITH NO_INFOMSGS, ALL_ERRORMSGS;"
log "Contents of $target:"
sql -d "$target" -W -Q "SET NOCOUNT ON;
  SELECT (SELECT COUNT(*) FROM dbo.Tenants)  AS Shops,
         (SELECT COUNT(*) FROM dbo.Devices)  AS Devices,
         (SELECT COUNT(*) FROM dbo.Products) AS Products,
         (SELECT COUNT(*) FROM dbo.Customers) AS Customers,
         (SELECT COUNT(*) FROM dbo.Sales)    AS Sales,
         (SELECT CONVERT(varchar(19), MAX(CreatedAt), 126) FROM dbo.Sales) AS LastSaleUtc;
  SELECT TOP (1) MigrationId AS LastMigration FROM dbo.__EFMigrationsHistory ORDER BY MigrationId DESC;"
log "Restore test OK. Compare the numbers with production, then: ./restore.sh drop $target"
