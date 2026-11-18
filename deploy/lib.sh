# Shared helpers for release.sh, backup.sh and restore.sh (sourced, not run). Server side only.
# shellcheck shell=bash

ZAYPOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034 # used by the scripts that source this file
DB_NAME=ZayPOS

log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

# Loads .env into this shell (exported, so `docker run -e NAME` can pass values without
# putting them on the command line).
load_env() {
  local env="$ZAYPOS_DIR/.env"
  [[ -f "$env" ]] || die "$env is missing. Copy deploy/.env.example there and fill it in (runbook §1)."
  local mode
  mode=$(stat -c '%a' "$env")
  [[ "$mode" == "600" || "$mode" == "400" ]] || die "$env must be chmod 600 (is $mode)."
  set -a
  # shellcheck disable=SC1090
  source "$env"
  set +a
  export DEPLOY_UID DEPLOY_GID
  DEPLOY_UID=$(id -u)
  DEPLOY_GID=$(id -g)
}

dc() { docker compose --project-directory "$ZAYPOS_DIR" -f "$ZAYPOS_DIR/docker-compose.prod.yml" "$@"; }

# Runs T-SQL as sa inside the SQL Server container. The password is read from the container's
# own environment, so it never shows up in `ps` on the host.
sql() {
  # shellcheck disable=SC2016 # single quotes on purpose: expanded inside the container
  dc exec -T mssql sh -c 'SQLCMDPASSWORD="$MSSQL_SA_PASSWORD" exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b "$@"' sqlcmd "$@"
}

mssql_running() { [[ -n "$(dc ps --status running -q mssql 2>/dev/null)" ]]; }

wait_healthy() { # <service> <seconds>
  local svc=$1 limit=$2 id status restarts first_id="" base=0
  for ((i = 0; i < limit; i += 3)); do
    id=$(dc ps -a -q "$svc")
    status=$([[ -n "$id" ]] && docker inspect -f '{{.State.Health.Status}}' "$id" 2>/dev/null || echo missing)
    [[ "$status" == healthy ]] && return 0
    # Crash loop (e.g. "Unsafe production configuration", pending migrations): give up now, not after
    # $limit s. Counted from the start of this wait (the same container may have restarted before).
    restarts=$([[ -n "$id" ]] && docker inspect -f '{{.RestartCount}}' "$id" 2>/dev/null || echo 0)
    if [[ "$id" != "$first_id" ]]; then first_id=$id; base=$restarts; fi
    if ((restarts - base >= 2)); then
      log "$svc keeps exiting (restarted $((restarts - base)) times in ${i}s)"
      return 1
    fi
    sleep 3
  done
  return 1
}

# aws-cli in a throw-away container, pointed at Cloudflare R2 with the backup token.
r2() {
  : "${R2_ACCOUNT_ID:?set in .env}" "${R2_BACKUP_BUCKET:?set in .env}"
  AWS_ACCESS_KEY_ID="${R2_BACKUP_ACCESS_KEY_ID:?set in .env}" \
  AWS_SECRET_ACCESS_KEY="${R2_BACKUP_SECRET_ACCESS_KEY:?set in .env}" \
  docker run --rm -i \
    -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY \
    -e AWS_DEFAULT_REGION=auto \
    -e AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
    -e AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
    -v "$ZAYPOS_DIR/backups:/backups" \
    amazon/aws-cli --endpoint-url "${R2_ENDPOINT:-https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com}" "$@"
}

# shellcheck disable=SC2034
R2_PREFIX=zaypos
