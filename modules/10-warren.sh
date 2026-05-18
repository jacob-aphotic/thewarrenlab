#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/10-warren.sh — Lapin Logistics — internal web app on TCP 58008
# =============================================================================
# Deploys assets/warren/ (app.py, requirements.txt, templates/) to /opt/warren/
# and runs it under gunicorn as a systemd (or OpenRC/SysV) service.
#
# Design decisions:
#   GUNICORN:   system gunicorn (installed by 00-prereqs via pip3
#               --break-system-packages). No separate venv — 00-prereqs already
#               placed flask+gunicorn on the system Python; a per-app venv would
#               need network or pre-cached wheels, both unsafe for an offline lab
#               target. A real-run pre-flight confirms python3 can import both
#               modules (actionable die if missing).
#
#   SERVICE USER: 'www-data' — present on Debian/Ubuntu by default; on RPM-
#               based or Arch targets it may be absent, so we use ensure_user to
#               create it as a no-login system account if needed. Files under
#               /opt/warren are owned www-data:www-data, mode 750.  The systemd
#               unit runs User=www-data so the process is never root.
#
#   -w 1:       Single gunicorn worker. App state (Flask session) is in-memory
#               per process; a single worker keeps that state consistent.
#
#   PORT:       0.0.0.0:58008 — firewall/LSM rules are handled centrally by
#               install.sh; this module only notes that the port should be open.
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

# Derive assets path from BASH_SOURCE — never a hardcoded /home/kali path.
_WARREN_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAPIN_ASSETS="${LAPIN_ASSETS:-${_WARREN_MODULE_DIR}/../assets}"
LAPIN_ASSETS="$(cd "${LAPIN_ASSETS}" && pwd)"

_WARREN_SRC="${LAPIN_ASSETS}/warren"
_WARREN_DEST="/opt/warren"
_WARREN_PORT="58008"
_WARREN_USER="www-data"

log "10-warren: starting internal web app setup (port ${_WARREN_PORT})"

# ---------------------------------------------------------------------------
# 1. Pre-flight: verify source bundle exists (real-run only)
# ---------------------------------------------------------------------------
if ! is_dry_run; then
    if [[ ! -f "${_WARREN_SRC}/app.py" ]]; then
        die "10-warren: source bundle missing: ${_WARREN_SRC}/app.py" \
            "— ensure assets/warren/ is present in the project root before running."
    fi
    log "10-warren: source bundle verified at ${_WARREN_SRC}"
fi

# ---------------------------------------------------------------------------
# 2. Pre-flight: confirm Flask + gunicorn are importable (real-run only)
#    00-prereqs.sh installs them system-wide via pip3 --break-system-packages.
# ---------------------------------------------------------------------------
if ! is_dry_run; then
    if ! python3 -c 'import flask, gunicorn' 2>/dev/null; then
        die "10-warren: 'flask' and/or 'gunicorn' not importable by python3." \
            "Run modules/00-prereqs.sh first (it installs them system-wide via pip3)."
    fi
    log "10-warren: flask + gunicorn importable — OK"
fi

# ---------------------------------------------------------------------------
# 2b. Resolve the gunicorn invocation (real-run only)
#     On Debian/Ubuntu pip3 --break-system-packages drops a `gunicorn` console
#     script in /usr/local/bin; on Arch (and others) root pip3 lands it in
#     /usr/bin instead. Hardcoding /usr/local/bin/gunicorn => systemd/openrc/sysv
#     ExecStart points at a missing binary and The Warren never starts.
#     So resolve it at install time:
#       * Prefer the `gunicorn` console script on PATH.
#       * Fall back to `python3 -m gunicorn` — the preflight already proved
#         `import gunicorn` works for this python3, so the module form is
#         guaranteed runnable even when no console script is on PATH.
#     The init files below carry a literal @@GUNICORN@@ token; we sed-substitute
#     ${_GUNICORN_BIN} into each written file (real-run / not-dry-run only).
# ---------------------------------------------------------------------------
if is_dry_run; then
    # Placeholder only — never written (every unit write is dry-run-gated).
    _GUNICORN_BIN="/usr/local/bin/gunicorn"
    log "[DRY-RUN] would resolve gunicorn via 'command -v gunicorn' (fallback: python3 -m gunicorn); no probe run in dry-run"
else
    if _GUNICORN_BIN="$(command -v gunicorn 2>/dev/null)" && [[ -x "$_GUNICORN_BIN" ]]; then
        log "10-warren: resolved gunicorn console script: ${_GUNICORN_BIN}"
    else
        _GUNICORN_BIN="$(command -v python3) -m gunicorn"
        log "10-warren: no gunicorn console script on PATH — fallback to module invocation: ${_GUNICORN_BIN}"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Ensure service user www-data exists (no-login system account)
#    On Debian/Ubuntu it is present by default; ensure_user no-ops if so.
# ---------------------------------------------------------------------------
log "10-warren: ensuring service user '${_WARREN_USER}'"
ensure_user "${_WARREN_USER}" /usr/sbin/nologin --system --no-create-home

# ---------------------------------------------------------------------------
# 4. Deploy app: copy assets/warren/ → /opt/warren (idempotent, authoritative)
# ---------------------------------------------------------------------------
log "10-warren: deploying app to ${_WARREN_DEST}"
ensure_dir "${_WARREN_DEST}" 750 "${_WARREN_USER}:${_WARREN_USER}"

# cp -aT: copy source tree INTO dest, dereferencing correctly; overwrites.
run cp -aT "${_WARREN_SRC}" "${_WARREN_DEST}"

# Ownership: www-data owns everything under /opt/warren.
# World-write is not granted; students cannot tamper with the app directly.
run chown -R "${_WARREN_USER}:${_WARREN_USER}" "${_WARREN_DEST}"
run chmod -R u=rwX,g=rX,o= "${_WARREN_DEST}"
# /opt/warren itself must be executable/traversable by the service user.
run chmod 750 "${_WARREN_DEST}"

# Post-copy existence check (real-run only).
if ! is_dry_run; then
    if [[ ! -f "${_WARREN_DEST}/app.py" ]]; then
        die "10-warren: copy appeared to succeed but ${_WARREN_DEST}/app.py not found — aborting."
    fi
    log "10-warren: ${_WARREN_DEST}/app.py verified after deploy"
fi

log "10-warren: app deployed to ${_WARREN_DEST}"
log "10-warren: NOTE — port ${_WARREN_PORT} must be permitted by the firewall; install.sh handles firewall/LSM rules centrally."

# ---------------------------------------------------------------------------
# 5. systemd unit (or OpenRC/SysV fallback) — authoritative OVERWRITE
#    ExecStart uses the system gunicorn; WorkingDirectory=/opt/warren so
#    'app:app' and the templates/ directory resolve correctly.
#    -w 1: single worker so in-memory session state stays consistent.
# ---------------------------------------------------------------------------

if [[ "${LAPIN_INIT:-}" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then

    _UNIT_FILE="/etc/systemd/system/lapin-warren.service"
    log "10-warren: writing systemd unit ${_UNIT_FILE}"

    if is_dry_run; then
        log "[DRY-RUN] would write ${_UNIT_FILE}"
    else
        cat > "${_UNIT_FILE}" <<'UNIT_EOF'
[Unit]
Description=Lapin Logistics Internal Chat
Documentation=https://lapinlogistics.local/internal/ops
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/warren
ExecStart=@@GUNICORN@@ -w 1 -b 0.0.0.0:58008 app:app
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT_EOF
        # Substitute the gunicorn token. systemd splits ExecStart on
        # whitespace, so the space-containing fallback
        # (/usr/bin/python3 -m gunicorn) is a valid ExecStart as-is.
        run sed -i "s|@@GUNICORN@@|${_GUNICORN_BIN}|g" "${_UNIT_FILE}"
        log "10-warren: systemd unit written (ExecStart -> ${_GUNICORN_BIN})"
        # Reload so the new (or replaced) unit is visible to systemctl.
        run systemctl daemon-reload
    fi

    log "10-warren: enabling lapin-warren service"
    ensure_service_enabled lapin-warren

elif [[ "${LAPIN_INIT:-}" == "openrc" ]]; then

    _OPENRC_SCRIPT="/etc/init.d/lapin-warren"
    log "10-warren: writing OpenRC init script ${_OPENRC_SCRIPT}"

    if is_dry_run; then
        log "[DRY-RUN] would write ${_OPENRC_SCRIPT}"
    else
        # OpenRC `command` must be a single executable; `command_args` is
        # word-split. The fallback (/usr/bin/python3 -m gunicorn) contains a
        # space, so we cannot put it directly in `command`. Robust encoding
        # for BOTH forms: command=/bin/sh, and command_args runs the resolved
        # invocation via `-c` (a single sh argument). @@GUNICORN@@ is
        # substituted unquoted into the -c string so `python3 -m gunicorn`
        # expands to multiple words correctly; a plain console-script path
        # works identically.
        cat > "${_OPENRC_SCRIPT}" <<'OPENRC_EOF'
#!/sbin/openrc-run
description="Lapin Logistics Internal Chat"

command="/bin/sh"
command_args="-c 'exec @@GUNICORN@@ -w 1 -b 0.0.0.0:58008 app:app'"
command_background=true
command_user="www-data"
directory="/opt/warren"
pidfile="/run/lapin-warren.pid"
OPENRC_EOF
        run sed -i "s|@@GUNICORN@@|${_GUNICORN_BIN}|g" "${_OPENRC_SCRIPT}"
        chmod 755 "${_OPENRC_SCRIPT}"
        log "10-warren: OpenRC script written (command -> /bin/sh -c '${_GUNICORN_BIN} ...')"
    fi

    log "10-warren: enabling lapin-warren (OpenRC)"
    ensure_service_enabled lapin-warren

else

    # SysV / unknown init — write a basic start/stop helper.
    log "10-warren: unknown init (${LAPIN_INIT:-}); writing SysV-style helper"
    warn "10-warren: non-systemd/openrc init — lapin-warren will not auto-start on boot"

    if is_dry_run; then
        log "[DRY-RUN] would write /etc/init.d/lapin-warren (SysV)"
    else
        cat > /etc/init.d/lapin-warren <<'SYSV_EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          lapin-warren
# Required-Start:    $network
# Default-Start:     2 3 4 5
# Short-Description: Lapin Logistics Internal Chat
### END INIT INFO
PIDFILE=/run/lapin-warren.pid
case "$1" in
    start)
        cd /opt/warren
        # Portable privilege drop: `su` is always present when running as
        # root (sudo may be absent on minimal installs). The whole gunicorn
        # invocation is one /bin/sh -c string, so the space-containing
        # fallback (/usr/bin/python3 -m gunicorn) works after token sub.
        su -s /bin/sh -c "exec @@GUNICORN@@ -w 1 -b 0.0.0.0:58008 app:app --daemon --pid \"$PIDFILE\"" www-data
        echo "lapin-warren started"
        ;;
    stop)
        if [[ -f "$PIDFILE" ]]; then
            kill "$(cat "$PIDFILE")" 2>/dev/null || true
            rm -f "$PIDFILE"
        fi
        echo "lapin-warren stopped"
        ;;
    restart)
        "$0" stop
        "$0" start
        ;;
    *) echo "Usage: $0 {start|stop|restart}" ;;
esac
SYSV_EOF
        chmod 755 /etc/init.d/lapin-warren
        if command -v update-rc.d >/dev/null 2>&1; then
            run update-rc.d lapin-warren defaults
        elif command -v chkconfig >/dev/null 2>&1; then
            run chkconfig --add lapin-warren
        fi
        run /etc/init.d/lapin-warren start
    fi

fi

log "10-warren: DONE — The Warren internal chat deployed on 0.0.0.0:${_WARREN_PORT}"
log "10-warren: Healthcheck: curl http://127.0.0.1:${_WARREN_PORT}/healthz"
