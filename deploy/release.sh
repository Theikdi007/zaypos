#!/usr/bin/env bash
# Server side: switch the running API to an image tag that is already loaded (deploy.sh loads it).
#   ./release.sh <tag>       deploy that tag: backup → migrate → api → caddy
#   ./release.sh previous    roll back to the tag before the current one (releases.log)
# Every step stops on error; the old API keeps running until the new one is ready to start.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
load_env

[[ $# -eq 1 ]] || die "usage: ./release.sh <tag> | ./release.sh previous"
current="${API_TAG:-}"
tag="$1"
if [[ "$tag" == previous ]]; then
  [[ -f "$ZAYPOS_DIR/releases.log" ]] || die "no releases.log yet: nothing to roll back to"
  # Last line: "<time> <from> -> <to>". Roll back to <from>.
  tag=$(tail -n 1 "$ZAYPOS_DIR/releases.log" | awk '{print $2}')
  [[ -n "$tag" && "$tag" != "-" ]] || die "releases.log has no previous tag"
  log "Rolling back: $current -> $tag"
fi
[[ "$tag" =~ ^[A-Za-z0-9._-]+$ ]] || die "bad tag '$tag'"
docker image inspect "zaypos-api:$tag" > /dev/null 2>&1 \
  || die "image zaypos-api:$tag is not on this server. Run deploy/deploy.sh from your Mac (it uploads the image)."

for f in origin.pem origin.key cloudflare-origin-pull-ca.pem; do
  [[ -s "$ZAYPOS_DIR/certs/$f" ]] || die "certs/$f is missing (runbook §1.4)"
done

# 1. Safety backup before touching the schema (not on the very first deploy: no database yet).
if [[ "${SKIP_BACKUP:-0}" == 1 ]]; then
  log "1/5 Backup skipped (SKIP_BACKUP=1)"
elif ! mssql_running; then
  log "1/5 Backup skipped (SQL Server not running yet: first deploy)"
else
  log "1/5 Backup before deploy"
  "$ZAYPOS_DIR/backup.sh" || die "pre-deploy backup failed: nothing changed. (SKIP_BACKUP=1 ./release.sh $tag to deploy anyway)"
fi

# 2. Point .env at the new tag (compose reads API_TAG from it).
sed -i "s/^API_TAG=.*/API_TAG=$tag/" "$ZAYPOS_DIR/.env"
grep -q "^API_TAG=$tag\$" "$ZAYPOS_DIR/.env" || die ".env has no API_TAG= line (copy it from .env.example)"
export API_TAG="$tag"

log "2/5 SQL Server"
dc up -d mssql
wait_healthy mssql 180 || die "SQL Server is not healthy: docker compose logs mssql"

# 3. Migrations (+ the API login) with the NEW image, before the new API starts.
log "3/5 Migrations"
if ! dc run --rm migrate; then
  sed -i "s/^API_TAG=.*/API_TAG=$current/" "$ZAYPOS_DIR/.env"
  die "migrate failed; API_TAG reset to '$current', the running API was not touched."
fi

# 4. API (--no-deps: migrate already ran). The old container is replaced only now.
log "4/5 API zaypos-api:$tag"
dc up -d --no-deps api
if ! wait_healthy api 120; then
  dc logs --tail 60 api >&2 || true
  [[ -n "$current" ]] || die "API $tag is not healthy (logs above)."
  log "API $tag is not healthy (logs above): putting $current back"
  sed -i "s/^API_TAG=.*/API_TAG=$current/" "$ZAYPOS_DIR/.env"
  API_TAG="$current" dc up -d --no-deps api
  if wait_healthy api 120; then
    die "rolled back to $current (healthy). Fix $tag and deploy again."
  fi
  die "rolled back to $current but it is not healthy either: docker compose logs api"
fi

log "5/5 Caddy"
dc up -d --no-deps caddy

printf '%s %s -> %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${current:--}" "$tag" >> "$ZAYPOS_DIR/releases.log"
log "Released zaypos-api:$tag (was ${current:-none})."

# Keep the 5 newest API images for rollbacks.
docker image ls zaypos-api --format '{{.CreatedAt}}\t{{.Tag}}' | sort -r | awk 'NR > 5 {print $NF}' |
  while read -r old; do
    [[ "$old" == "$tag" || "$old" == "$current" ]] && continue
    docker image rm "zaypos-api:$old" > /dev/null 2>&1 && log "removed old image zaypos-api:$old" || true
  done
