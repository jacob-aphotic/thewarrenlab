#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/14-bash-history.sh — Lapin Logistics — shell history
# =============================================================================
# Plants .bash_history for peter and roger with ordinary day-to-day commands.
#
# AUTHORITATIVE OWNER of:
#   /home/peter/.bash_history   (03-ftp does NOT write it — this module owns it)
#   /home/roger/.bash_history   (0600 roger:roger)
#
# DRY-RUN SAFE: every write is is_dry_run-gated; nothing is written in dry-run.
# IDEMPOTENT:   authoritative OVERWRITE each run — never appended, so re-runs
#               never duplicate lines or drift.
# GRACEFUL:     if peter/roger do not exist yet (standalone run before
#               01-users) -> warn and SKIP that user (do NOT die).
# =============================================================================
set -euo pipefail

LAPIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
# shellcheck source=../lib/common.sh
source "$LAPIN_LIB_DIR/common.sh"
# shellcheck source=../lib/pkg.sh
source "$LAPIN_LIB_DIR/pkg.sh"
# shellcheck source=../lib/distro.sh
source "$LAPIN_LIB_DIR/distro.sh"

require_root

log "14-bash-history: planting .bash_history for peter + roger"

# ---------------------------------------------------------------------------
# _plant_history <user> -- authoritative overwrite, 0600, owned <user>:<user>.
# Home dir + histfile path are resolved internally via getent. Reads the
# history body from stdin. Graceful skip if the user is absent. Dry-run inert.
# ---------------------------------------------------------------------------
_plant_history() {
    local user="$1" home histfile
    if ! id "$user" >/dev/null 2>&1; then
        warn "14-bash-history: user '${user}' does not exist (run 01-users.sh first) — skipping ${user}'s .bash_history"
        # Drain stdin so the heredoc feeding us doesn't error on a closed pipe.
        cat >/dev/null 2>&1 || true
        return 0
    fi
    home="$(getent passwd "$user" | cut -d: -f6)"
    if [[ -z "$home" || ! -d "$home" ]]; then
        warn "14-bash-history: home dir for '${user}' missing ('${home:-unset}') — skipping ${user}'s .bash_history"
        cat >/dev/null 2>&1 || true
        return 0
    fi
    histfile="${home}/.bash_history"
    if is_dry_run; then
        cat >/dev/null 2>&1 || true
        log "[DRY-RUN] would authoritatively overwrite ${histfile} (mode 0600, ${user}:${user})"
        return 0
    fi
    # Authoritative overwrite — never append.
    cat > "$histfile"
    chown "${user}:${user}" "$histfile"
    chmod 0600 "$histfile"
    log "14-bash-history: wrote ${histfile} ($(wc -l < "$histfile") lines, mode 0600, ${user}:${user})"
}

# ===========================================================================
# peter — ordinary day-to-day shell activity.
# ===========================================================================
_plant_history peter <<'PETER_HIST'
ls
pwd
whoami
ls -la
cat notes.txt
cd /var/log
ls -la
tail -n 50 syslog
cd ~
df -h
free -m
uptime
cat /etc/hostname
ping -c 2 lapinlogistics.local
clear
cat todo.txt
vi notes.txt
history
cd /tmp
ls -la
cd ~
mv notes.txt notes.bak
cp notes.bak notes.txt
ps aux | grep carrot
sudo -l
top
nano todo.txt
ls -la ~/.ssh
cat ~/.ssh/known_hosts
date
who
crontab -l
exit
PETER_HIST

# ===========================================================================
# roger — ordinary day-to-day shell activity (file is 0600 roger:roger).
# ===========================================================================
_plant_history roger <<'ROGER_HIST'
ls
whoami
pwd
id
cd /var/log
tail -n 100 lapin-inventory.log
cd ~
sudo -l
sudo /usr/local/bin/carrot-report "north"
sudo /usr/local/bin/carrot-report "south"
cat /var/log/lapin-inventory.log | tail -20
df -h
crontab -l
ps aux | grep inventory
clear
free -m
uptime
date
who
cd /tmp
ls -la
cd ~
history
sudo /usr/local/bin/carrot-report "north"
logout
ROGER_HIST

log "14-bash-history: DONE — peter + roger .bash_history written (authoritative, 0600, per-user owned)"
