#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/01-users.sh — Lapin Logistics — OS user roster
# =============================================================================
# Creates the rabbit-themed OS user accounts and the lapin-staff group.
#
# Roster:
#   peter   uid=1100  /bin/bash   password set from PETER_SSH_PW
#   roger   uid=1101  /bin/bash   random password
#   bugs    uid=1102  /bin/bash   random password
#   thumper uid=1103  /bin/bash   random password
#   harvey  uid=1104  /bin/bash   random password
#   oswald  uid=1105  /bin/bash   account locked
#
# NOT created: jessica, andrea, velveteen (website-only names, no OS account)
#
# Group: lapin-staff (supplementary/secondary for peter + roger ONLY)
#   peter is NOT added to roger's primary group; each user keeps their own
#   primary group and lapin-staff is a shared secondary group.
#
# DRY-RUN SAFE: all system mutations go through run / ensure_user / is_dry_run.
# IDEMPOTENT:   ensure_user no-ops on existing users; password/lock re-apply is safe.
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
command -v openssl >/dev/null 2>&1 || die "01-users: openssl not found; run 00-prereqs.sh first or install openssl"

# ---------------------------------------------------------------------------
# Helper: set a password for a user — dry-run safe.
# Usage: _set_password <username> <plaintext-password>
# ---------------------------------------------------------------------------
_set_password() {
    local uname="$1" pw="$2"
    if is_dry_run; then
        log "[DRY-RUN] would set password for '${uname}'"
        return 0
    fi
    log "exec: chpasswd for '${uname}'"
    printf '%s:%s\n' "$uname" "$pw" | chpasswd
}

# ---------------------------------------------------------------------------
# Helper: set a password using an explicit sha512-crypt ($6$) hash.
# Used for peter so the stored hash algorithm is deterministic regardless of
# the distro's login.defs default (recent Ubuntu defaults to yescrypt, which
# is not recomputable by openssl/standard tooling). sha512-crypt is fully
# valid for PAM/sshd, so login behaviour is unchanged. dry-run safe; the
# plaintext is never logged.
# ---------------------------------------------------------------------------
_set_password_sha512() {
    local uname="$1" pw="$2" hash
    if is_dry_run; then
        log "[DRY-RUN] would set password for '${uname}' (sha512-crypt)"
        return 0
    fi
    hash="$(openssl passwd -6 "$pw")"
    log "exec: chpasswd -e for '${uname}' (sha512-crypt)"
    printf '%s:%s\n' "$uname" "$hash" | chpasswd -e
}

# ---------------------------------------------------------------------------
# Helper: lock a user account — dry-run safe.
# Usage: _lock_user <username>
# ---------------------------------------------------------------------------
_lock_user() {
    local uname="$1"
    if is_dry_run; then
        log "[DRY-RUN] would lock account '${uname}' (passwd -l / usermod -L)"
        return 0
    fi
    log "exec: locking account '${uname}'"
    passwd -l "$uname"
}

# ---------------------------------------------------------------------------
# 1. Ensure the lapin-staff supplementary group exists
# ---------------------------------------------------------------------------
log "01-users: ensuring supplementary group 'lapin-staff'"
if getent group lapin-staff >/dev/null 2>&1; then
    log "01-users: group 'lapin-staff' already exists; leaving as-is"
else
    run groupadd lapin-staff
fi

# ---------------------------------------------------------------------------
# 2. Create users (ensure_user is idempotent; no-ops if already exists)
# ---------------------------------------------------------------------------

# --- peter (uid=1100) -------------------------------------------------------
log "01-users: ensuring user 'peter' (uid=1100)"
ensure_user peter 1100 /bin/bash
# peter's login/SSH password (PETER_SSH_PW).
_set_password_sha512 peter 'R3set-Burrow-7Gx2!'

# --- roger (uid=1101) -------------------------------------------------------
# Password is random and not used directly.
log "01-users: ensuring user 'roger' (uid=1101)"
ensure_user roger 1101 /bin/bash
_roger_pw="$(openssl rand -hex 24)"
_set_password roger "$_roger_pw"
unset _roger_pw

# --- bugs (uid=1102) --------------------------------------------------------
log "01-users: ensuring user 'bugs' (uid=1102)"
ensure_user bugs 1102 /bin/bash
_bugs_pw="$(openssl rand -hex 16)"
_set_password bugs "$_bugs_pw"
unset _bugs_pw

# --- thumper (uid=1103) -----------------------------------------------------
log "01-users: ensuring user 'thumper' (uid=1103)"
ensure_user thumper 1103 /bin/bash
_thumper_pw="$(openssl rand -hex 16)"
_set_password thumper "$_thumper_pw"
unset _thumper_pw

# --- harvey (uid=1104) ------------------------------------------------------
log "01-users: ensuring user 'harvey' (uid=1104)"
ensure_user harvey 1104 /bin/bash
_harvey_pw="$(openssl rand -hex 16)"
_set_password harvey "$_harvey_pw"
unset _harvey_pw

# --- oswald (uid=1105) — locked; appears in /etc/passwd but cannot log in --
log "01-users: ensuring user 'oswald' (uid=1105) — will be locked"
ensure_user oswald 1105 /bin/bash
_lock_user oswald

# ---------------------------------------------------------------------------
# 3. Add peter and roger to lapin-staff (supplementary only)
#    usermod -aG: appends to supplementary groups; does NOT touch primary group.
#    CRITICAL: do NOT use --gid / -g (that changes the primary group).
# ---------------------------------------------------------------------------
log "01-users: adding 'peter' to supplementary group 'lapin-staff'"
run usermod -aG lapin-staff peter

log "01-users: adding 'roger' to supplementary group 'lapin-staff'"
run usermod -aG lapin-staff roger

# ---------------------------------------------------------------------------
# 4. Ensure home directories exist with correct ownership
#    ensure_user -m already creates /home/<user> with skeleton on first run.
#    On re-run: user exists → ensure_user no-ops → we verify the dir ourselves.
#    Later modules plant per-user content; we do NOT here.
# ---------------------------------------------------------------------------
for _u in peter roger bugs thumper harvey oswald; do
    ensure_dir "/home/${_u}" 750 "${_u}:${_u}"
done
unset _u

# ---------------------------------------------------------------------------
# Negative confirmation: jessica / andrea / velveteen are NEVER created here.
# (This comment is authoritative — no useradd/ensure_user call for them below.)
# ---------------------------------------------------------------------------

log "01-users: DONE"
