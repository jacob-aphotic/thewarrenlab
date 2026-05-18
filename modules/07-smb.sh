#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/07-smb.sh — Lapin Logistics — Samba shares
# =============================================================================
# Configures two Samba shares:
#   [hutch]   — read-only, guest ok, /srv/smb/hutch — shared docs
#   [carrots] — read-write, guest ok, /srv/smb/carrots — upload area
#
# Global: map to guest = bad user, restrict anonymous = 0,
#         server min protocol = NT1
#
# Adds peter + roger to smbpasswd. Passwords are random.
#
# Note: AppArmor/SELinux Samba null-session interference is handled centrally
# by install.sh's handle_lsm(); this module does not duplicate that logic.
#
# DRY-RUN SAFE: all mutations via run / is_dry_run-gated blocks.
# IDEMPOTENT:   smb.conf is authoritatively overwritten; dirs created only if
#               missing; if the user already exists in the Samba DB smbpasswd -a
#               changes the password (new random value); safe to re-run.
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

log "07-smb: starting Samba share setup"

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
log "07-smb: ensuring samba package"
ensure_pkg samba

# ---------------------------------------------------------------------------
# 2. Share directories
# ---------------------------------------------------------------------------
log "07-smb: ensuring share directories"
ensure_dir /srv/smb/hutch  755 root:root
ensure_dir /srv/smb/carrots 777 root:root

# ---------------------------------------------------------------------------
# 3. Drop files in hutch (idempotent — only write if missing)
# ---------------------------------------------------------------------------
log "07-smb: planting hutch files"
if is_dry_run; then
    log "[DRY-RUN] would create files in /srv/smb/hutch"
else
    # Mundane text files; written only if not present.
    if [[ ! -f /srv/smb/hutch/warehouse-inventory.txt ]]; then
        cat > /srv/smb/hutch/warehouse-inventory.txt <<'EOF'
Lapin Logistics Warehouse Inventory — Q3 2024
==============================================
Row A: 1,204 units carrot pulp concentrate
Row B: 876 units dried grass meal
Row C: Seasonal — empty pending resupply
EOF
    fi
    if [[ ! -f /srv/smb/hutch/hr-contacts.txt ]]; then
        cat > /srv/smb/hutch/hr-contacts.txt <<'EOF'
HR CONTACTS (internal use only)
================================
Peter Cottontail    — Warehouse Lead   — peter@lapinlogistics.local
Roger Hare          — Logistics Mgr    — roger@lapinlogistics.local
Jessica Rabbit      — Marketing Mgr    — jessica@lapinlogistics.local (external)
EOF
    fi
    if [[ ! -f /srv/smb/hutch/q3-shipping-report.txt ]]; then
        cat > /srv/smb/hutch/q3-shipping-report.txt <<'EOF'
Q3 Shipping Summary — DRAFT
============================
Total outbound shipments: 4,112
On-time delivery rate: 94.2%
Pending review: rows C, D (see inventory)
Status: PENDING FINANCE SIGN-OFF
EOF
    fi
    log "07-smb: hutch files written"
fi

# ---------------------------------------------------------------------------
# 4. Write smb.conf (authoritative — always overwrite)
# ---------------------------------------------------------------------------
log "07-smb: writing /etc/samba/smb.conf"
if is_dry_run; then
    log "[DRY-RUN] would write /etc/samba/smb.conf"
else
    cat > /etc/samba/smb.conf <<'SMB_CONF_EOF'
# Lapin Logistics — smb.conf

[global]
   workgroup             = LAPINLOGISTICS
   server string         = Lapin Logistics File Server
   netbios name          = LAPIN-SRV

   map to guest          = bad user
   restrict anonymous    = 0
   guest account         = nobody

   server min protocol   = NT1

   # Logging
   log file              = /var/log/samba/log.%m
   max log size          = 1000
   logging               = file

   # Bind all interfaces
   interfaces            = 0.0.0.0/0
   bind interfaces only  = no

[hutch]
   comment               = Lapin Hutch — shared docs
   path                  = /srv/smb/hutch
   guest ok              = yes
   read only             = yes
   browseable            = yes

[carrots]
   comment               = Carrot Store — upload area
   path                  = /srv/smb/carrots
   guest ok              = yes
   read only             = no
   writable              = yes
   browseable            = yes
   create mask           = 0664
   directory mask        = 0775
SMB_CONF_EOF
    log "07-smb: /etc/samba/smb.conf written"
fi

# ---------------------------------------------------------------------------
# 5. Add peter and roger to the Samba user database
#    Passwords are random.
#    smbpasswd -a is idempotent; if user already in DB it just updates pw.
# ---------------------------------------------------------------------------
log "07-smb: adding peter + roger to Samba user DB"
if is_dry_run; then
    log "[DRY-RUN] would smbpasswd -a peter <random-pw>"
    log "[DRY-RUN] would smbpasswd -a roger <random-pw>"
else
    # peter — random password
    _smb_peter_pw="$(openssl rand -hex 16)"
    printf '%s\n%s\n' "$_smb_peter_pw" "$_smb_peter_pw" | smbpasswd -a -s peter
    unset _smb_peter_pw
    log "07-smb: peter added to samba DB"

    # roger — random password
    _smb_roger_pw="$(openssl rand -hex 16)"
    printf '%s\n%s\n' "$_smb_roger_pw" "$_smb_roger_pw" | smbpasswd -a -s roger
    unset _smb_roger_pw
    log "07-smb: roger added to samba DB"
fi

# ---------------------------------------------------------------------------
# 6. Enable and start smbd + nmbd
#    Generic handles: smb (-> smbd on Debian) and nmb (-> nmbd on Debian)
# ---------------------------------------------------------------------------
log "07-smb: enabling smbd"
ensure_service_enabled smb
log "07-smb: enabling nmbd"
ensure_service_enabled nmb

log "07-smb: DONE — hutch (ro) + carrots (rw) shares active"
