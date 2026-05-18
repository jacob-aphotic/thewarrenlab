# shellcheck shell=bash
# =============================================================================
# lib/distro.sh — Lapin Logistics — distro + init system detection
# =============================================================================
# Sourced (never executed). Depends on lib/common.sh (log/warn/die).
#
# Exports for the rest of the codebase:
#   LAPIN_DISTRO_ID      raw ID from /etc/os-release (ubuntu/debian/fedora/...)
#   LAPIN_DISTRO_NAME    pretty name for messaging
#   LAPIN_DISTRO_FAMILY  debian|rhel|arch|suse|alpine|bsd|unknown
#   LAPIN_INIT           systemd|openrc|sysv|unknown
#   LAPIN_DISTRO_TESTED  1 = on the tested/supported path; 0 = warn user
#
# Calls lapin_distro_guard() which, for untested distros, prints the EXACT
# warning from the plan and prompts to continue (auto-yes if LAPIN_ASSUME_YES=1).
# =============================================================================

if [[ -n "${LAPIN_DISTRO_SOURCED:-}" ]]; then
    return 0 2>/dev/null || true
fi
LAPIN_DISTRO_SOURCED=1

# minimal fallbacks if common.sh not yet loaded (keeps standalone sourcing safe)
if ! declare -F log >/dev/null 2>&1;  then log()  { printf '%s\n' "[INFO] $*"; }; fi
if ! declare -F warn >/dev/null 2>&1; then warn() { printf '%s\n' "[WARN] $*" >&2; }; fi
if ! declare -F die >/dev/null 2>&1;  then die()  { printf '%s\n' "[ERROR] $*" >&2; exit 1; }; fi

LAPIN_DISTRO_ID="unknown"
LAPIN_DISTRO_NAME="unknown"
LAPIN_DISTRO_FAMILY="unknown"
LAPIN_INIT="unknown"
LAPIN_DISTRO_TESTED=0

# ---- distro detection -------------------------------------------------------
_lapin_detect_distro() {
    local id="" id_like="" name="" uname_s
    uname_s="$(uname -s 2>/dev/null || echo unknown)"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        id_like="${ID_LIKE:-}"
        name="${PRETTY_NAME:-${NAME:-}}"
    fi

    # BSDs have no /etc/os-release
    if [[ -z "$id" ]]; then
        case "$uname_s" in
            *BSD*|Darwin) id="$(echo "$uname_s" | tr '[:upper:]' '[:lower:]')" ;;
        esac
    fi

    LAPIN_DISTRO_ID="${id:-unknown}"
    LAPIN_DISTRO_NAME="${name:-$LAPIN_DISTRO_ID}"

    # Family classification from ID + ID_LIKE.
    local probe="$LAPIN_DISTRO_ID $id_like"
    case " $probe " in
        *" ubuntu "*|*" debian "*|*" linuxmint "*|*" pop "*|*" kali "*|*" raspbian "*)
            LAPIN_DISTRO_FAMILY="debian" ;;
        *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*|*" amzn "*)
            LAPIN_DISTRO_FAMILY="rhel" ;;
        *" arch "*|*" archarm "*|*" manjaro "*|*" endeavouros "*)
            LAPIN_DISTRO_FAMILY="arch" ;;
        *" opensuse"*|*" sles "*|*" suse "*|*"opensuse-"*)
            LAPIN_DISTRO_FAMILY="suse" ;;
        *" alpine "*)
            LAPIN_DISTRO_FAMILY="alpine" ;;
        *bsd*|*darwin*)
            LAPIN_DISTRO_FAMILY="bsd" ;;
        *)
            LAPIN_DISTRO_FAMILY="unknown" ;;
    esac

    # Tested/supported path = the families with a real package path
    #.
    case "$LAPIN_DISTRO_FAMILY" in
        debian|rhel|arch) LAPIN_DISTRO_TESTED=1 ;;
        *)                LAPIN_DISTRO_TESTED=0 ;;
    esac
}

# ---- init system detection --------------------------------------------------
_lapin_detect_init() {
    if [[ -d /run/systemd/system ]] || ( command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1 ); then
        LAPIN_INIT="systemd"
    elif command -v rc-service >/dev/null 2>&1 || command -v openrc >/dev/null 2>&1; then
        LAPIN_INIT="openrc"
    elif [[ -d /etc/init.d ]] && command -v service >/dev/null 2>&1; then
        LAPIN_INIT="sysv"
    else
        LAPIN_INIT="unknown"
    fi
}

_lapin_detect_distro
_lapin_detect_init
export LAPIN_DISTRO_ID LAPIN_DISTRO_NAME LAPIN_DISTRO_FAMILY LAPIN_INIT LAPIN_DISTRO_TESTED

# ---- untested-distro guard --------------------------------------------------
# Prints the EXACT warning/prompt from the plan for untested distros and
# requires confirmation. LAPIN_ASSUME_YES=1 (or --yes via install.sh) skips it.
lapin_distro_guard() {
    log "distro: ${LAPIN_DISTRO_NAME} (id=${LAPIN_DISTRO_ID}, family=${LAPIN_DISTRO_FAMILY}, init=${LAPIN_INIT})"

    if [[ "$LAPIN_DISTRO_TESTED" == "1" ]]; then
        if [[ "$LAPIN_DISTRO_FAMILY" != "debian" ]]; then
            warn "non-primary distro family '${LAPIN_DISTRO_FAMILY}': best-effort path, expect some manual fixes."
        fi
        return 0
    fi

    # Untested: openSUSE / Alpine / BSD / unknown.
    printf '%s\n' "[WARN] Detected ${LAPIN_DISTRO_NAME}. This script is tested on Ubuntu;"
    printf '%s\n' "       proceeding but expect manual fixes. Continue? [y/N]"

    if [[ "${LAPIN_ASSUME_YES:-0}" == "1" ]]; then
        log "LAPIN_ASSUME_YES=1 -> auto-continuing on untested distro"
        return 0
    fi

    local reply=""
    if [[ -t 0 ]]; then
        read -r reply || reply=""
    else
        # No TTY and not auto-yes: refuse rather than guess.
        die "untested distro and no TTY to confirm (set LAPIN_ASSUME_YES=1 to proceed)"
    fi
    case "$reply" in
        y|Y|yes|YES) log "user confirmed; continuing on untested distro" ;;
        *)           die "aborted by user on untested distro" ;;
    esac
}
