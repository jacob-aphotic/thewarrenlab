#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/08-snmp.sh — Lapin Logistics — SNMPv2
# =============================================================================
# Configures snmpd with two community strings:
#   public         — read-only, default system view
#   lapin-internal — read-only, FULL MIB view (.1) — process list, interfaces,
#                    installed software; snmpwalk returns thousands of lines.
#
# Listens on UDP 161 on all interfaces.
#
# DRY-RUN SAFE: all mutations via run / is_dry_run-gated here-doc.
# IDEMPOTENT:   snmpd.conf authoritatively overwritten on every run.
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

log "08-snmp: starting snmpd setup"

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
log "08-snmp: ensuring snmpd package"
ensure_pkg snmpd

# ---------------------------------------------------------------------------
# 2. Resolve snmpd.conf path (same on Debian, RHEL, Arch for net-snmp)
# ---------------------------------------------------------------------------
_SNMPD_CONF="/etc/snmp/snmpd.conf"

# Ensure the directory exists (RHEL may not create it until after package post-install).
ensure_dir /etc/snmp 755

# ---------------------------------------------------------------------------
# 3. Write snmpd.conf (authoritative overwrite)
#    Two community strings:
#      public          -> systemview (default read-only view of system MIBs)
#      lapin-internal  -> fullview   (entire MIB tree: process list, ifaces,
#                                    software, etc.)
# ---------------------------------------------------------------------------
log "08-snmp: writing ${_SNMPD_CONF}"
if is_dry_run; then
    log "[DRY-RUN] would write ${_SNMPD_CONF} with communities: public, lapin-internal"
else
    cat > "$_SNMPD_CONF" <<'SNMPD_CONF_EOF'
# Lapin Logistics — snmpd.conf
# Two community strings: public (limited) and lapin-internal (full MIB).

###########################################################################
# AGENT BEHAVIOUR
###########################################################################

# Listen on all interfaces, UDP 161 (default)
agentAddress udp:161,udp6:[::1]:161

###########################################################################
# ACCESS CONTROL
###########################################################################

# --- Views ---
# systemview: standard limited view (system group + interfaces)
view   systemview  included  .1.3.6.1.2.1.1        # system
view   systemview  included  .1.3.6.1.2.1.25.1     # hrSystem
view   systemview  included  .1.3.6.1.2.1.2        # interfaces

# fullview: entire MIB tree — process list, installed software, all ifaces, etc.
view   fullview    included  .1

# --- Community strings ---
# public: read-only, systemview
rocommunity  public    default  -V systemview

# lapin-internal: read-only, full view
rocommunity  lapin-internal  default  -V fullview

###########################################################################
# SYSTEM INFO
###########################################################################
sysLocation  Lapin Logistics Warehouse, Sector 7
sysContact   ops@lapinlogistics.local
sysServices  72

###########################################################################
# PROCESS / HOST RESOURCES (make process list + software list visible)
###########################################################################
# Enable host-resources MIB tables
extend .1.3.6.1.4.1.8072.1.3.2  test /bin/echo "snmpd_ok"

# Disk monitoring (populates dskTable — adds more enumerable data)
disk / 1000

# Process list monitoring (populates hrSWRunTable)
proc sshd
proc apache2
proc smbd

###########################################################################
# LOGGING
###########################################################################
# Log to syslog
# (default snmpd logging; no additional config required)
SNMPD_CONF_EOF
    log "08-snmp: ${_SNMPD_CONF} written"
fi

# ---------------------------------------------------------------------------
# 4. Enable and start snmpd
# ---------------------------------------------------------------------------
log "08-snmp: enabling snmpd"
ensure_service_enabled snmpd

log "08-snmp: DONE — communities: public (systemview) + lapin-internal (fullview)"
