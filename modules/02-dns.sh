#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/02-dns.sh — Lapin Logistics — bind9 authoritative DNS
# =============================================================================
# Configures bind9 as authoritative server for lapinlogistics.local with
# allow-transfer { any; }. Zone file includes all A/CNAME records.
#
# Resolved/stub-listener conflict:
#   On systemd distros, systemd-resolved may hold :53. This module disables
#   DNSStubListener in /etc/systemd/resolved.conf and restarts resolved so
#   bind9 can bind the port. install.sh's handle_resolved() also does this;
#   the assertion here makes the module idempotent when run standalone.
#   AppArmor / SELinux are handled centrally by install.sh's handle_lsm().
#
# DRY-RUN SAFE: all mutations via run / is_dry_run-gated here-docs.
# IDEMPOTENT:   config files are authoritatively overwritten; service enable
#               is idempotent via ensure_service_enabled.
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

log "02-dns: starting bind9 / lapinlogistics.local setup"

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
log "02-dns: ensuring bind9 package"
ensure_pkg bind9

# ---------------------------------------------------------------------------
# 2. Detect host IP (substituted into the zone file at install time)
# ---------------------------------------------------------------------------
_HOST_IP="$(lapin_host_ip)"
log "02-dns: detected host IP: ${_HOST_IP}"

# ---------------------------------------------------------------------------
# 3. Resolve distro-specific paths
#    Debian/Ubuntu: /etc/bind/named.conf.options   /etc/bind/named.conf.local
#                   zones in /etc/bind/zones/
#    RHEL/Fedora:   /etc/named.conf (monolithic)   zones in /var/named/
#    Arch/others:   same as RHEL
# ---------------------------------------------------------------------------
case "${LAPIN_DISTRO_FAMILY:-debian}" in
    debian)
        _BIND_CONF_DIR="/etc/bind"
        _BIND_OPTIONS="${_BIND_CONF_DIR}/named.conf.options"
        _BIND_LOCAL="${_BIND_CONF_DIR}/named.conf.local"
        _ZONE_DIR="${_BIND_CONF_DIR}/zones"
        ;;
    *)
        _BIND_CONF_DIR="/etc"
        _BIND_OPTIONS="/etc/named.conf"
        _BIND_LOCAL="/etc/named.conf"
        _ZONE_DIR="/var/named"
        ;;
esac
_ZONE_FILE="${_ZONE_DIR}/db.lapinlogistics.local"

# ---------------------------------------------------------------------------
# 4. Ensure zone directory exists
# ---------------------------------------------------------------------------
ensure_dir "$_ZONE_DIR" 755

# ---------------------------------------------------------------------------
# 5. Disable systemd-resolved DNSStubListener so bind9 can bind :53
#    (idempotent; no-op if already set or if not systemd)
# ---------------------------------------------------------------------------
if [[ "${LAPIN_INIT:-}" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
    log "02-dns: asserting systemd-resolved DNSStubListener=no"
    if is_dry_run; then
        log "[DRY-RUN] would write DNSStubListener=no to /etc/systemd/resolved.conf"
    else
        # Idempotent: overwrite the [Resolve] section stub line if needed.
        if ! grep -qs '^DNSStubListener=no' /etc/systemd/resolved.conf 2>/dev/null; then
            # Append under the [Resolve] section if it exists, else just append.
            if grep -qs '^\[Resolve\]' /etc/systemd/resolved.conf 2>/dev/null; then
                run sed -i '/^\[Resolve\]/a DNSStubListener=no' /etc/systemd/resolved.conf
            else
                # bare append — run cannot wrap a shell redirection
                printf '[Resolve]\nDNSStubListener=no\n' >> /etc/systemd/resolved.conf
            fi
            log "02-dns: set DNSStubListener=no in /etc/systemd/resolved.conf"
        else
            log "02-dns: DNSStubListener=no already set; skipping"
        fi
        # Restart resolved to release :53, then ensure /etc/resolv.conf is sane.
        if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
            run systemctl restart systemd-resolved
            log "02-dns: systemd-resolved restarted"
        fi
        # /etc/resolv.conf: if it is the stub symlink, relink — with a bounded
        # wait (I3) for resolved to write the target file after restart.
        if [[ -L /etc/resolv.conf ]]; then
            _rv_target="$(readlink /etc/resolv.conf)"
            if [[ "$_rv_target" == *stub* ]]; then
                _tries=0
                while [[ ! -f /run/systemd/resolve/resolv.conf ]] && (( _tries++ < 10 )); do sleep 0.5; done
                if [[ -f /run/systemd/resolve/resolv.conf ]]; then
                    run ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
                    log "02-dns: /etc/resolv.conf relinked to systemd-resolved stub-free resolver"
                else
                    warn "02-dns: /run/systemd/resolve/resolv.conf not available yet; skipping relink"
                fi
                unset _tries
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. Write named.conf.options (or the options block if monolithic)
#    Authoritative only; no recursion so this server won't be abused as open
#    resolver. listen-on any so it binds all interfaces.
# ---------------------------------------------------------------------------
log "02-dns: writing bind9 options -> ${_BIND_OPTIONS}"
if is_dry_run; then
    log "[DRY-RUN] would write ${_BIND_OPTIONS}"
else
    case "${LAPIN_DISTRO_FAMILY:-debian}" in
        debian)
            cat > "$_BIND_OPTIONS" <<'NAMED_OPTIONS_EOF'
options {
    directory "/var/cache/bind";

    listen-on { any; };
    listen-on-v6 { any; };

    allow-transfer { any; };
    recursion no;
    allow-query { any; };

    dnssec-validation no;
};
NAMED_OPTIONS_EOF
            ;;
        *)
            # On RHEL/Arch the options block lives inside named.conf itself.
            # We prepend only if an options block does not already exist in
            # the zone-local file we are about to write; this path writes
            # /etc/named.conf so we handle it monolithically.
            cat > "$_BIND_OPTIONS" <<'NAMED_OPTIONS_RHEL_EOF'
options {
    listen-on port 53 { any; };
    listen-on-v6 { any; };
    directory "/var/named";

    allow-transfer { any; };
    recursion no;
    allow-query { any; };

    dnssec-validation no;
};
NAMED_OPTIONS_RHEL_EOF
            ;;
    esac
    log "02-dns: ${_BIND_OPTIONS} written"
fi

# ---------------------------------------------------------------------------
# 7. Write the zone declaration into named.conf.local
#    (Debian/Ubuntu only; on RHEL the options file IS named.conf, so we
#    append the zone stanza there.)
# ---------------------------------------------------------------------------
log "02-dns: writing zone declaration -> ${_BIND_LOCAL}"
if is_dry_run; then
    log "[DRY-RUN] would write zone lapinlogistics.local to ${_BIND_LOCAL}"
else
    case "${LAPIN_DISTRO_FAMILY:-debian}" in
        debian)
            cat > "$_BIND_LOCAL" <<NAMED_LOCAL_EOF
// Lapin Logistics — local zone declarations
// Authoritative for lapinlogistics.local

zone "lapinlogistics.local" {
    type master;
    file "${_ZONE_FILE}";
    allow-transfer { any; };
};
NAMED_LOCAL_EOF
            ;;
        *)
            # Append zone to the monolithic named.conf (already written above).
            cat >> "$_BIND_OPTIONS" <<NAMED_RHEL_ZONE_EOF

zone "lapinlogistics.local" {
    type master;
    file "${_ZONE_FILE}";
    allow-transfer { any; };
};
NAMED_RHEL_ZONE_EOF
            ;;
    esac
    log "02-dns: zone declaration written"
fi

# ---------------------------------------------------------------------------
# 8. Write the zone file (authoritative; always overwritten)
# ---------------------------------------------------------------------------
log "02-dns: writing zone file -> ${_ZONE_FILE}"
if is_dry_run; then
    log "[DRY-RUN] would write zone file ${_ZONE_FILE} with host IP ${_HOST_IP}"
else
    _ZONE_SERIAL="$(date +%Y%m%d)01"
    cat > "$_ZONE_FILE" <<ZONE_EOF
\$TTL 86400
@   IN  SOA ns1.lapinlogistics.local. admin.lapinlogistics.local. (
        ${_ZONE_SERIAL} ; serial (date-based YYYYMMDDNN, ≤10 digits)
        3600       ; refresh
        1800       ; retry
        604800     ; expire
        86400 )    ; minimum TTL

; Name servers
@       IN  NS  ns1.lapinlogistics.local.

; A records — all point to the host
ns1     IN  A   ${_HOST_IP}
www     IN  A   ${_HOST_IP}
internal IN A   ${_HOST_IP}
warren  IN  A   ${_HOST_IP}
mail    IN  A   ${_HOST_IP}
dev     IN  A   ${_HOST_IP}

; CNAME
ftp     IN  CNAME   www.lapinlogistics.local.
ZONE_EOF
    log "02-dns: zone file written"
fi

# ---------------------------------------------------------------------------
# 9. Enable and start named
#    Note: AppArmor/SELinux are handled centrally by install.sh's handle_lsm.
# ---------------------------------------------------------------------------
log "02-dns: enabling and starting named (bind9)"
ensure_service_enabled named

log "02-dns: DONE — lapinlogistics.local authoritative"
