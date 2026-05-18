#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/99-flags.sh — Lapin Logistics — on-disk flag files
# =============================================================================
# Places the two ON-DISK flags BYTE-EXACT. Flag byte-exactness matters — this
# module is pedantic about it.
#
#   peter.txt   NOT a file on disk. The Warren (assets/warren/app.py) serves
#               the EXACT peter.txt on a successful login. We only log that it
#               is Warren-served.
#   /home/roger/roger.txt   roger.txt, byte-exact. roger:roger, 0400
#                           (only roger reads it).
#   /root/root.txt          root.txt, byte-exact INCLUDING the ASCII carrot's
#                           exact relative spacing, the U+2014 em-dash and the
#                           ASCII apostrophe. root:root, 0400.
#
# BYTE-EXACT METHOD (must match the Warren convention so all 3 flags use ONE
# consistent dedent — verified against assets/warren/app.py PETER_TXT):
#   Each FILE content preserves ALL relative whitespace verbatim (critically
#   the root.txt carrot's internal spacing and its ` " " ` line). Each file
#   ends with exactly ONE trailing newline. Warren's PETER_TXT is built as
#   explicit per-line "....\n" string concatenation with a single trailing
#   "\n"; we mirror that EXACTLY here via printf '%s' of the same per-line
#   form, so peter.txt (Warren-served), roger.txt and root.txt are produced
#   under one identical convention.
#
# DRY-RUN SAFE: every write is is_dry_run-gated; nothing written in dry-run.
# IDEMPOTENT:   authoritative OVERWRITE + re-chmod 0400 each run.
# GRACEFUL:     if roger's home / /root is absent -> warn and skip (no die).
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

log "99-flags: placing on-disk flags (roger.txt, root.txt) byte-exact; peter.txt is Warren-served only"

# ---------------------------------------------------------------------------
# Flag bodies — exact content, all whitespace preserved, produced via
# printf '%s' so the bytes are unambiguous (no echo/heredoc interpolation).
# Mirrors assets/warren/app.py PETER_TXT's per-line "...\n" concatenation
# convention exactly, incl. ONE trailing \n.
#
# roger.txt (byte-exact).
# ---------------------------------------------------------------------------
_ROGER_TXT="\
Roger here. If you're reading this, you've gotten further
than expected. Not bad for a fox.
The Golden Carrot is buried where only root can dig.
FLAG{r0g3r_th4t_r4bb1t}
"

# root.txt (byte-exact). The carrot-art lines have 18 leading spaces; the
# fourth art line is exactly 18 spaces + `" "`. The narrative/FLAG lines have
# no leading space. The em-dash below is U+2014 (UTF-8 e2 80 94); apostrophe
# is ASCII 0x27.
_ROOT_TXT="\
                  ___,
                 (o,o)
                 ({_})
                  \" \"
THE GOLDEN CARROT — Lapin Logistics' deepest secret.
Congratulations: you followed the rabbit all the way down.
FLAG{g0ld3n_c4rr0t_pwn3d}
"

# ---------------------------------------------------------------------------
# _place_flag <dst> <owner:group> <content> -- authoritative overwrite, then
# chown + chmod 0400. Parent dir must already exist (created by 01-users /
# the base system); graceful skip + warn if it does not. Dry-run inert.
# ---------------------------------------------------------------------------
_place_flag() {
    local dst="$1" og="$2" content="$3" parent
    parent="$(dirname "$dst")"
    if [[ ! -d "$parent" ]]; then
        warn "99-flags: parent dir '${parent}' missing — skipping ${dst} (run 01-users.sh / ensure the account exists first)"
        return 0
    fi
    if is_dry_run; then
        log "[DRY-RUN] would authoritatively overwrite ${dst} (byte-exact), chown ${og}, chmod 0400"
        return 0
    fi
    # Authoritative overwrite. printf '%s' — NO trailing newline
    # added by us; the content variable already carries the single trailing
    # \n (matching the Warren PETER_TXT convention exactly).
    printf '%s' "$content" > "$dst"
    chown "$og" "$dst"
    chmod 0400 "$dst"
    log "99-flags: wrote ${dst} ($(wc -c < "$dst") bytes, ${og}, mode 0400)"
}

# ---------------------------------------------------------------------------
# peter.txt — NOT on disk. Served by the Warren on successful login
# (assets/warren/app.py PETER_TXT). We write NOTHING here.
# ---------------------------------------------------------------------------
log "99-flags: peter.txt is NOT placed on disk — the Warren serves it byte-exact on successful login (assets/warren/app.py). No peter.txt written anywhere by this module."

# ---------------------------------------------------------------------------
# roger.txt — /home/roger/roger.txt, roger:roger, 0400.
# ---------------------------------------------------------------------------
if ! id roger >/dev/null 2>&1; then
    warn "99-flags: user 'roger' does not exist (run 01-users.sh first) — skipping roger.txt"
else
    _roger_home="$(getent passwd roger | cut -d: -f6)"
    if [[ -z "$_roger_home" ]]; then
        warn "99-flags: could not resolve roger's home — skipping roger.txt"
    else
        _place_flag "${_roger_home}/roger.txt" "roger:roger" "$_ROGER_TXT"
    fi
    unset _roger_home
fi

# ---------------------------------------------------------------------------
# root.txt — /root/root.txt, root:root, 0400.
# ---------------------------------------------------------------------------
_root_home="$(getent passwd root | cut -d: -f6)"
[[ -n "$_root_home" ]] || _root_home="/root"
_place_flag "${_root_home}/root.txt" "root:root" "$_ROOT_TXT"
unset _root_home

log "99-flags: DONE — roger.txt + root.txt byte-exact (0400); peter.txt left Warren-served"
