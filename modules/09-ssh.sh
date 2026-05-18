#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/09-ssh.sh — Lapin Logistics — sshd on port 2222
# =============================================================================
# Configures OpenSSH to listen on port 2222, with:
#   PermitRootLogin no
#   PasswordAuthentication yes
#
# Strategy (idempotent):
#   1. Prefer a drop-in /etc/ssh/sshd_config.d/zz-lapin.conf if the Include
#      directive is present in the main sshd_config (modern Debian/Ubuntu 22+,
#      Fedora 33+, etc.).
#   2. Fall back to authoritative rewrite of /etc/ssh/sshd_config if drop-in
#      is not supported.
#
# ssh.socket conflict:
#   On systemd distros where ssh.socket (socket-activated sshd) is active it
#   overrides the Port= directive because the socket hands the fd to sshd.
#   We disable ssh.socket and let the sshd.service bind directly so Port 2222
#   is honoured.
#
# DRY-RUN SAFE: all mutations via run / is_dry_run-gated blocks.
# IDEMPOTENT:   drop-in file authoritatively overwritten; socket disable is
#               idempotent (systemctl disable no-ops if not enabled).
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

log "09-ssh: starting sshd-on-2222 setup"

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
log "09-ssh: ensuring openssh-server package"
ensure_pkg openssh-server

# ---------------------------------------------------------------------------
# 2. ssh.socket handling — must happen BEFORE sshd is (re)started
#    If ssh.socket is present and active/enabled, it will override the Port
#    directive in sshd_config. Disable it so the daemon binds 2222 directly.
# ---------------------------------------------------------------------------
if [[ "${LAPIN_INIT:-}" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
    # Check if ssh.socket unit exists on this system.
    if systemctl list-unit-files --type=socket 2>/dev/null | grep -q '^ssh\.socket'; then
        log "09-ssh: ssh.socket found — disabling to allow Port 2222 override"
        if is_dry_run; then
            log "[DRY-RUN] would: systemctl disable --now ssh.socket"
        else
            # Pre-check (read-only): only call disable --now if the unit is
            # actually enabled or active; disable --now already exits 0 when the
            # unit is already stopped+disabled, so || true would only hide real
            # failures (masked unit / degraded systemd) that must not be swallowed.
            if systemctl is-enabled --quiet ssh.socket 2>/dev/null \
               || systemctl is-active --quiet ssh.socket 2>/dev/null; then
                run systemctl disable --now ssh.socket
            fi
            log "09-ssh: ssh.socket disabled"
        fi
    else
        log "09-ssh: ssh.socket not present on this system; no action needed"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Write sshd configuration
# ---------------------------------------------------------------------------
_SSHD_DROPIN_DIR="/etc/ssh/sshd_config.d"
_SSHD_DROPIN="${_SSHD_DROPIN_DIR}/zz-lapin.conf"
_SSHD_MAIN="/etc/ssh/sshd_config"

# Detect drop-in support: main sshd_config must contain an Include directive
# pointing at sshd_config.d, AND the directory must exist (or be creatable).
_use_dropin=0
if [[ -f "$_SSHD_MAIN" ]] && grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d' "$_SSHD_MAIN" 2>/dev/null; then
    _use_dropin=1
fi

if [[ "$_use_dropin" -eq 1 ]]; then
    # ---- Drop-in path (preferred) -------------------------------------------
    log "09-ssh: drop-in dir supported — writing ${_SSHD_DROPIN}"
    ensure_dir "$_SSHD_DROPIN_DIR" 755
    if is_dry_run; then
        log "[DRY-RUN] would write ${_SSHD_DROPIN} (Port 2222, PermitRootLogin no, PasswordAuthentication yes)"
    else
        cat > "$_SSHD_DROPIN" <<'DROPIN_EOF'
# Lapin Logistics — zz-lapin.conf
# Authoritative drop-in: processed LAST so values here win.
# z-prefix ensures this overrides earlier defaults.

Port 2222
PermitRootLogin no
PasswordAuthentication yes
DROPIN_EOF
        log "09-ssh: ${_SSHD_DROPIN} written"
    fi
else
    # ---- Fallback: authoritative main config rewrite -------------------------
    log "09-ssh: no drop-in Include found — rewriting ${_SSHD_MAIN} authoritatively"
    warn "09-ssh: overwriting ${_SSHD_MAIN}; original backed up to ${_SSHD_MAIN}.lapin-bak"
    if is_dry_run; then
        log "[DRY-RUN] would backup and rewrite ${_SSHD_MAIN}"
    else
        # Backup original once (idempotent — do not overwrite an existing backup)
        if [[ ! -f "${_SSHD_MAIN}.lapin-bak" ]]; then
            cp "$_SSHD_MAIN" "${_SSHD_MAIN}.lapin-bak"
        fi
        # Use sed to set/replace the three directives in-place.
        # Strategy: delete any existing Port/PermitRootLogin/PasswordAuthentication
        # lines, then append our settings at the end (authoritative).
        sed -i \
            -e '/^\s*Port\s/d' \
            -e '/^\s*PermitRootLogin\s/d' \
            -e '/^\s*PasswordAuthentication\s/d' \
            "$_SSHD_MAIN"
        cat >> "$_SSHD_MAIN" <<'MAIN_APPEND_EOF'

# --- Lapin Logistics overrides ---
Port 2222
PermitRootLogin no
PasswordAuthentication yes
MAIN_APPEND_EOF
        log "09-ssh: ${_SSHD_MAIN} updated (Port 2222, PermitRootLogin no, PasswordAuthentication yes)"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Enable and reload sshd
#    Generic handle: ssh (-> 'ssh' on Debian, 'sshd' on RHEL/Arch)
# ---------------------------------------------------------------------------
log "09-ssh: enabling ssh service"
ensure_service_enabled ssh

log "09-ssh: DONE — sshd configured on port 2222 (PermitRootLogin no, PasswordAuthentication yes)"
