#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/15-flag-portal.sh — Lapin Logistics — flag submission portal on TCP 1337
# =============================================================================
# Deploys assets/flag-portal/ (app.py, requirements.txt, templates/) to
# /opt/flag-portal/ and runs it under gunicorn as a systemd (or OpenRC/SysV)
# service named lapin-flag-portal.
#
# Design decisions:
#   GUNICORN:   system gunicorn (installed by 00-prereqs via pip3
#               --break-system-packages). No per-app venv — same pattern as
#               10-warren.sh. Pre-flight confirms flask importable; gunicorn
#               binary resolved at install-time via @@GUNICORN@@ token + sed.
#
#   SERVICE USER: 'flagportal' — dedicated no-login system account; ensures
#               the process is never root and cannot write outside /opt/flag-portal.
#               Files under /opt/flag-portal owned flagportal:flagportal, mode 750.
#
#   -w 1:       Session state is in the signed cookie (no DB). A single worker
#               is correct and sufficient; multiple workers would each have their
#               own in-memory state and could produce inconsistent responses.
#
#   PORT:       0.0.0.0:1337 — firewall/LSM rules are handled centrally by
#               install.sh; this module only notes the port requirement.
#
#   ANTI-CHEAT: The deployed app.py contains only SHA-256 digests; no plaintext
#               flag value is written to disk by this module. The instructor
#               answer key (/root/flags.txt, mode 0400) is written by this module
#               for reference only and is not readable by non-root players.
#
# DRY-RUN SAFE:  all mutations via run / is_dry_run-gated here-docs.
# IDEMPOTENT:    re-running re-copies app, re-writes unit, restarts cleanly.
#                The systemd unit file is authoritatively OVERWRITTEN every run.
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

# Derive assets path from BASH_SOURCE — never a hardcoded author home path.
_FP_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAPIN_ASSETS="${LAPIN_ASSETS:-${_FP_MODULE_DIR}/../assets}"
LAPIN_ASSETS="$(cd "${LAPIN_ASSETS}" && pwd)"

_FP_SRC="${LAPIN_ASSETS}/flag-portal"
_FP_DEST="/opt/flag-portal"
_FP_PORT="1337"
_FP_USER="flagportal"

log "15-flag-portal: starting flag submission portal setup (port ${_FP_PORT})"

# ---------------------------------------------------------------------------
# 1. Pre-flight: verify source bundle exists (real-run only)
# ---------------------------------------------------------------------------
if ! is_dry_run; then
    if [[ ! -f "${_FP_SRC}/app.py" ]]; then
        die "15-flag-portal: source bundle missing: ${_FP_SRC}/app.py" \
            "— ensure assets/flag-portal/ is present in the project root before running."
    fi
    log "15-flag-portal: source bundle verified at ${_FP_SRC}"
fi

# ---------------------------------------------------------------------------
# 2. Pre-flight: confirm Flask is importable (real-run only)
#    00-prereqs.sh installs flask + gunicorn system-wide via pip3.
# ---------------------------------------------------------------------------
if ! is_dry_run; then
    if ! python3 -c 'import flask' 2>/dev/null; then
        die "15-flag-portal: 'flask' not importable by python3." \
            "Run modules/00-prereqs.sh first (it installs flask system-wide via pip3)."
    fi
    log "15-flag-portal: flask importable — OK"
fi

# ---------------------------------------------------------------------------
# 2b. Resolve the gunicorn invocation (real-run only)
#     Same pattern as 10-warren.sh: prefer the console script on PATH, fall
#     back to `python3 -m gunicorn`.  The @@GUNICORN@@ token is substituted
#     into each written init file; the gunicorn probe is skipped in dry-run.
# ---------------------------------------------------------------------------
if is_dry_run; then
    _GUNICORN_BIN="/usr/local/bin/gunicorn"
    log "[DRY-RUN] would resolve gunicorn via 'command -v gunicorn' (fallback: python3 -m gunicorn); no probe run in dry-run"
else
    if _GUNICORN_BIN="$(command -v gunicorn 2>/dev/null)" && [[ -x "$_GUNICORN_BIN" ]]; then
        log "15-flag-portal: resolved gunicorn console script: ${_GUNICORN_BIN}"
    else
        _GUNICORN_BIN="$(command -v python3) -m gunicorn"
        log "15-flag-portal: no gunicorn console script on PATH — fallback to module invocation: ${_GUNICORN_BIN}"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Ensure dedicated service user exists (no-login system account)
# ---------------------------------------------------------------------------
log "15-flag-portal: ensuring service user '${_FP_USER}'"
ensure_user "${_FP_USER}" /usr/sbin/nologin --system --no-create-home

# ---------------------------------------------------------------------------
# 4. Deploy app: copy assets/flag-portal/ → /opt/flag-portal (idempotent)
# ---------------------------------------------------------------------------
log "15-flag-portal: deploying app to ${_FP_DEST}"
ensure_dir "${_FP_DEST}" 750 "${_FP_USER}:${_FP_USER}"

# cp -aT: copy source tree INTO dest, dereferencing correctly; overwrites.
run cp -aT "${_FP_SRC}" "${_FP_DEST}"

# Ownership: flagportal owns everything under /opt/flag-portal.
# World-write is NOT granted; players cannot tamper with the deployed app.
run chown -R "${_FP_USER}:${_FP_USER}" "${_FP_DEST}"
run chmod -R u=rwX,g=rX,o= "${_FP_DEST}"
run chmod 750 "${_FP_DEST}"

# Post-copy existence check (real-run only).
if ! is_dry_run; then
    if [[ ! -f "${_FP_DEST}/app.py" ]]; then
        die "15-flag-portal: copy appeared to succeed but ${_FP_DEST}/app.py not found — aborting."
    fi
    log "15-flag-portal: ${_FP_DEST}/app.py verified after deploy"
fi

log "15-flag-portal: app deployed to ${_FP_DEST}"
log "15-flag-portal: NOTE — port ${_FP_PORT} must be permitted by the firewall; install.sh handles firewall/LSM rules centrally."

# ---------------------------------------------------------------------------
# 5. Write instructor answer key — /root/flags.txt, mode 0400
#    Plaintext flags for instructor reference ONLY. Not readable by players
#    (mode 0400 root:root). The portal itself does NOT read this file.
# ---------------------------------------------------------------------------
if is_dry_run; then
    log "[DRY-RUN] would write /root/flags.txt (mode 0400, root:root) — instructor answer key"
else
    cat > /root/flags.txt <<'FLAGS_EOF'
# Lapin Logistics — Instructor Answer Key
# mode 0400 root:root — do not share with players
FLAG{h0pp1ng_d0wn_th3_warren}
FLAG{r0g3r_th4t_r4bb1t}
FLAG{g0ld3n_c4rr0t_pwn3d}
FLAGS_EOF
    chmod 0400 /root/flags.txt
    chown root:root /root/flags.txt
    log "15-flag-portal: /root/flags.txt written (0400 root:root)"
fi

# ---------------------------------------------------------------------------
# 6. systemd unit (or OpenRC/SysV fallback) — authoritative OVERWRITE
#    ExecStart uses the resolved gunicorn; WorkingDirectory=/opt/flag-portal
#    so 'app:app' and templates/ resolve correctly.
#    Description is neutral — this lands on the target machine.
# ---------------------------------------------------------------------------

if [[ "${LAPIN_INIT:-}" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then

    _UNIT_FILE="/etc/systemd/system/lapin-flag-portal.service"
    log "15-flag-portal: writing systemd unit ${_UNIT_FILE}"

    if is_dry_run; then
        log "[DRY-RUN] would write ${_UNIT_FILE} (Description: Lapin Logistics submission service)"
    else
        cat > "${_UNIT_FILE}" <<'UNIT_EOF'
[Unit]
Description=Lapin Logistics submission service
Documentation=https://lapinlogistics.local/internal/ops
After=network.target

[Service]
Type=simple
User=flagportal
Group=flagportal
WorkingDirectory=/opt/flag-portal
ExecStart=@@GUNICORN@@ -w 1 -b 0.0.0.0:1337 app:app
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT_EOF
        # Substitute the gunicorn token.  The space-containing fallback
        # (/usr/bin/python3 -m gunicorn) is valid as a systemd ExecStart.
        run sed -i "s|@@GUNICORN@@|${_GUNICORN_BIN}|g" "${_UNIT_FILE}"
        log "15-flag-portal: systemd unit written (ExecStart -> ${_GUNICORN_BIN})"
        run systemctl daemon-reload
    fi

    log "15-flag-portal: enabling lapin-flag-portal service"
    ensure_service_enabled lapin-flag-portal

elif [[ "${LAPIN_INIT:-}" == "openrc" ]]; then

    _OPENRC_SCRIPT="/etc/init.d/lapin-flag-portal"
    log "15-flag-portal: writing OpenRC init script ${_OPENRC_SCRIPT}"

    if is_dry_run; then
        log "[DRY-RUN] would write ${_OPENRC_SCRIPT}"
    else
        # OpenRC `command` must be a single executable. Use /bin/sh -c so the
        # space-containing python3 fallback works identically to a plain path.
        cat > "${_OPENRC_SCRIPT}" <<'OPENRC_EOF'
#!/sbin/openrc-run
description="Lapin Logistics submission service on TCP 1337"

command="/bin/sh"
command_args="-c 'exec @@GUNICORN@@ -w 1 -b 0.0.0.0:1337 app:app'"
command_background=true
command_user="flagportal"
directory="/opt/flag-portal"
pidfile="/run/lapin-flag-portal.pid"
OPENRC_EOF
        run sed -i "s|@@GUNICORN@@|${_GUNICORN_BIN}|g" "${_OPENRC_SCRIPT}"
        chmod 755 "${_OPENRC_SCRIPT}"
        log "15-flag-portal: OpenRC script written (command -> /bin/sh -c '${_GUNICORN_BIN} ...')"
    fi

    log "15-flag-portal: enabling lapin-flag-portal (OpenRC)"
    ensure_service_enabled lapin-flag-portal

else

    # SysV / unknown init — write a basic start/stop helper.
    log "15-flag-portal: unknown init (${LAPIN_INIT:-}); writing SysV-style helper"
    warn "15-flag-portal: non-systemd/openrc init — lapin-flag-portal will not auto-start on boot"

    if is_dry_run; then
        log "[DRY-RUN] would write /etc/init.d/lapin-flag-portal (SysV)"
    else
        cat > /etc/init.d/lapin-flag-portal <<'SYSV_EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          lapin-flag-portal
# Required-Start:    $network
# Default-Start:     2 3 4 5
# Short-Description: Lapin Logistics submission service on TCP 1337
### END INIT INFO
PIDFILE=/run/lapin-flag-portal.pid
case "$1" in
    start)
        cd /opt/flag-portal
        su -s /bin/sh -c "exec @@GUNICORN@@ -w 1 -b 0.0.0.0:1337 app:app --daemon --pid \"$PIDFILE\"" flagportal
        echo "lapin-flag-portal started"
        ;;
    stop)
        if [[ -f "$PIDFILE" ]]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
        echo "lapin-flag-portal stopped"
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
SYSV_EOF
        chmod 755 /etc/init.d/lapin-flag-portal
        run sed -i "s|@@GUNICORN@@|${_GUNICORN_BIN}|g" /etc/init.d/lapin-flag-portal
        if command -v update-rc.d >/dev/null 2>&1; then
            run update-rc.d lapin-flag-portal defaults
        elif command -v chkconfig >/dev/null 2>&1; then
            run chkconfig --add lapin-flag-portal
        fi
        run /etc/init.d/lapin-flag-portal start
    fi

fi

log "15-flag-portal: DONE — flag submission portal deployed on 0.0.0.0:${_FP_PORT}"
log "15-flag-portal: Healthcheck: curl http://127.0.0.1:${_FP_PORT}/healthz"
