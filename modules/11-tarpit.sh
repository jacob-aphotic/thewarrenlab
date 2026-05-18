#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/11-tarpit.sh — Lapin Logistics — status beacon on TCP 31337
# =============================================================================
# Creates a socat-based status beacon on TCP port 31337:
#   /opt/lapin-tools/status-beacon.sh — emits a per-connection nonce + the
#       BurrowD status banner, then closes.
#   lapin-status-beacon.service        — systemd unit running socat.
#
# /opt/lapin-tools/ is shared with module 12-privesc; ensure_dir is safe to
# call from both — it no-ops if the directory already exists.
#
# DRY-RUN SAFE: all mutations via run / is_dry_run-gated blocks.
# IDEMPOTENT:   script + unit file authoritatively overwritten every run.
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

log "11-tarpit: starting status-beacon setup on TCP 31337"

# ---------------------------------------------------------------------------
# 1. Package — socat
# ---------------------------------------------------------------------------
log "11-tarpit: ensuring socat package"
ensure_pkg socat

# ---------------------------------------------------------------------------
# 2. Ensure /opt/lapin-tools/ exists
#    Also created by module 12-privesc; ensure_dir is idempotent.
# ---------------------------------------------------------------------------
ensure_dir /opt/lapin-tools 755 root:root

# ---------------------------------------------------------------------------
# 3. Write status-beacon.sh (authoritative overwrite)
# ---------------------------------------------------------------------------
log "11-tarpit: writing /opt/lapin-tools/status-beacon.sh"
if is_dry_run; then
    log "[DRY-RUN] would write /opt/lapin-tools/status-beacon.sh"
else
    cat > /opt/lapin-tools/status-beacon.sh <<'JUNK_EOF'
#!/usr/bin/env bash
# status-beacon.sh — emits the BurrowD status banner for a polling client.
# Invoked per-connection by socat EXEC.

# Small settle delay before responding.
sleep 0.1

# Per-connection nonce.
_blob="$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | base64 -w 0)"

printf '%s\r\n' "$_blob"
printf 'BurrowD v1.4.2-stable (Lapin Logistics internal)\r\n'
printf 'Connection closed by foreign host.\r\n'
JUNK_EOF
    chmod 755 /opt/lapin-tools/status-beacon.sh
    log "11-tarpit: /opt/lapin-tools/status-beacon.sh written (mode 755)"
fi

# ---------------------------------------------------------------------------
# 4. Write systemd unit (or init equivalent)
# ---------------------------------------------------------------------------
if [[ "${LAPIN_INIT:-}" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
    _UNIT_FILE="/etc/systemd/system/lapin-status-beacon.service"
    log "11-tarpit: writing systemd unit ${_UNIT_FILE}"
    if is_dry_run; then
        log "[DRY-RUN] would write ${_UNIT_FILE}"
    else
        cat > "$_UNIT_FILE" <<'UNIT_EOF'
[Unit]
Description=Lapin Logistics Status Beacon
After=network.target
Documentation=https://lapinlogistics.local/internal/ops

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:31337,reuseaddr,fork EXEC:/opt/lapin-tools/status-beacon.sh
Restart=always
RestartSec=3
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT_EOF
        log "11-tarpit: systemd unit written"
        # Reload systemd so the new unit is visible before enable.
        run systemctl daemon-reload
    fi

    log "11-tarpit: enabling lapin-status-beacon service"
    ensure_service_enabled lapin-status-beacon

elif [[ "${LAPIN_INIT:-}" == "openrc" ]]; then
    # OpenRC fallback — write a simple init script
    _OPENRC_SCRIPT="/etc/init.d/lapin-status-beacon"
    log "11-tarpit: writing OpenRC init script ${_OPENRC_SCRIPT}"
    if is_dry_run; then
        log "[DRY-RUN] would write ${_OPENRC_SCRIPT}"
    else
        cat > "$_OPENRC_SCRIPT" <<'OPENRC_EOF'
#!/sbin/openrc-run
description="Lapin Logistics Status Beacon"

command="/usr/bin/socat"
command_args="TCP-LISTEN:31337,reuseaddr,fork EXEC:/opt/lapin-tools/status-beacon.sh"
command_background=true
pidfile="/run/lapin-status-beacon.pid"
OPENRC_EOF
        chmod 755 "$_OPENRC_SCRIPT"
        log "11-tarpit: OpenRC script written"
    fi
    log "11-tarpit: enabling lapin-status-beacon (OpenRC)"
    ensure_service_enabled lapin-status-beacon

else
    # SysV / unknown — write a basic wrapper start/stop script
    log "11-tarpit: unknown init (${LAPIN_INIT:-}); writing manual start helper"
    warn "11-tarpit: no systemd/openrc — service will not auto-start on boot"
    if is_dry_run; then
        log "[DRY-RUN] would write /etc/init.d/lapin-status-beacon (sysv)"
    else
        cat > /etc/init.d/lapin-status-beacon <<'SYSV_EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          lapin-status-beacon
# Required-Start:    $network
# Default-Start:     2 3 4 5
# Short-Description: Lapin Logistics Status Beacon
### END INIT INFO
case "$1" in
    start)
        /usr/bin/socat TCP-LISTEN:31337,reuseaddr,fork \
            EXEC:/opt/lapin-tools/status-beacon.sh &
        echo $! > /run/lapin-status-beacon.pid
        ;;
    stop)
        kill "$(cat /run/lapin-status-beacon.pid 2>/dev/null)" 2>/dev/null || true
        ;;
    *) echo "Usage: $0 {start|stop}" ;;
esac
SYSV_EOF
        chmod 755 /etc/init.d/lapin-status-beacon
        if command -v update-rc.d >/dev/null 2>&1; then
            run update-rc.d lapin-status-beacon defaults
        elif command -v chkconfig >/dev/null 2>&1; then
            run chkconfig --add lapin-status-beacon
        fi
        # Start it now
        run /etc/init.d/lapin-status-beacon start
    fi
fi

log "11-tarpit: DONE — socat status beacon listening on TCP 31337"
