#!/usr/bin/env bash
# One-time hardening + Docker for a fresh Vultr server (Ubuntu 24.04). Run as root, in two steps
# (runbook §1.3), from the copied deploy/ folder. Both steps are safe to re-run.
#
#   1. bash server-setup.sh "ssh-ed25519 AAAA... you@mac"
#        packages, user deploy (+ your key), firewall, fail2ban, unattended-upgrades, swap, Docker,
#        app folder, backup timer. SSH is NOT locked down yet: root login still works.
#   2. (from your Mac, in a NEW connection)  ssh deploy@<server-ip>      ← must work
#   3. bash server-setup.sh --lock-ssh
#        refuses unless sshd's log shows a key login as deploy in the last 2 hours; then turns off
#        root login and password login for SSH.
set -euo pipefail

DEPLOY_USER=deploy
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="/home/$DEPLOY_USER/zaypos"

log() { printf '\n==> %s\n' "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root"
. /etc/os-release
[[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]] || die "expected Ubuntu 24.04, found $PRETTY_NAME"

# ---------------------------------------------------------------- step 3: SSH lockdown
if [[ "${1:-}" == --lock-ssh ]]; then
  id "$DEPLOY_USER" > /dev/null 2>&1 || die "user $DEPLOY_USER does not exist: run step 1 first"
  # Proof that the key login works, from sshd itself (not from what someone remembers).
  proof=$(journalctl --since "-2 hours" -t sshd -t sshd-session --no-pager 2>/dev/null \
    | grep -E "Accepted publickey for $DEPLOY_USER from" | tail -n 1 || true)
  [[ -n "$proof" ]] || die "no successful key login as $DEPLOY_USER in the last 2 hours.
  From your Mac, in a new terminal: ssh $DEPLOY_USER@<server-ip>   then run this again.
  Nothing was changed: root and password login still work."
  echo "Key login as $DEPLOY_USER seen: $proof"

  log "SSH: no root login, no passwords, keys only, only $DEPLOY_USER"
  # 00- sorts before cloud-init's 50-cloud-init.conf, and sshd keeps the FIRST value it reads.
  cat > /etc/ssh/sshd_config.d/00-zaypos.conf << EOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $DEPLOY_USER
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
EOF
  if ! sshd -t; then
    rm -f /etc/ssh/sshd_config.d/00-zaypos.conf
    die "sshd config invalid; removed it, nothing restarted"
  fi
  systemctl restart ssh
  sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|allowusers) '
  cat << EOF

SSH locked down. Existing sessions stay open. Check from your Mac, in a NEW terminal:
    ssh $DEPLOY_USER@<server-ip>          (must work)
    ssh root@<server-ip>                  (must be refused)
Locked out anyway? Vultr → the server → "View Console": log in as root with the password from the
Vultr dashboard (the console is not SSH, so it still works), then: rm /etc/ssh/sshd_config.d/00-zaypos.conf && systemctl restart ssh
EOF
  exit 0
fi

# ---------------------------------------------------------------- step 1: everything else
pubkey="${1:-}"
[[ "$pubkey" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\ [A-Za-z0-9+/=]+(\ .*)?$ ]] \
  || die "usage: bash server-setup.sh \"<your SSH public key, e.g. the contents of ~/.ssh/id_ed25519.pub>\"  |  bash server-setup.sh --lock-ssh"

export DEBIAN_FRONTEND=noninteractive

log "Packages"
apt-get update -q
apt-get -y -q -o Dpkg::Options::=--force-confold upgrade
apt-get -y -q install ca-certificates curl gnupg ufw fail2ban unattended-upgrades apt-listchanges

log "User $DEPLOY_USER (SSH key only)"
if ! id "$DEPLOY_USER" > /dev/null 2>&1; then
  adduser --disabled-password --gecos "ZayPOS deploy" "$DEPLOY_USER"
fi
usermod -aG sudo "$DEPLOY_USER"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
auth="/home/$DEPLOY_USER/.ssh/authorized_keys"
touch "$auth"
grep -qxF "$pubkey" "$auth" || echo "$pubkey" >> "$auth"
chown "$DEPLOY_USER:$DEPLOY_USER" "$auth"
chmod 600 "$auth"
if passwd -S "$DEPLOY_USER" | awk '{exit !($2 == "L" || $2 == "NP")}'; then
  if [[ -t 0 ]]; then
    echo "Choose a password for '$DEPLOY_USER'. It is only for sudo, never for SSH (password SSH login"
    echo "gets disabled). Store it in your password manager."
    passwd "$DEPLOY_USER"
  else
    echo "NOTE: no terminal, so no sudo password was set for $DEPLOY_USER. Daily work needs none (docker group)."
    echo "      To allow sudo later: Vultr console as root → passwd $DEPLOY_USER"
  fi
fi

log "Firewall (ufw): 22, 80 and 443 only"
ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp comment 'SSH (rate-limited)'
# Phones connect straight to Caddy (api.zaypos.app is DNS only, not proxied by Cloudflare: Myanmar networks
# cut connections to Cloudflare-proxied hosts). 80 = http→https redirect + Let's Encrypt HTTP-01.
ufw allow 80/tcp comment 'HTTP (Caddy: redirect + ACME)'
ufw allow 443/tcp comment 'HTTPS (Caddy)'
# NOTE: Docker-published ports (Caddy's 80 and 443) bypass ufw; what really filters them is the Vultr
# Firewall group in front of the server (runbook §1.2: 80 and 443 from anywhere).
ufw --force enable
ufw status verbose

log "fail2ban (sshd)"
cat > /etc/fail2ban/jail.d/zaypos.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled = true
backend = systemd
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

log "Unattended security upgrades (reboot if needed at 04:00 Myanmar time = 21:30 UTC)"
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/52zaypos-unattended << 'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "21:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
timedatectl set-timezone UTC
systemctl enable --now unattended-upgrades

log "Swap (2 GB): SQL Server + .NET on 4 GB RAM"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
echo 'vm.swappiness=10' > /etc/sysctl.d/90-zaypos.conf
sysctl -q --system

log "Docker (official repository)"
if ! command -v docker > /dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get -y -q install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
# Default log rotation for every container (compose also sets it per service).
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "5" },
  "live-restore": true
}
EOF
systemctl enable docker
systemctl restart docker
# NOTE: the docker group is root-equivalent. Only the deploy user is in it.
usermod -aG docker "$DEPLOY_USER"

log "App folder $APP_DIR"
install -d -m 750 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR" "$APP_DIR/backups"
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APP_DIR/caddy-data"   # Caddy's Let's Encrypt account + certificates
for f in docker-compose.prod.yml Caddyfile lib.sh release.sh backup.sh restore.sh .env.example; do
  install -m 640 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$HERE/$f" "$APP_DIR/$f"
done
chmod 750 "$APP_DIR"/*.sh

log "Nightly backup timer"
install -m 644 "$HERE/systemd/zaypos-backup.service" /etc/systemd/system/zaypos-backup.service
install -m 644 "$HERE/systemd/zaypos-backup.timer" /etc/systemd/system/zaypos-backup.timer
systemctl daemon-reload
systemctl enable --now zaypos-backup.timer
systemctl list-timers zaypos-backup.timer --no-pager

cat << EOF

Step 1 done. SSH is NOT locked down yet. Next:
  1. From your Mac, in a NEW terminal:  ssh $DEPLOY_USER@<server-ip>     (must work)
  2. Back here as root:                 bash $HERE/server-setup.sh --lock-ssh
EOF
