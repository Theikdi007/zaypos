#!/usr/bin/env bash
# Run on your Mac from the repo: build the API image for the droplet (linux/amd64), upload it
# over SSH (no registry needed), copy the deploy files, and run release.sh on the server.
#   deploy/deploy.sh deploy@<droplet-ip>
# The image tag is the git commit, so the tree must be committed (ALLOW_DIRTY=1 to override).
set -euo pipefail

target="${1:-}"
[[ "$target" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9.:-]+$ ]] || { echo "usage: deploy/deploy.sh deploy@<droplet-ip>" >&2; exit 2; }
cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain -- backend deploy)" && "${ALLOW_DIRTY:-0}" != 1 ]]; then
  echo "backend/ or deploy/ has uncommitted changes: commit first (the image tag is the commit)." >&2
  git status --short -- backend deploy >&2
  exit 1
fi
tag=$(git rev-parse --short=12 HEAD)
[[ -z "$(git status --porcelain -- backend deploy)" ]] || tag="$tag-dirty-$(date +%s)"

echo "==> Building zaypos-api:$tag (linux/amd64)"
docker buildx build --platform linux/amd64 -t "zaypos-api:$tag" --load backend

echo "==> Copying deploy files to $target:zaypos/"
ssh "$target" 'mkdir -p zaypos/certs zaypos/backups && chmod 700 zaypos/certs'
scp -q deploy/docker-compose.prod.yml deploy/Caddyfile deploy/lib.sh deploy/release.sh \
  deploy/backup.sh deploy/restore.sh deploy/.env.example "$target:zaypos/"
ssh "$target" 'chmod +x zaypos/*.sh'

if ssh "$target" "docker image inspect zaypos-api:$tag > /dev/null 2>&1"; then
  echo "==> Image already on the server"
else
  echo "==> Uploading image (about 100 MB compressed)"
  docker save "zaypos-api:$tag" | gzip -1 | ssh "$target" 'gunzip | docker load'
fi

echo "==> Releasing on the server"
ssh "$target" "cd zaypos && ./release.sh '$tag'"

echo "==> Public check"
if curl -fsS -m 15 "https://${API_DOMAIN:-api.zaypos.app}/health"; then
  echo
  echo "Deployed zaypos-api:$tag"
else
  echo "https://${API_DOMAIN:-api.zaypos.app}/health did not answer 200: see runbook §6 (troubleshooting)." >&2
  exit 1
fi
