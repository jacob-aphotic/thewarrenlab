#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/12-privesc.sh — Lapin Logistics — inventory tooling + cron + sudoers
# =============================================================================
# This module installs the inventory tooling, its cron jobs, and the
# carrot-report sudoers drop-in. All artifacts are deterministic and
# authoritative (idempotent overwrite).
#
# /opt/lapin-tools/ is co-owned with module 11-tarpit (status-beacon.sh):
#   we ALWAYS ensure_dir (never rm) and only ADD files — status-beacon.sh
#   and any sibling-module artifacts are left untouched.
#
# DRY-RUN SAFE: every mutation is via run / ensure_* / is_dry_run-gated blocks.
#               In dry-run NOTHING is written and `visudo` is NEVER invoked.
# IDEMPOTENT:   scripts/crons/sudoers are authoritatively OVERWRITTEN every
#               run; re-running never duplicates or removes anything.
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

log "12-privesc: starting inventory tooling setup"

# ---------------------------------------------------------------------------
# 0. Shared directory — created by 11-tarpit too; ensure_dir is idempotent and
#    NEVER removes the dir, so status-beacon.sh (and any sibling artifacts)
#    survive a re-run. World-readable + traversable.
# ---------------------------------------------------------------------------
ensure_dir /opt/lapin-tools 755 root:root

# ---------------------------------------------------------------------------
# 0a. Scratch dir for the inventory tooling — world-writable + sticky so any
#     user can drop files here but only the owner can remove them.
# ---------------------------------------------------------------------------
ensure_dir /opt/lapin-tools/cache 1777 root:root

# ===========================================================================
# Inventory cron tooling
# ===========================================================================

# ---------------------------------------------------------------------------
# 1a. Ops utilities: a set of small warehouse helper scripts.
#     Generated programmatically. Each is a real, harmless, executable bash
#     script. NONE is named `count`. All authoritatively overwritten so
#     re-runs don't drift.
# ---------------------------------------------------------------------------
_LAPIN_TOOLS=(
    "count-carrots.sh|Tallies carrots in the warehouse manifest (sample data)."
    "email-warehouse.sh|Sends a summary to the warehouse shift lead."
    "print-greeting.sh|Prints the Lapin Logistics daily greeting banner."
    "rotate-bins.sh|Rotates the carrot storage bin labels A->B->C."
    "hutch-census.sh|Counts occupied hutches from a static census file."
    "burrow-status.sh|Reports a canned all-burrows-nominal status line."
    "carrot-grader.sh|Grades a fixed sample of carrots by length bucket."
    "warren-ping.sh|Emits a heartbeat check for the Warren service."
    "lettuce-tally.sh|Adds up a hard-coded lettuce crate count."
    "shift-roster.sh|Prints today's (static) warehouse shift roster."
    "feed-schedule.sh|Prints the feeding schedule for the hutch wing."
    "manifest-checksum.sh|Computes a checksum over a sample manifest string."
    "pallet-report.sh|Summarises pallet utilisation from canned numbers."
    "fluff-counter.sh|Counts fluff units (an internal joke metric) deterministically."
    "carrot-forecast.sh|Prints a weekly carrot-demand forecast."
    "bin-audit.sh|Walks a static bin list and prints OK for each."
    "hop-metrics.sh|Emits hop-distance telemetry for the warren network."
    "tunnel-map.sh|Prints an ASCII map of the tunnel network."
    "carrot-qc.sh|Runs a quality-control pass over sample carrots."
    "warren-uptime.sh|Prints a Warren uptime figure."
    "stock-rotate.sh|Rotates FIFO stock and prints a summary."
    "greeting-card.sh|Prints a seasonal greeting for warehouse staff."
    "carrot-weigh.sh|Prints sample carrot weights and their average."
    "hutch-temp.sh|Prints a static hutch temperature reading."
    "delivery-eta.sh|Prints a delivery ETA for a sample route."
    "label-printer.sh|Renders a sample shipping label to stdout."
    "carrot-color.sh|Classifies a sample carrot colour (always orange)."
    "warehouse-map.sh|Prints a tiny ASCII warehouse floor map."
    "snack-inventory.sh|Lists the break-room snack inventory."
    "morale-report.sh|Prints an upbeat warehouse morale report."
)

log "12-privesc: writing ${#_LAPIN_TOOLS[@]} utilities into /opt/lapin-tools/"
# Pre-loop guard: verify no utility is named `count` regardless of dry-run mode.
# Pure string inspection, no mutation.
for _entry in "${_LAPIN_TOOLS[@]}"; do
    if [[ "${_entry%%|*}" == "count" ]]; then
        die "12-privesc: refusing to create a utility literally named 'count'"
    fi
done
unset _entry
if is_dry_run; then
    for _entry in "${_LAPIN_TOOLS[@]}"; do
        _name="${_entry%%|*}"
        log "[DRY-RUN] would write /opt/lapin-tools/${_name} (mode 0755)"
    done
    unset _entry _name
else
    _i=0
    for _entry in "${_LAPIN_TOOLS[@]}"; do
        _name="${_entry%%|*}"
        _desc="${_entry#*|}"
        _i=$((_i + 1))
        if [[ "$_name" == "count" ]]; then
            die "12-privesc: refusing to create a utility literally named 'count'"
        fi
        # Each utility is a genuine, harmless, deterministic bash script.
        cat > "/opt/lapin-tools/${_name}" <<EOF
#!/bin/bash
# ${_name} — Lapin Logistics warehouse utility
# ${_desc}
# Operational helper. Output is canned sample data — safe to run anytime.
set -u
_TOOL="${_name}"
_SEED=${_i}
echo "[\${_TOOL}] Lapin Logistics warehouse ops — \$(date '+%Y-%m-%d')"
echo "[\${_TOOL}] ${_desc}"
# Deterministic calculation for the reported metric.
_n=\$(( (_SEED * 37 + 11) % 100 ))
echo "[\${_TOOL}] result: \${_n} unit(s) processed, status OK"
exit 0
EOF
        chmod 0755 "/opt/lapin-tools/${_name}"
        chown root:root "/opt/lapin-tools/${_name}"
    done
    log "12-privesc: wrote ${_i} utilities (mode 0755, root:root)"
    unset _entry _name _desc _i
fi

# ---------------------------------------------------------------------------
# 1b. /opt/lapin-tools/daily-inventory.sh — inventory rollup helper.
#     World-readable so users can inspect it.
# ---------------------------------------------------------------------------
log "12-privesc: writing /opt/lapin-tools/daily-inventory.sh"
if is_dry_run; then
    log "[DRY-RUN] would write /opt/lapin-tools/daily-inventory.sh (mode 0755, root:root)"
else
    cat > /opt/lapin-tools/daily-inventory.sh <<'INV_EOF'
#!/bin/bash
# daily-inventory.sh — inventory rollup helper
# Tallies total carrot stock and appends a timestamped line to the inventory log.
cd /opt/lapin-tools
TOTAL=$(count)
echo "$(date): $TOTAL carrots in inventory" >> /var/log/lapin-inventory.log
INV_EOF
    chmod 0755 /opt/lapin-tools/daily-inventory.sh
    chown root:root /opt/lapin-tools/daily-inventory.sh
    log "12-privesc: daily-inventory.sh written (mode 0755, root:root, world-readable)"
fi

# ---------------------------------------------------------------------------
# 1c. Inventory log — referenced by daily-inventory.sh (roger's cron writes it)
#     AND by carrot-report (greps it). Must exist with sane perms so BOTH the
#     cron append and the grep work out of the box.
#     0666 so roger's cron can append even before any successful run.
# ---------------------------------------------------------------------------
log "12-privesc: ensuring /var/log/lapin-inventory.log exists (shared by cron + carrot-report)"
if is_dry_run; then
    log "[DRY-RUN] would create /var/log/lapin-inventory.log (mode 0666, root:root) with a seed line"
else
    if [[ ! -f /var/log/lapin-inventory.log ]]; then
        cat > /var/log/lapin-inventory.log <<'LOG_EOF'
Mon Jan  6 00:05:01 UTC 2025: 412 carrots in inventory
LOG_EOF
    fi
    chmod 0666 /var/log/lapin-inventory.log
    chown root:root /var/log/lapin-inventory.log
    log "12-privesc: /var/log/lapin-inventory.log ready (mode 0666)"
fi

# ---------------------------------------------------------------------------
# 1d. /etc/cron.d/lapin-inventory — authoritative OVERWRITE.
#     EXACT line (cron.d format: m h dom mon dow USER CMD):
#       */1 * * * * roger PATH=/opt/lapin-tools/cache:/usr/local/bin:/usr/bin:/bin /opt/lapin-tools/daily-inventory.sh
#     World-readable 0644 so users can inspect it.
# ---------------------------------------------------------------------------
_LAPIN_CRON_LINE='*/1 * * * * roger PATH=/opt/lapin-tools/cache:/usr/local/bin:/usr/bin:/bin /opt/lapin-tools/daily-inventory.sh'

# Structural sanity check on the cron line (cheap, dry-run safe — pure string
# logic, no mutation).
_lapin_validate_cron_line() {
    local line="$1"
    # Field 1: */1  Field 6: roger  Command must reference daily-inventory.sh
    # and PATH must put /opt/lapin-tools/cache FIRST.
    [[ "$line" == '*/1 * * * * roger PATH=/opt/lapin-tools/cache:'* ]] \
        || { err "12-privesc: cron line malformed (schedule/user/PATH prefix)"; return 1; }
    [[ "$line" == *'/opt/lapin-tools/daily-inventory.sh' ]] \
        || { err "12-privesc: cron line does not invoke daily-inventory.sh"; return 1; }
    local nf
    nf="$(awk '{print NF}' <<<"$line")"
    [[ "$nf" -ge 8 ]] \
        || { err "12-privesc: cron line has too few fields ($nf)"; return 1; }
    return 0
}

_lapin_validate_cron_line "$_LAPIN_CRON_LINE" \
    || die "12-privesc: refusing to install a malformed /etc/cron.d/lapin-inventory"

ensure_dir /etc/cron.d 755 root:root
log "12-privesc: installing /etc/cron.d/lapin-inventory (authoritative overwrite)"
if is_dry_run; then
    log "[DRY-RUN] would overwrite /etc/cron.d/lapin-inventory"
else
    # Authoritative: full overwrite, never append.
    cat > /etc/cron.d/lapin-inventory <<INVCRON_EOF
# Lapin Logistics — carrot inventory rollup (runs as roger every minute)
# m h dom mon dow USER CMD
${_LAPIN_CRON_LINE}
INVCRON_EOF
    chmod 0644 /etc/cron.d/lapin-inventory
    chown root:root /etc/cron.d/lapin-inventory
    log "12-privesc: /etc/cron.d/lapin-inventory written (mode 0644, world-readable)"
fi

# ===========================================================================
# carrot-report sudoers drop-in
# ===========================================================================

# ---------------------------------------------------------------------------
# 2a. /usr/local/bin/carrot-report — generates a regional inventory report.
#     Accepts a region name as argv[1] and greps the inventory log for it.
#     Uses a cat|grep pipeline so grep always has finite stdin.
#     mode 0755, root:root.
# ---------------------------------------------------------------------------
ensure_dir /usr/local/bin 755 root:root
log "12-privesc: writing /usr/local/bin/carrot-report"
if is_dry_run; then
    log "[DRY-RUN] would write /usr/local/bin/carrot-report (mode 0755, root:root)"
else
    cat > /usr/local/bin/carrot-report <<'CR_EOF'
#!/usr/bin/env python3
# carrot-report — generates a regional inventory report
import os, sys
if len(sys.argv) < 2:
    print("Usage: carrot-report <region>")
    sys.exit(1)
region = sys.argv[1]
os.system("cat /var/log/lapin-inventory.log | grep '" + region + "' | tail -20")
CR_EOF
    chmod 0755 /usr/local/bin/carrot-report
    chown root:root /usr/local/bin/carrot-report
    log "12-privesc: /usr/local/bin/carrot-report written (mode 0755, root:root)"
fi

# ---------------------------------------------------------------------------
# 2b. /etc/sudoers.d/carrot-report — authoritative OVERWRITE.
#     EXACT line:  roger ALL=(ALL) NOPASSWD: /usr/local/bin/carrot-report
#
#     SAFETY: a malformed sudoers drop-in can break sudo system-wide. We write
#     to a TEMP file, validate it with `visudo -cf` (real-run only — visudo is
#     NEVER invoked in dry-run), and ONLY install (atomic mv into place, then
#     chown root:root + chmod 0440) if validation passes. On failure we `die`
#     WITHOUT installing — never leave an unvalidated sudoers file behind.
# ---------------------------------------------------------------------------
_LAPIN_SUDOERS_LINE='roger ALL=(ALL) NOPASSWD: /usr/local/bin/carrot-report'
_LAPIN_SUDOERS_DST='/etc/sudoers.d/carrot-report'

ensure_dir /etc/sudoers.d 755 root:root
log "12-privesc: installing ${_LAPIN_SUDOERS_DST} (visudo-validated authoritative overwrite)"
if is_dry_run; then
    log "[DRY-RUN] would validate+install sudoers drop-in ${_LAPIN_SUDOERS_DST} (visudo NOT run in dry-run)"
else
    command -v visudo >/dev/null 2>&1 \
        || die "12-privesc: visudo not found — refusing to install an unvalidated sudoers file"

    _sudo_tmp="$(mktemp /tmp/lapin-sudoers.XXXXXX)" \
        || die "12-privesc: could not create temp file for sudoers validation"
    # Ensure cleanup of the temp file no matter how we leave this block.
    trap 'rm -f "${_sudo_tmp:-}" 2>/dev/null || true' EXIT

    cat > "$_sudo_tmp" <<SUDO_EOF
# Lapin Logistics — roger may run the carrot-report tool as root without a password.
${_LAPIN_SUDOERS_LINE}
SUDO_EOF
    chmod 0440 "$_sudo_tmp"

    # Validate ONLY the candidate file in isolation. visudo -cf returns
    # non-zero on any syntax error; we do not install unless it passes.
    if visudo -cf "$_sudo_tmp" >/dev/null 2>&1; then
        log "12-privesc: sudoers candidate passed 'visudo -cf' — installing"
        # Atomic-ish install: move into place, then lock down ownership/mode.
        mv "$_sudo_tmp" "$_LAPIN_SUDOERS_DST"
        chown root:root "$_LAPIN_SUDOERS_DST"
        chmod 0440 "$_LAPIN_SUDOERS_DST"
        log "12-privesc: ${_LAPIN_SUDOERS_DST} installed (mode 0440, root:root)"
    else
        die "12-privesc: 'visudo -cf' REJECTED the sudoers candidate — NOT installing (sudo left untouched)"
    fi
    # EXIT trap removes _sudo_tmp if it still exists (it won't after mv).
    trap - EXIT
    unset _sudo_tmp
fi

# ===========================================================================
# Secondary cron — log trimmer
# ===========================================================================
# /etc/cron.d/lapin-rotate-logs is world-readable (0644). Its target
# /usr/local/sbin/lapin-logrotate is root:root mode 0750 and uses only
# absolute paths with no relative-binary calls. Authoritative overwrite.
# ---------------------------------------------------------------------------
ensure_dir /usr/local/sbin 755 root:root
log "12-privesc: writing /usr/local/sbin/lapin-logrotate (root:root 0750)"
if is_dry_run; then
    log "[DRY-RUN] would write /usr/local/sbin/lapin-logrotate (mode 0750, root:root)"
else
    cat > /usr/local/sbin/lapin-logrotate <<'ROT_EOF'
#!/bin/bash
# lapin-logrotate — inventory log trimmer (runs as root via cron)
# Keeps the inventory log from growing without bound.
# All paths are absolute.
set -eu
_LOG=/var/log/lapin-inventory.log
if [ -f "$_LOG" ]; then
    /usr/bin/tail -n 5000 "$_LOG" > "${_LOG}.tmp" 2>/dev/null || exit 0
    /bin/mv "${_LOG}.tmp" "$_LOG" 2>/dev/null || exit 0
fi
exit 0
ROT_EOF
    chmod 0750 /usr/local/sbin/lapin-logrotate
    chown root:root /usr/local/sbin/lapin-logrotate
    log "12-privesc: /usr/local/sbin/lapin-logrotate written (0750 root:root)"
fi

# Secondary cron — world-readable 0644, runs as root. Authoritative overwrite.
log "12-privesc: installing /etc/cron.d/lapin-rotate-logs (authoritative overwrite)"
if is_dry_run; then
    log "[DRY-RUN] would overwrite /etc/cron.d/lapin-rotate-logs"
else
    cat > /etc/cron.d/lapin-rotate-logs <<'ROTCRON_EOF'
# Lapin Logistics — rotate the inventory log (runs as root, hourly)
# m h dom mon dow USER CMD
17 * * * * root /usr/local/sbin/lapin-logrotate
ROTCRON_EOF
    chmod 0644 /etc/cron.d/lapin-rotate-logs
    chown root:root /etc/cron.d/lapin-rotate-logs
    log "12-privesc: /etc/cron.d/lapin-rotate-logs written (0644)"
fi

log "12-privesc: DONE"
