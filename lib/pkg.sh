# shellcheck shell=bash
# =============================================================================
# lib/pkg.sh — Lapin Logistics — package manager abstraction
# =============================================================================
# Sourced (never executed). Depends on lib/common.sh (run/log/die/is_dry_run).
# Provides:
#   pkg_install <generic-names...>   — install, translating generic -> distro
#   svc_name    <generic>            — resolve service unit name for this distro
#   svc_enable_now <real-name>       — enable + start a service (idempotent)
#
# Generic package name vocabulary. Modules pass GENERIC names:
#   apache2  vsftpd  samba  snmpd  openssh-server  bind9
#   php  libapache2-mod-php  php-cli  mariadb-server
#   curl wget git python3 python3-pip python3-venv unzip zip jq build-essential
#   socat nmap dnsutils exiftool openssl smbclient
# =============================================================================

if [[ -n "${LAPIN_PKG_SOURCED:-}" ]]; then
    return 0 2>/dev/null || true
fi
LAPIN_PKG_SOURCED=1

# common.sh must be loaded first (for run/log/die). Provide minimal fallbacks
# so this file can still be syntax-checked / sourced standalone.
if ! declare -F log >/dev/null 2>&1;  then log()  { printf '%s\n' "[INFO] $*"; }; fi
if ! declare -F warn >/dev/null 2>&1; then warn() { printf '%s\n' "[WARN] $*" >&2; }; fi
if ! declare -F die >/dev/null 2>&1;  then die()  { printf '%s\n' "[ERROR] $*" >&2; exit 1; }; fi
if ! declare -F run >/dev/null 2>&1;  then run()  { "$@"; }; fi
if ! declare -F is_dry_run >/dev/null 2>&1; then is_dry_run() { [[ "${LAPIN_DRY_RUN:-0}" != "0" ]]; }; fi

# ---- detect package manager -------------------------------------------------
LAPIN_PKG_MGR=""
_lapin_detect_pkg_mgr() {
    local m
    for m in apt-get dnf yum pacman zypper; do
        if command -v "$m" >/dev/null 2>&1; then
            LAPIN_PKG_MGR="$m"
            return 0
        fi
    done
    LAPIN_PKG_MGR=""
    return 1
}
_lapin_detect_pkg_mgr || warn "no supported package manager found (apt-get/dnf/yum/pacman/zypper)"
export LAPIN_PKG_MGR

# ---- name translation -------------------------------------------------------
# _pkg_xlate <generic> -> echoes the space-separated package list for the
# detected manager. Debian/apt is the canonical/generic name in most cases.
_pkg_xlate() {
    local g="$1"
    case "$LAPIN_PKG_MGR" in
        apt-get)
            case "$g" in
                apache2)            echo "apache2" ;;
                libapache2-mod-php) echo "libapache2-mod-php" ;;
                php)                echo "php" ;;
                php-cli)            echo "php-cli" ;;
                bind9)              echo "bind9 bind9-utils" ;;
                snmpd)              echo "snmpd" ;;
                openssh-server)     echo "openssh-server" ;;
                samba)              echo "samba" ;;
                mariadb-server)     echo "mariadb-server" ;;
                dnsutils)           echo "dnsutils" ;;
                exiftool)           echo "libimage-exiftool-perl" ;;
                smbclient)          echo "smbclient" ;;
                build-essential)    echo "build-essential" ;;
                python3-dev)        echo "python3-dev" ;;
                zlib1g-dev)         echo "zlib1g-dev" ;;
                python3-pip)        echo "python3-pip" ;;
                python3-venv)       echo "python3-venv" ;;
                *)                  echo "$g" ;;
            esac ;;
        dnf|yum)
            case "$g" in
                apache2)            echo "httpd" ;;
                libapache2-mod-php) echo "php" ;;
                php)                echo "php" ;;
                php-cli)            echo "php-cli" ;;
                bind9)              echo "bind bind-utils" ;;
                snmpd)              echo "net-snmp net-snmp-utils" ;;
                openssh-server)     echo "openssh-server" ;;
                samba)              echo "samba samba-client" ;;
                mariadb-server)     echo "mariadb-server" ;;
                dnsutils)           echo "bind-utils" ;;
                exiftool)           echo "perl-Image-ExifTool" ;;
                smbclient)          echo "samba-client" ;;
                build-essential)    echo "gcc gcc-c++ make" ;;
                python3-dev)        echo "python3-devel" ;;
                zlib1g-dev)         echo "zlib-devel" ;;
                python3-pip)        echo "python3-pip" ;;
                python3-venv)       echo "python3" ;;
                *)                  echo "$g" ;;
            esac ;;
        pacman)
            case "$g" in
                apache2)            echo "apache" ;;
                libapache2-mod-php) echo "php-apache" ;;
                php)                echo "php" ;;
                php-cli)            echo "php" ;;
                bind9)              echo "bind" ;;
                snmpd)              echo "net-snmp" ;;
                openssh-server)     echo "openssh" ;;
                samba)              echo "samba" ;;
                mariadb-server)     echo "mariadb" ;;
                dnsutils)           echo "bind" ;;
                exiftool)           echo "perl-image-exiftool" ;;
                smbclient)          echo "smbclient" ;;
                build-essential)    echo "base-devel" ;;
                python3-dev)        echo "python" ;;
                zlib1g-dev)         echo "zlib" ;;
                python3-pip)        echo "python-pip" ;;
                python3-venv)       echo "python" ;;
                python3)            echo "python" ;;
                *)                  echo "$g" ;;
            esac ;;
        zypper)
            case "$g" in
                apache2)            echo "apache2" ;;
                libapache2-mod-php) echo "apache2-mod_php8" ;;
                php)                echo "php8" ;;
                php-cli)            echo "php8-cli" ;;
                bind9)              echo "bind bind-utils" ;;
                snmpd)              echo "net-snmp" ;;
                openssh-server)     echo "openssh" ;;
                samba)              echo "samba samba-client" ;;
                mariadb-server)     echo "mariadb" ;;
                dnsutils)           echo "bind-utils" ;;
                exiftool)           echo "exiftool" ;;
                smbclient)          echo "samba-client" ;;
                build-essential)    echo "gcc make" ;;
                python3-dev)        echo "python3-devel" ;;
                zlib1g-dev)         echo "zlib-devel" ;;
                python3-pip)        echo "python3-pip" ;;
                python3-venv)       echo "python3" ;;
                *)                  echo "$g" ;;
            esac ;;
        *)
            # Unknown manager: pass through generic name unchanged.
            echo "$g" ;;
    esac
}

# ---- pkg_install <generic-names...> ----------------------------------------
# Idempotent in spirit: the package managers themselves no-op on already
# installed packages; we just translate names and invoke once for the batch.
pkg_install() {
    [[ "$#" -gt 0 ]] || { warn "pkg_install: called with no packages"; return 0; }
    local g
    local -a real_list=()
    for g in "$@"; do
        # shellcheck disable=SC2207
        real_list+=( $(_pkg_xlate "$g") )
    done
    [[ "${#real_list[@]}" -gt 0 ]] || { warn "pkg_install: nothing to install"; return 0; }
    log "pkg_install: generic[$*] -> ${LAPIN_PKG_MGR}[${real_list[*]}]"

    case "$LAPIN_PKG_MGR" in
        apt-get)
            # `apt-get update` is ADVISORY here, not load-bearing: on an
            # idempotent re-run a transient mirror hiccup must not abort the
            # whole install. Still wrapped by `run` for dry-run. The
            # install step below remains FATAL on failure.
            if ! run env DEBIAN_FRONTEND=noninteractive apt-get update -y; then
                warn "apt-get update failed (continuing; will install with the existing package index)"
            fi
            run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${real_list[@]}"
            ;;
        dnf)
            run dnf install -y "${real_list[@]}"
            ;;
        yum)
            run yum install -y "${real_list[@]}"
            ;;
        pacman)
            run pacman -Sy --noconfirm --needed "${real_list[@]}"
            ;;
        zypper)
            run zypper --non-interactive install -y "${real_list[@]}"
            ;;
        *)
            die "pkg_install: no supported package manager detected; cannot install: ${real_list[*]}"
            ;;
    esac
}

# ---- svc_name <generic> -----------------------------------------------------
# Resolve a generic service handle to the actual service/unit name for this
# distro. Always use this instead of hardcoding apache2/httpd.
# Generic handles: apache2 smb nmb vsftpd named snmpd ssh mariadb
svc_name() {
    local g="$1"
    local fam="${LAPIN_DISTRO_FAMILY:-debian}"
    case "$g" in
        apache2|httpd)
            case "$fam" in
                debian|suse) echo "apache2" ;;
                *)           echo "httpd" ;;
            esac ;;
        smb|smbd)
            case "$fam" in
                debian)      echo "smbd" ;;
                *)           echo "smb" ;;
            esac ;;
        nmb|nmbd)
            case "$fam" in
                debian)      echo "nmbd" ;;
                *)           echo "nmb" ;;
            esac ;;
        vsftpd) echo "vsftpd" ;;
        named|bind|bind9|dns)
            # All supported families ship the daemon as 'named.service'
            # (Debian's bind9 package adds a 'bind9.service' alias that also
            # resolves to it), so there is intentionally nothing to branch on.
            echo "named" ;;
        snmpd|net-snmp)
            case "$fam" in
                debian|suse) echo "snmpd" ;;
                *)           echo "snmpd" ;;
            esac ;;
        ssh|sshd|openssh-server|openssh)
            case "$fam" in
                debian)      echo "ssh" ;;
                *)           echo "sshd" ;;
            esac ;;
        mariadb|mariadb-server|mysql)
            case "$fam" in
                debian)      echo "mariadb" ;;
                *)           echo "mariadb" ;;
            esac ;;
        *) echo "$g" ;;
    esac
}

# ---- svc_enable_now <real-name> --------------------------------------------
# Idempotent enable + (re)start. Honors dry-run and init system.
svc_enable_now() {
    local svc="$1"
    [[ -n "$svc" ]] || die "svc_enable_now: service name required"
    local init="${LAPIN_INIT:-systemd}"
    case "$init" in
        systemd)
            if command -v systemctl >/dev/null 2>&1; then
                run systemctl enable "$svc"
                run systemctl restart "$svc"
                return 0
            fi
            ;;
        openrc)
            if command -v rc-update >/dev/null 2>&1; then
                run rc-update add "$svc" default
                run rc-service "$svc" restart
                return 0
            fi
            ;;
    esac
    # Fallbacks.
    if command -v systemctl >/dev/null 2>&1; then
        run systemctl enable --now "$svc"
    elif command -v service >/dev/null 2>&1; then
        run service "$svc" restart
    else
        warn "svc_enable_now: no init system found to enable '$svc'"
    fi
}
