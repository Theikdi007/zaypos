#!/usr/bin/env bash
# Run on your Mac from the repo: build the API image for the server (linux/amd64), upload it
# over SSH (no registry needed), copy the deploy files, and run release.sh on the server.
#   deploy/deploy.sh deploy@<server-ip>              deploy the current commit
#   deploy/deploy.sh deploy@<server-ip> --dry-run    change nothing: check the server, show which deploy
#                                                    files differ, which release runs now, and that only
#                                                    ONE SSH connection is used
# The image tag is the git commit, so the tree must be committed (ALLOW_DIRTY=1 to override).
#
# All ssh/scp calls share ONE connection (ControlMaster): the server's ufw allows only 6 new SSH
# connections per 30 s from one IP, and a deploy needs about 6 calls.
set -euo pipefail

target="${1:-}"
mode="${2:-}"
[[ "$target" =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9.:-]+$ && ( -z "$mode" || "$mode" == --dry-run ) ]] \
  || { echo "usage: deploy/deploy.sh deploy@<server-ip> [--dry-run]" >&2; exit 2; }
dry=0; [[ "$mode" == --dry-run ]] && dry=1
cd "$(dirname "$0")/.."

files=(deploy/docker-compose.prod.yml deploy/Caddyfile deploy/lib.sh deploy/release.sh
       deploy/backup.sh deploy/restore.sh deploy/.env.example)
domain="${API_DOMAIN:-api.zaypos.app}"

# --- one shared SSH connection ---------------------------------------------------------------
# %C = hash of user/host/port: short enough for macOS's 104-byte socket path limit.
ssh_opts=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/zaypos-%C" -o ControlPersist=120
          -o ServerAliveInterval=30 -o ConnectTimeout=15)
remote() { ssh "${ssh_opts[@]}" "$target" "$@"; }
copy() { scp -q "${ssh_opts[@]}" "$@"; }
master_pid() { ssh "${ssh_opts[@]}" -O check "$target" 2>&1 | sed -n 's/.*pid=\([0-9]*\).*/\1/p'; }
close_master() { ssh "${ssh_opts[@]}" -O exit "$target" > /dev/null 2>&1 || true; }
trap close_master EXIT

# Open it now (one TCP connection, one login); every later call reuses it.
close_master # a stale socket from an aborted run must not be reused
remote true || { echo "cannot log in as $target (key? rate limit: wait a minute)" >&2; exit 1; }
pid=$(master_pid)
[[ -n "$pid" ]] || { echo "SSH connection sharing did not start (ControlMaster)" >&2; exit 1; }
echo "==> SSH: one shared connection to $target (pid $pid)"

same_connection() { # fail loudly if a call opened its own connection
  [[ "$(master_pid)" == "$pid" ]] || { echo "SSH connection sharing broke (master pid changed)" >&2; exit 1; }
}

# --- version --------------------------------------------------------------------------------
if [[ -n "$(git status --porcelain -- backend deploy)" && "${ALLOW_DIRTY:-0}" != 1 && $dry == 0 ]]; then
  echo "backend/ or deploy/ has uncommitted changes: commit first (the image tag is the commit)." >&2
  git status --short -- backend deploy >&2
  exit 1
fi
tag=$(git rev-parse --short=12 HEAD)
[[ -z "$(git status --porcelain -- backend deploy)" ]] || tag="$tag-dirty-$(date +%s)"

if ((dry)); then
  echo "==> DRY RUN for zaypos-api:$tag: nothing is built, copied, uploaded or released"
  remote 'test -f zaypos/.env && test -d zaypos/certs && echo "    server: zaypos/.env and zaypos/certs/ present"'
  # Copy the deploy files to a throw-away folder (exercises scp on the shared connection) and compare.
  tmp=$(remote 'mktemp -d zaypos-dryrun.XXXXXX')
  copy "${files[@]}" "$target:$tmp/"
  remote "cd '$tmp' && for f in *.sh *.yml Caddyfile .env.example; do
            if cmp -s \"\$f\" \"../zaypos/\$f\"; then echo \"    same     \$f\"; else echo \"    CHANGED  \$f (would be replaced)\"; fi
          done; cd && rm -rf '$tmp'"
  same_connection
  if remote "docker image inspect zaypos-api:$tag > /dev/null 2>&1"; then
    echo "    image zaypos-api:$tag is already on the server (no upload needed)"
  else
    echo "    image zaypos-api:$tag is not on the server: a deploy would build and upload it (~100 MB)"
  fi
  remote 'echo "    running now: $(grep -m1 "^API_TAG=" zaypos/.env | cut -d= -f2)"; echo "    last releases:"; tail -n 3 zaypos/releases.log 2>/dev/null | sed "s/^/      /"'
  same_connection
  printf '    public health: '
  curl -fsS -m 15 "https://$domain/health" || echo "NOT OK"
  echo
  # Proof: this machine has exactly one TCP connection to the server's SSH port, the shared one.
  host=${target#*@}
  conns=$(lsof -nP -a -p "$pid" -iTCP@"$host":22 -sTCP:ESTABLISHED 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
  echo "==> DRY RUN OK: every ssh/scp call above went over $conns TCP connection(s) (master pid $pid, unchanged)"
  [[ "$conns" == 1 ]] || exit 1
  exit 0
fi

echo "==> Building zaypos-api:$tag (linux/amd64)"
docker buildx build --platform linux/amd64 -t "zaypos-api:$tag" --load backend

echo "==> Copying deploy files to $target:zaypos/"
remote 'mkdir -p zaypos/certs zaypos/backups && chmod 700 zaypos/certs'
copy "${files[@]}" "$target:zaypos/"
remote 'chmod +x zaypos/*.sh'

if remote "docker image inspect zaypos-api:$tag > /dev/null 2>&1"; then
  echo "==> Image already on the server"
else
  echo "==> Uploading image (about 100 MB compressed)"
  docker save "zaypos-api:$tag" | gzip -1 | remote 'gunzip | docker load'
fi
same_connection

echo "==> Releasing on the server"
remote "cd zaypos && ./release.sh '$tag'"

echo "==> Public check"
if curl -fsS -m 15 "https://$domain/health"; then
  echo
  echo "Deployed zaypos-api:$tag"
else
  echo "https://$domain/health did not answer 200: see runbook §6 (troubleshooting)." >&2
  exit 1
fi
