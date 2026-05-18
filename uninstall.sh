#!/usr/bin/env bash
# =============================================================================
# Lapin Logistics — uninstall.sh — BEST-EFFORT teardown
# =============================================================================
# Run as ROOT on the TARGET VM only. This is "good enough for dev iteration",
# NOT a guaranteed clean restore. Plan: for cohort delivery, snapshot the
# VM after install and roll back between cohorts instead of relying on this.
#
# It removes the OS users, services, and files this lab creates and tries to
# restore the host security posture (re-enable AppArmor/SELinux/resolved).
# Every step is guarded so a partial install still tears down cleanly, and it
# honors LAPIN_DRY_RUN like install.sh.
#
# >>> USAGE
# Usage:
#   ./uninstall.sh            # tear down
#   ./uninstall.sh --dry-run  # show what would be removed
#   ./uninstall.sh --yes      # do not prompt for confirmation
# <<< USAGE
# =============================================================================
set -euo pipefail

LAPIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$LAPIN_ROOT/lib/common.sh"
# shellcheck source=lib/pkg.sh
source "$LAPIN_ROOT/lib/pkg.sh"
# shellcheck source=lib/distro.sh
source "$LAPIN_ROOT/lib/distro.sh"

ASSUME_YES="${LAPIN_ASSUME_YES:-0}"
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run) LAPIN_DRY_RUN=1 ;;
        --yes|-y)  ASSUME_YES=1 ;;
        -h|--help) _render_help "${BASH_SOURCE[0]}"; exit 0 ;;
        *)         die "unknown argument: $1" ;;
    esac
    shift
done
export LAPIN_DRY_RUN

require_root

if [[ "$ASSUME_YES" != "1" ]] && ! is_dry_run; then
    printf 'This will remove Lapin Logistics lab users/services/files. Continue? [y/N] '
    if [[ -t 0 ]]; then read -r r || r=""; else r=""; fi
    case "$r" in y|Y|yes|YES) ;; *) die "aborted" ;; esac
fi

# Best-effort wrapper: never let one failure abort the whole teardown.
try() {
    if is_dry_run; then
        log "[DRY-RUN] would: $*"
        return 0
    fi
    log "exec: $*"
    "$@" || warn "non-fatal: '$*' failed (continuing best-effort)"
}

LAPIN_USERS=(peter roger bugs thumper harvey oswald)

# ---- stop + disable services ------------------------------------------------
log "stopping lab services"
if command -v systemctl >/dev/null 2>&1; then
    for s in vsftpd "$(svc_name named)" "$(svc_name apache2)" "$(svc_name smb)" \
             "$(svc_name nmb)" "$(svc_name snmpd)" "$(svc_name ssh)" \
             "$(svc_name mariadb)" lapin-warren lapin-tarpit; do
        [[ -n "$s" ]] || continue
        try systemctl disable --now "$s"
    done
    for unit in lapin-warren lapin-tarpit; do
        try rm -f "/etc/systemd/system/${unit}.service"
    done
    try systemctl daemon-reload
fi

# ---- remove users + homes ---------------------------------------------------
log "removing lab users"
for u in "${LAPIN_USERS[@]}"; do
    if id "$u" >/dev/null 2>&1; then
        try pkill -KILL -u "$u"
        try userdel -r "$u"
    fi
done
try groupdel lapin-staff

# ---- remove files / dirs the lab plants -------------------------------------
log "removing lab files"
LAPIN_PATHS=(
    /srv/ftp/pub
    /opt/lapin-tools
    /opt/hutch
    /opt/backup
    /var/www/carrotmart
    /var/www/internal-vhost
    /var/www/wordpress
    /etc/cron.d/lapin-inventory
    /etc/sudoers.d/carrot-report
    /etc/systemd/resolved.conf.d/lapin.conf
    /root/root.txt
    /var/log/lapin-install.log
)
for p in "${LAPIN_PATHS[@]}"; do
    if [[ -e "$p" ]]; then
        try rm -rf "$p"
    fi
done

# ---- restore host security posture (best-effort) ----------------------------
log "attempting to restore host security posture (re-enable hardening)"
if command -v systemctl >/dev/null 2>&1; then
    try systemctl enable --now apparmor
    try systemctl restart systemd-resolved
fi
if command -v setenforce >/dev/null 2>&1; then
    try setenforce 1
    if [[ -f /etc/selinux/config ]] && ! is_dry_run; then
        sed -i 's/^SELINUX=permissive/SELINUX=enforcing/' /etc/selinux/config || true
    fi
fi
warn "Firewall was disabled/opened by install.sh; uninstall does NOT re-enable it"
warn "(restoring a firewall blindly could lock you out). Re-enable manually if needed."

log "uninstall complete (best-effort). Snapshot rollback remains the reliable reset."
