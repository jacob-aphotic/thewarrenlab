#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/05-web-internal.sh — Lapin Logistics — HTTPS internal vhost
# =============================================================================
# Adds an HTTPS:443 name-based vhost for internal.lapinlogistics.local on top
# of the Apache base that 04-web-carrotmart.sh installed. This module does NOT
# reinstall/clobber Apache or CarrotMart — it drops its OWN conf file and only
# adds the ssl module + `Listen 443` idempotently.
#
# Behaviour:
#   - Self-signed cert+key with subjectAltName=DNS:internal.lapinlogistics.local
#     (and a sensible CN) under /etc/ssl/lapin/.
#   - DocumentRoot /var/www/internal (assets/internal-vhost deployed there),
#     index.php + docs.php served as PHP. .env and docs/ readable by the web
#     user. NO dotfile deny in this docroot.
#   - GENERIC DEFAULT: a visitor hitting :443 (or :80) WITHOUT Host
#     internal.lapinlogistics.local gets a bland Apache-ish page, NOT the
#     internal site. Implemented with two :443 vhosts: a catch-all
#     <VirtualHost _default_:443> listed FIRST (Apache default for unmatched
#     Host headers) serving the bland page, and a name-based
#     <VirtualHost *:443> for internal.lapinlogistics.local listed second.
#     The internal vhost only answers when Host == internal.lapinlogistics.local.
#
# Cross-cutting:
#   - Apache tooling is Debian-centric (a2enmod ssl / a2ensite / ports.conf).
#     On rhel/arch we drop into the conf.d-equivalent and add a `Listen 443`
#     line idempotently; mod_ssl is usually a separate pkg there
#     (mod_ssl / openssl) — we ensure_pkg it best-effort and log.
#   - LSM/firewall handled centrally by install.sh — log note only.
#
# DRY-RUN SAFE: every mutation via run / ensure_* / is_dry_run-gated here-doc.
#               openssl cert generation is is_dry_run-gated (NOT executed in
#               dry-run); regenerated only if missing (idempotent + dry-safe).
# IDEMPOTENT:   vhost confs authoritatively overwritten; asset tree mirrored
#               with cp -aT; cert generated once (kept if present & valid SAN).
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

LAPIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LAPIN_ROOT
LAPIN_ASSETS="${LAPIN_ROOT}/assets"
readonly LAPIN_ASSETS

INTERNAL_DOCROOT="/var/www/internal"
INTERNAL_SERVERNAME="internal.lapinlogistics.local"
SSL_DIR="/etc/ssl/lapin"
SSL_CERT="${SSL_DIR}/internal.crt"
SSL_KEY="${SSL_DIR}/internal.key"
readonly INTERNAL_DOCROOT INTERNAL_SERVERNAME SSL_DIR SSL_CERT SSL_KEY

log "05-web-internal: starting (vhost=${INTERNAL_SERVERNAME}, docroot=${INTERNAL_DOCROOT})"

# ---------------------------------------------------------------------------
# Distro abstraction (mirrors 04's; 04 owns the base Apache install).
# ---------------------------------------------------------------------------
_web_user() {
    case "${LAPIN_DISTRO_FAMILY:-debian}" in
        rhel)  echo "apache" ;;
        arch)  echo "http" ;;
        *)     echo "www-data" ;;
    esac
}
WEB_USER="$(_web_user)"
readonly WEB_USER

_apache_confdir() {
    case "${LAPIN_DISTRO_FAMILY:-debian}" in
        debian|suse)
            if [[ -d /etc/apache2/sites-available ]]; then
                echo "/etc/apache2/sites-available"
            else
                echo "/etc/apache2/conf.d"
            fi ;;
        rhel)  echo "/etc/httpd/conf.d" ;;
        arch)  echo "/etc/httpd/conf/extra" ;;
        *)     echo "/etc/apache2/sites-available" ;;
    esac
}

_apache_enmod() {
    local m="$1"
    if command -v a2enmod >/dev/null 2>&1; then
        run a2enmod "$m"
    else
        log "05-web-internal: a2enmod unavailable (non-Debian); assuming '$m' built-in/LoadModule'd by distro default"
    fi
}

_apache_ensite() {
    local site="$1"
    if command -v a2ensite >/dev/null 2>&1; then
        run a2ensite "$site"
    else
        log "05-web-internal: a2ensite unavailable (non-Debian); conf.d drop-in auto-included, nothing to enable"
    fi
}

# ---------------------------------------------------------------------------
# 1. Packages. 04 owns base apache2+php; here we only ensure mod_ssl exists.
#    On Debian mod_ssl ships with apache2 (a2enmod ssl). On rhel/suse it is a
#    separate pkg (mod_ssl). ensure_pkg apache2 is a no-op if already present
#    and guarantees standalone-debug runs still work.
# ---------------------------------------------------------------------------
log "05-web-internal: ensuring apache2 (no-op if 04 already installed it)"
ensure_pkg apache2 php libapache2-mod-php
case "${LAPIN_DISTRO_FAMILY:-debian}" in
    rhel|suse)
        log "05-web-internal: ensuring mod_ssl (separate package on ${LAPIN_DISTRO_FAMILY})"
        ensure_pkg mod_ssl || warn "05-web-internal: mod_ssl pkg install best-effort; continuing"
        ;;
    *) : ;;  # debian/arch: ssl module ships with apache; a2enmod below
esac

# Enable mod_ssl (Debian a2enmod ssl; elsewhere assumed LoadModule'd).
_apache_enmod ssl

# ---------------------------------------------------------------------------
# 2. Self-signed cert with SAN = DNS:internal.lapinlogistics.local.
#    Idempotent + dry-safe: generated only if missing OR if an existing cert
#    lacks the required SAN (so a stale/wrong cert self-heals on re-run).
#    NEVER executed in dry-run.
# ---------------------------------------------------------------------------
ensure_dir "${SSL_DIR}" 0750 "root:root"

_cert_has_san() {
    [[ -f "$SSL_CERT" ]] || return 1
    openssl x509 -in "$SSL_CERT" -noout -text 2>/dev/null \
        | grep -q "DNS:${INTERNAL_SERVERNAME}"
}

log "05-web-internal: ensuring self-signed cert with SAN DNS:${INTERNAL_SERVERNAME}"
if is_dry_run; then
    log "[DRY-RUN] would generate ${SSL_CERT} / ${SSL_KEY} with subjectAltName=DNS:${INTERNAL_SERVERNAME} (if missing/SAN-stale)"
else
    command -v openssl >/dev/null 2>&1 \
        || die "05-web-internal: openssl not found; run 00-prereqs.sh first"
    if _cert_has_san; then
        log "05-web-internal: existing cert already has the required SAN; keeping it"
    else
        log "05-web-internal: generating fresh self-signed cert"
        run openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "${SSL_KEY}" -out "${SSL_CERT}" -days 3650 \
            -subj "/C=GB/O=Lapin Logistics/OU=IT/CN=${INTERNAL_SERVERNAME}" \
            -addext "subjectAltName=DNS:${INTERNAL_SERVERNAME}"
        run chmod 0640 "${SSL_KEY}"
        run chmod 0644 "${SSL_CERT}"
        run chown root:root "${SSL_KEY}" "${SSL_CERT}"
        log "05-web-internal: cert generated at ${SSL_CERT}"
    fi
fi

# ---------------------------------------------------------------------------
# 3. DocumentRoot — deploy assets/internal-vhost -> /var/www/internal.
#    cp -aT mirrors the tree (index.php, docs.php, docs/, .env) and overwrites
#    on re-run. .env + docs/ must be readable by the web user.
# ---------------------------------------------------------------------------
ensure_dir /var/www              0755 root:root
ensure_dir "${INTERNAL_DOCROOT}" 0755 "root:root"

log "05-web-internal: deploying assets/internal-vhost -> ${INTERNAL_DOCROOT}"
if [[ ! -d "${LAPIN_ASSETS}/internal-vhost" ]]; then
    die "05-web-internal: missing asset tree ${LAPIN_ASSETS}/internal-vhost (bundle deployed correctly?)"
fi
run cp -aT "${LAPIN_ASSETS}/internal-vhost" "${INTERNAL_DOCROOT}"
run chown -R "root:${WEB_USER}" "${INTERNAL_DOCROOT}"
run find "${INTERNAL_DOCROOT}" -type d -exec chmod 0755 {} +
run find "${INTERNAL_DOCROOT}" -type f -exec chmod 0644 {} +
# .env: world-unwritable but web-user readable.
if ! is_dry_run && [[ -f "${INTERNAL_DOCROOT}/.env" ]]; then
    run chmod 0644 "${INTERNAL_DOCROOT}/.env"
    run chown "root:${WEB_USER}" "${INTERNAL_DOCROOT}/.env"
fi

# ---------------------------------------------------------------------------
# 4. Generic default docroot — a bland Apache-ish page for visitors who do
#    NOT send Host internal.lapinlogistics.local. Distinct from the
#    internal site.
# ---------------------------------------------------------------------------
GENERIC_DOCROOT="/var/www/default-generic"
readonly GENERIC_DOCROOT
ensure_dir "${GENERIC_DOCROOT}" 0755 "root:${WEB_USER}"
log "05-web-internal: writing generic default landing page"
if is_dry_run; then
    log "[DRY-RUN] would write ${GENERIC_DOCROOT}/index.html (generic Apache-ish page)"
else
    cat > "${GENERIC_DOCROOT}/index.html" <<'GENERIC_HTML'
<!DOCTYPE html>
<html><head><title>Apache2 Default Page</title>
<style>body{font-family:Arial,sans-serif;margin:40px;color:#333}</style></head>
<body>
<h1>It works!</h1>
<p>This is the default web page for this server.</p>
<p>The web server software is running but no content has been added, yet.</p>
</body></html>
GENERIC_HTML
    chmod 0644 "${GENERIC_DOCROOT}/index.html"
    chown "root:${WEB_USER}" "${GENERIC_DOCROOT}/index.html"
fi

# ---------------------------------------------------------------------------
# 5. `Listen 443` — add idempotently WITHOUT clobbering 04's config.
#    Debian: append to ports.conf only if absent (mod_ssl's own ports.conf
#    snippet already does this when ssl is enabled, so this is belt-and-braces
#    and ensure_line keeps it idempotent). Elsewhere: a tiny own conf file.
# ---------------------------------------------------------------------------
case "${LAPIN_DISTRO_FAMILY:-debian}" in
    debian|suse)
        # Debian/Ubuntu stock ports.conf ALWAYS provides `Listen 443` as a
        # TAB-indented directive inside `<IfModule ssl_module>` (activated by
        # the `a2enmod ssl` above) and `<IfModule mod_gnutls.c>`. A *bare,
        # column-0* `Listen 443` is therefore never stock — it can only be a
        # leftover this installer itself appended on an earlier (buggy) run,
        # and a second active Listen 443 = AH00072 (98) Address already in use
        # -> apache won't start. So REPAIR (idempotent, self-healing,
        # overwrite-not-append spirit): strip any bare `Listen 443` and
        # rely solely on the stock conditional directive. This fixes a host
        # already poisoned by the first failed run, and is a no-op once clean.
        # NOTE: regex is anchored at column 0 with NO leading-whitespace
        # allowance, so it matches ONLY a bare `Listen 443` and never the
        # TAB-indented stock `\tListen 443` inside the <IfModule> blocks
        # (deleting those would remove :443 entirely).
        if [[ -f /etc/apache2/ports.conf ]]; then
            if grep -Eq '^Listen[[:space:]]+443[[:space:]]*$' /etc/apache2/ports.conf; then
                run sed -i -E '/^Listen[[:space:]]+443[[:space:]]*$/d' /etc/apache2/ports.conf
                log "05-web-internal: removed bare 'Listen 443' from ports.conf (stock <IfModule ssl_module> Listen 443 covers :443 once mod_ssl is enabled — prevents AH00072 duplicate-bind)"
            else
                log "05-web-internal: no bare 'Listen 443' in ports.conf — stock <IfModule ssl_module> handles :443 (correct)"
            fi
        fi
        ;;
    *)
        # rhel/arch: our own listen conf so we never edit a shared file.
        _listen_conf="$(_apache_confdir)/lapin-internal-listen.conf"
        if apache_port_listened 443 /etc/apache2/ports.conf "${_listen_conf}"; then
            log "05-web-internal: Apache already listens on :443 — not writing ${_listen_conf}"
        elif is_dry_run; then
            log "[DRY-RUN] would write ${_listen_conf} with 'Listen 443'"
        else
            ensure_dir "$(_apache_confdir)"
            printf 'Listen 443\n' > "${_listen_conf}"
        fi
        unset _listen_conf
        ;;
esac

# ---------------------------------------------------------------------------
# 6. Authoritative vhost conf — OWN file, never clobbers 04's.
#    Order matters: the catch-all default :443 vhost is declared FIRST so it
#    becomes Apache's default for unmatched Host headers; the internal vhost
#    answers only when Host == internal.lapinlogistics.local. We also add a
#    generic :80 default for completeness (04 owns the CarrotMart :80 default
#    via its own conf; this one only fires if 04's site is absent — harmless,
#    name-based, lowest precedence).
#    NO dotfile deny in the internal docroot.
# ---------------------------------------------------------------------------
APACHE_CONFDIR="$(_apache_confdir)"
INTERNAL_VHOST_CONF="${APACHE_CONFDIR}/lapin-internal.conf"
readonly APACHE_CONFDIR INTERNAL_VHOST_CONF

log "05-web-internal: writing authoritative vhost ${INTERNAL_VHOST_CONF}"
if is_dry_run; then
    log "[DRY-RUN] would write ${INTERNAL_VHOST_CONF} (:443 catch-all generic + name-based ${INTERNAL_SERVERNAME})"
else
    ensure_dir "${APACHE_CONFDIR}"
    cat > "${INTERNAL_VHOST_CONF}" <<INTERNAL_VHOST
# ==========================================================================
# ${INTERNAL_VHOST_CONF} — Lapin Logistics — managed by configuration
# DO NOT EDIT MANUALLY — overwritten by configuration management.
#
# Name-based HTTPS vhost for ${INTERNAL_SERVERNAME} + a generic catch-all so
# visitors who don't add the name to /etc/hosts see a bland default page.
# Separate conf file — never clobbers 04-web-carrotmart's vhost.
# ==========================================================================

# ---- :443 generic catch-all (FIRST = Apache default for unmatched Host) ----
<VirtualHost _default_:443>
    ServerName generic.invalid
    DocumentRoot ${GENERIC_DOCROOT}
    SSLEngine on
    SSLCertificateFile ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}
    <Directory ${GENERIC_DOCROOT}>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/generic_ssl_error.log
</VirtualHost>

# ---- :443 internal vhost (answers ONLY for ${INTERNAL_SERVERNAME}) --------
<VirtualHost *:443>
    ServerName ${INTERNAL_SERVERNAME}
    DocumentRoot ${INTERNAL_DOCROOT}
    DirectoryIndex index.php index.html

    SSLEngine on
    SSLCertificateFile ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}

    <Directory ${INTERNAL_DOCROOT}>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "\.php\$">
        SetHandler application/x-httpd-php
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/internal_error.log
    CustomLog \${APACHE_LOG_DIR}/internal_access.log combined
</VirtualHost>

# ---- :80 generic catch-all (lowest precedence; 04 owns the :80 default) ---
# Name-based *:80 with an unresolvable ServerName. Apache picks a _default_:80
# vhost over any *:80 vhost for unmatched requests, so 04's CarrotMart
# <VirtualHost _default_:80> always wins; this vhost only fires if 04's site
# is disabled entirely (belt-and-braces; does NOT override CarrotMart).
<VirtualHost *:80>
    ServerName generic80.invalid
    DocumentRoot ${GENERIC_DOCROOT}
    <Directory ${GENERIC_DOCROOT}>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
INTERNAL_VHOST
    log "05-web-internal: vhost written"
fi

_apache_ensite "lapin-internal"

# ---------------------------------------------------------------------------
# 7. LSM reminder (centralised; do not duplicate).
# ---------------------------------------------------------------------------
log "05-web-internal: NOTE — install.sh's handle_lsm sets AppArmor/SELinux permissive."

# ---------------------------------------------------------------------------
# 8. Reload Apache (picks up ssl module + the new vhost conf).
# ---------------------------------------------------------------------------
log "05-web-internal: enabling and restarting apache"
apache_restart_safe

log "05-web-internal: DONE"
