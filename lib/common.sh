# shellcheck shell=bash
# =============================================================================
# lib/common.sh — Lapin Logistics — logging, safety, idempotency helpers
# =============================================================================
# This file is the foundation sourced by install.sh AND every modules/NN-*.sh.
# It is *sourced*, never executed directly. It must be safe to source multiple
# times (idempotent guard below) and must not have side effects on `source`.
#
# -----------------------------------------------------------------------------
# MODULE AUTHOR CONTRACT  (read this before writing any modules/NN-*.sh)
# -----------------------------------------------------------------------------
# 1. SOURCING
#    Every module begins with the standard preamble:
#
#        #!/usr/bin/env bash
#        set -euo pipefail
#        LAPIN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
#        # shellcheck source=../lib/common.sh
#        source "$LAPIN_LIB_DIR/common.sh"
#        # shellcheck source=../lib/pkg.sh
#        source "$LAPIN_LIB_DIR/pkg.sh"
#        # shellcheck source=../lib/distro.sh
#        source "$LAPIN_LIB_DIR/distro.sh"
#
#    install.sh sources the libs ONCE and then sources each module in the same
#    shell, so a module may assume the libs are already loaded — but the
#    re-source guards make the preamble above safe and self-contained too
#    (so a module can also be run standalone for debugging).
#
# 2. LOGGING
#    Use ONLY these functions for human-facing output (they all tee to
#    /var/log/lapin-install.log with an ISO-8601 timestamp + level):
#        log   "msg"   -> [INFO]
#        warn  "msg"   -> [WARN]
#        err   "msg"   -> [ERROR]   (does NOT exit)
#        die   "msg"   -> [ERROR] then exit 1
#    Never `echo` progress directly; use log/warn/err so the transcript is
#    captured. Raw command output (curl/dig/etc.) may go to stdout normally.
#
# 3. DRY-RUN
#    The single source of truth is the env var LAPIN_DRY_RUN.
#        LAPIN_DRY_RUN in {1, true, yes} (case-insensitive)
#                         -> dry run, make NO system changes
#        anything else (0, false, no, empty, unset, ...)
#                         -> real run (default; unset is treated as 0)
#    Note `LAPIN_DRY_RUN=false` is a REAL run, not a dry run.
#    install.sh sets/exports it from the --dry-run flag before sourcing
#    modules. In a module:
#      * Use `is_dry_run` in `if` tests for custom logic.
#      * Wrap any system-mutating command in `run`:
#            run useradd -m -u 1100 peter
#        In dry-run `run` prints "[DRY-RUN] would: useradd -m ..." and does
#        nothing. In a real run it executes the command and dies on failure.
#      * The ensure_* helpers below already honor dry-run internally, so
#        prefer them over raw commands.
#      * For here-doc / file writes that `run` can't wrap, gate manually:
#            if is_dry_run; then
#                log "[DRY-RUN] would write /etc/foo.conf"
#            else
#                cat > /etc/foo.conf <<'EOF'
#                ...
#                EOF
#            fi
#
# 4. IDEMPOTENCY (every module must be safe to re-run)
#    Prefer these helpers; they no-op when the desired state already exists:
#        ensure_user   <name> [uid] [shell] [extra useradd args...]
#            Creates a home dir (-m) by DEFAULT. If the extra args contain
#            --system, --no-create-home, or -M, the implicit -m is SUPPRESSED
#            (a system/no-home account must not get a home, and
#            `useradd -m ... --no-create-home` is a self-conflicting call).
#        ensure_dir    <path> [mode] [owner[:group]]
#        ensure_pkg    <generic-pkg-names...>      (delegates to pkg.sh)
#        ensure_service_enabled <generic-svc-name> (resolves via svc_name)
#        ensure_line   <file> <line>               (adds line if absent)
#    Config files that must be authoritative (cron, sudoers) are ALWAYS
#    overwritten, never appended (see the plan).
#
# 5. ROOT
#    install.sh calls require_root() once. A standalone-run module should
#    call require_root() too. ensure_* assume EUID 0 on a real run.
#    require_root() enforces EUID 0 on a real run and dies otherwise; under
#    LAPIN_DRY_RUN it is skipped (a dry run mutates nothing, so root is not
#    required) so `install.sh --dry-run` can be previewed unprivileged.
#
# 6. EXPORTED STATE you may rely on (set by distro.sh / pkg.sh):
#        $LAPIN_DISTRO_ID     e.g. ubuntu debian fedora rhel arch opensuse
#        $LAPIN_DISTRO_FAMILY  one of: debian rhel arch suse alpine bsd unknown
#        $LAPIN_INIT          one of: systemd openrc sysv unknown
#        $LAPIN_PKG_MGR       one of: apt-get dnf yum pacman zypper
#    Functions: pkg_install, svc_name, svc_enable_now (from pkg.sh).
#
# 7. EXIT / ERRORS
#    `set -euo pipefail` + the ERR trap installed here mean an unguarded
#    failing command aborts the module with a logged "file:line" location.
#    The trap reports BASH_SOURCE[1]:BASH_LINENO[0] — i.e. it attributes the
#    failure to the actual offending file (this module / a lib / install.sh
#    top-level), NOT to common.sh. It only falls back to common.sh:$LINENO in
#    a degenerate context where no source frame exists (interactive / `-c`).
#    NOTE: ERR traps are NOT inherited by subshells. install.sh runs each
#    module in a subshell that explicitly re-arms `trap '_lapin_on_err' ERR`,
#    so attribution works there; if you spawn your OWN subshell `( ... )` and
#    want the same behavior, re-arm the trap inside it. Use `cmd || true` only
#    when failure is genuinely acceptable, and log why.
#
# 8. ENV VARS honored by the framework:
#        LAPIN_DRY_RUN          (see #3)
#        LAPIN_HUTCH_SIZE_MB    (default 200; used by modules/13-decoys.sh)
#        LAPIN_LOG_FILE         (default /var/log/lapin-install.log)
#        LAPIN_ASSUME_YES       (=1 auto-answers the untested-distro prompt)
# -----------------------------------------------------------------------------

# ---- re-source guard (functions/idempotent; vars below are safe to re-init) --
if [[ -n "${LAPIN_COMMON_SOURCED:-}" ]]; then
    return 0 2>/dev/null || true
fi
LAPIN_COMMON_SOURCED=1

# ---- configuration ----------------------------------------------------------
: "${LAPIN_LOG_FILE:=/var/log/lapin-install.log}"
: "${LAPIN_DRY_RUN:=0}"
: "${LAPIN_HUTCH_SIZE_MB:=200}"
export LAPIN_LOG_FILE LAPIN_DRY_RUN LAPIN_HUTCH_SIZE_MB

# Best-effort: make sure the log file is writable. During --dry-run or when
# not root we may not be able to create /var/log/...; fall back to a temp file
# so logging never aborts the script.
_lapin_init_log() {
    if [[ -w "$LAPIN_LOG_FILE" ]]; then
        return 0
    fi
    if ( : >>"$LAPIN_LOG_FILE" ) 2>/dev/null; then
        return 0
    fi
    local fallback="${TMPDIR:-/tmp}/lapin-install.log"
    if ( : >>"$fallback" ) 2>/dev/null; then
        LAPIN_LOG_FILE="$fallback"
        return 0
    fi
    # Last resort: discard file logging, keep stdout.
    LAPIN_LOG_FILE="/dev/null"
}
_lapin_init_log

# ---- timestamp helper -------------------------------------------------------
_lapin_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }

# ---- core logging (tee to stdout + log file) --------------------------------
# Internal writer: _lapin_emit <LEVEL> <message...>
_lapin_emit() {
    local level="$1"; shift
    local line
    line="$(_lapin_ts) [$level] $*"
    # tee to stdout + logfile; never let a logging failure kill the script.
    printf '%s\n' "$line" | tee -a "$LAPIN_LOG_FILE" 2>/dev/null || printf '%s\n' "$line"
}

log()  { _lapin_emit "INFO"  "$@"; }
warn() { _lapin_emit "WARN"  "$@" >&2; }
err()  { _lapin_emit "ERROR" "$@" >&2; }

# die: log error and exit 1
die() {
    _lapin_emit "ERROR" "$@" >&2
    exit 1
}

# ---- ERR trap: print failing line number then exit --------------------------
# Modules inherit this only if they re-arm it in their subshell (install.sh's
# module runner does); install.sh itself and standalone-run modules inherit it
# directly because they are the same shell that sourced this file.
#
# Frame model: when this function runs, frame 0 is _lapin_on_err itself
# (BASH_SOURCE[0]=common.sh). The failing command lives one frame up, so the
# real source file is BASH_SOURCE[1] and the real line is BASH_LINENO[0].
# BASH_SOURCE[1] is reliably set whenever the failure is at the top level of a
# script (install.sh), inside a sourced module, or inside a lib function — the
# only time it is empty is a degenerate interactive/-c context, for which we
# fall back to common.sh + $LINENO rather than mis-blaming a real file.
_lapin_on_err() {
    local ec=$?
    local src="${BASH_SOURCE[1]:-}"
    local ln="${BASH_LINENO[0]:-}"
    if [[ -z "$src" ]]; then
        src="${BASH_SOURCE[0]:-?}"
        ln="${ln:-${LINENO}}"
    fi
    : "${ln:=?}"
    _lapin_emit "ERROR" "command failed (exit $ec) at ${src}:${ln}: ${BASH_COMMAND}" >&2
    exit "$ec"
}
trap '_lapin_on_err' ERR

# ---- root check -------------------------------------------------------------
require_root() {
    if is_dry_run; then
        warn "require_root: dry-run — root check skipped (dry run mutates nothing)"
        return 0
    fi
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "must be run as root (EUID 0). Try: sudo $0"
    fi
}

# ---- dry-run plumbing -------------------------------------------------------
# Truthy ONLY for 1 / true / yes (case-insensitive). Everything else —
# including 0, false, no, "" and any other value — is treated as a REAL run,
# so e.g. LAPIN_DRY_RUN=false is (correctly) NOT a dry run.
is_dry_run() {
    case "${LAPIN_DRY_RUN:-0}" in
        [1]|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]) return 0 ;;
        *)                                  return 1 ;;
    esac
}

# run <cmd...> — execute, or in dry-run just print intent. Aborts on failure
# during a real run (consistent with set -e / ERR trap).
run() {
    if is_dry_run; then
        log "[DRY-RUN] would: $*"
        return 0
    fi
    log "exec: $*"
    "$@"
}

# ---- idempotency helpers ----------------------------------------------------

# ensure_dir <path> [mode] [owner[:group]]
ensure_dir() {
    local path="$1" mode="${2:-}" owner="${3:-}"
    if [[ -z "$path" ]]; then die "ensure_dir: path required"; fi
    if [[ ! -d "$path" ]]; then
        run mkdir -p "$path"
    fi
    if [[ -n "$mode" ]]; then run chmod "$mode" "$path"; fi
    if [[ -n "$owner" ]]; then run chown "$owner" "$path"; fi
}

# ensure_user <name> [uid] [shell] [extra useradd args...]
# Creates the user if missing. Existing users are left alone (idempotent);
# uid/shell are NOT forcibly rewritten to avoid clobbering a re-run target.
ensure_user() {
    local name="$1"; shift || true
    [[ -n "$name" ]] || die "ensure_user: name required"
    local uid="" shell="/bin/bash"
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then uid="$1"; shift; fi
    if [[ "${1:-}" == /* ]]; then shell="$1"; shift; fi
    if id "$name" >/dev/null 2>&1; then
        log "user '$name' already exists; leaving as-is"
        return 0
    fi
    # By default create the home directory (-m). But a caller asking for a
    # system / no-home account (--system, --no-create-home, or -M) must NOT
    # get -m: `useradd -m ... --no-create-home` is a self-conflicting invocation
    # and a system account legitimately wants no home. Scan the caller's extra
    # args; suppress -m if any of those flags is present.
    local create_home=1 a
    for a in "$@"; do
        case "$a" in
            --no-create-home|-M|--system) create_home=0 ;;
        esac
    done
    local args=(useradd)
    if [[ "$create_home" -eq 1 ]]; then args+=(-m); fi
    args+=(-s "$shell")
    if [[ -n "$uid" ]]; then args+=(-u "$uid"); fi
    if [[ "$#" -gt 0 ]]; then args+=("$@"); fi
    args+=("$name")
    run "${args[@]}"
}

# ensure_pkg <generic-names...> — delegates to pkg_install from lib/pkg.sh.
ensure_pkg() {
    if ! declare -F pkg_install >/dev/null 2>&1; then
        die "ensure_pkg: pkg_install not loaded (source lib/pkg.sh first)"
    fi
    pkg_install "$@"
}

# ensure_service_enabled <generic-svc-name> — resolve real name + enable/start.
ensure_service_enabled() {
    local generic="$1"
    [[ -n "$generic" ]] || die "ensure_service_enabled: name required"
    local real="$generic"
    if declare -F svc_name >/dev/null 2>&1; then
        real="$(svc_name "$generic")"
    fi
    if declare -F svc_enable_now >/dev/null 2>&1; then
        svc_enable_now "$real"
        return $?
    fi
    # Fallback if pkg.sh helper unavailable: best-effort systemd.
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl enable --now "$real"
    else
        warn "no service manager helper available to enable '$real'"
    fi
}

# ensure_line <file> <line> — append line if not already present (idempotent).
# Use for additive config only; authoritative files must be fully overwritten.
ensure_line() {
    local file="$1" line="$2"
    [[ -n "$file" ]] || die "ensure_line: file required"
    if [[ -f "$file" ]] && grep -qxF -- "$line" "$file" 2>/dev/null; then
        return 0
    fi
    if is_dry_run; then
        log "[DRY-RUN] would append to $file: $line"
        return 0
    fi
    ensure_dir "$(dirname "$file")"
    printf '%s\n' "$line" >>"$file"
    log "appended to $file: $line"
}

# ---- Apache helpers ---------------------------------------------------------
# apache_port_listened <port> [file...] — return 0 if Apache is ALREADY
# configured to Listen on <port>, else 1. Indentation- and <IfModule>-aware:
# Debian/Ubuntu stock /etc/apache2/ports.conf ships a TAB-indented
# `Listen 443` inside `<IfModule ssl_module>` (activated by `a2enmod ssl`).
# A whole-line exact match (ensure_line's `grep -qxF`) MISSES that and would
# append a duplicate bare `Listen 443` -> two active Listen 443 once ssl is
# enabled -> `AH00072 (98) Address already in use` -> apache fails to start.
# This predicate matches a `Listen` directive for the port at any indentation
# (optionally prefixed with IP:/[::]:/*: ), so callers add a Listen ONLY when
# the port is genuinely not already listened.
apache_port_listened() {
    local port="$1"; shift
    local files=("$@")
    [[ ${#files[@]} -gt 0 ]] || files=(/etc/apache2/ports.conf)
    [[ -n "$port" ]] || return 1
    local f
    for f in "${files[@]}"; do
        [[ -f "$f" ]] || continue
        # ERE: optional leading ws, Listen, ws, optional addr prefix, exact port, then ws/EOL.
        if grep -Eq "^[[:space:]]*Listen[[:space:]]+([0-9.]+:|\[[0-9A-Fa-f:]+\]:|\*:)?${port}([[:space:]]|$)" "$f" 2>/dev/null; then
            return 0
        fi
    done
    return 1
}

# apache_restart_safe — validate the Apache config BEFORE (re)starting, and on
# failure surface the real reason (config test output + journal) instead of a
# silent module exit 1. Then enable+restart via the standard service helper.
# Dry-run inert (no configtest, no restart). Use this instead of a bare
# `ensure_service_enabled apache2` in modules that mutate Apache config.
apache_restart_safe() {
    if is_dry_run; then
        log "[DRY-RUN] would: apache config test + enable/restart apache2"
        return 0
    fi
    local tester="" svc="apache2"
    if command -v apache2ctl >/dev/null 2>&1; then tester="apache2ctl"
    elif command -v apachectl >/dev/null 2>&1; then tester="apachectl"
    elif command -v httpd     >/dev/null 2>&1; then tester="httpd"; svc="httpd"
    fi
    if [[ -n "$tester" ]]; then
        local _ct
        if ! _ct="$("$tester" -t 2>&1)"; then
            err "apache config test FAILED:"
            local _l; while IFS= read -r _l; do err "  configtest: $_l"; done <<<"$_ct"
            if command -v journalctl >/dev/null 2>&1; then
                local _j
                _j="$(journalctl -xeu "$svc" --no-pager -n 40 2>/dev/null || true)"
                while IFS= read -r _l; do [[ -n "$_l" ]] && err "  journal: $_l"; done <<<"$_j"
            fi
            die "apache_restart_safe: Apache config invalid — refusing to restart (see configtest/journal above)."
        fi
    else
        warn "apache_restart_safe: no apache config tester found; restarting without pre-validation"
    fi
    ensure_service_enabled apache2
}

# ---- help rendering ---------------------------------------------------------
# _render_help <file> — print the help/usage text from <file>'s header. The
# text is delimited by sentinel comment markers so it never drifts onto raw
# code when the header is edited:
#       # >>> USAGE
#       # ...help lines...
#       # <<< USAGE
# Only the lines strictly between the markers are printed, with the leading
# "# " (or bare "#") comment prefix stripped.
_render_help() {
    local file="${1:-${BASH_SOURCE[1]:-?}}"
    sed -n '/^# >>> USAGE$/,/^# <<< USAGE$/{ /^# >>> USAGE$/d; /^# <<< USAGE$/d; s/^# \{0,1\}//; p; }' "$file"
}

# ---- misc -------------------------------------------------------------------
# primary non-loopback IPv4 of the host (best-effort, never fails the script)
lapin_host_ip() {
    local ip=""
    if command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')"
    fi
    if [[ -z "$ip" ]] && command -v hostname >/dev/null 2>&1; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    fi
    [[ -n "$ip" ]] || ip="127.0.0.1"
    printf '%s' "$ip"
}
