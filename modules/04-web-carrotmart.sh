#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/04-web-carrotmart.sh — Lapin Logistics — Apache + CarrotMart
# =============================================================================
# OWNS the base Apache install (build order: 04 runs before 05/06, so this
# module installs apache2 + php + libapache2-mod-php and enables PHP). 05 and 06
# add their own vhosts/Listen via *separate* conf files and never clobber this
# module's site.
#
# Deploys the CarrotMart storefront to DocumentRoot EXACTLY /var/www/carrotmart.
# That exact docroot depth is load-bearing: carrot-cms/view.php anchors its
# include() on __DIR__ (= /var/www/carrotmart/carrot-cms). DO NOT change the
# docroot.
#
# Apache requirements honoured here:
#   - executes .php everywhere under the docroot (carrot-cms/, products/, /)
#   - serves robots.txt from the docroot
#   - PHP sessions enabled (admin/ lockout calls session_start) — default in
#     the distro php module; /tmp writable (admin lockout state lives in
#     /tmp/admin_lockout_*) — default on a normal box.
#   - DirectoryIndex includes index.html (warren/index.html) AND index.php
#     (the storefront is index.php)
#   - dotfiles are NOT denied in this docroot. We explicitly do not add an
#     Apache .ht*/dotfile deny for /var/www/carrotmart.
#
# Empty 403 dirs (robots.txt): /old /dev /test /backup /internal are
# created empty and return 403. /admin/ is an app dir (the lockout login)
# and is served normally — NOT 403'd. /warren/ serves its page.
# /carrot-cms/ is served normally. /backups/ holds a password-protected zip.
#
# Cross-cutting notes:
#   - Apache tooling is Debian-centric: a2enmod/a2ensite/a2dissite +
#     sites-available/sites-enabled. On rhel/arch/suse there is no a2* layer;
#     we fall back to dropping a conf into the distro's conf.d/-equivalent and
#     loading mod_php/mod_rewrite explicitly. The Debian path is the tested
#     one. See _apache_paths / a2* shims below.
#   - Firewall + AppArmor/SELinux are handled centrally by install.sh
#     (handle_firewall / handle_lsm set permissive). AppArmor's apache profile
#     can otherwise block PHP include() of /etc/passwd; install.sh's handle_lsm
#     makes it permissive — we only log a reminder, never duplicate that here.
#
# DRY-RUN SAFE: every mutation goes through run / ensure_* / an is_dry_run-
#               gated here-doc. Asset generators (gen-zip.py, gen-git-repo.sh)
#               are NEVER invoked in dry-run and have real-run pre-flight
#               existence/`command -v` checks that die with an actionable msg.
# IDEMPOTENT:   vhost conf + robots are authoritatively overwritten; the asset
#               tree is mirrored with `cp -aT` (overwrite); gen-git-repo.sh
#               itself replaces an existing .git/. Re-runs converge.
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

# Derive the project root + assets path from BASH_SOURCE — never hardcode.
LAPIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LAPIN_ROOT
LAPIN_ASSETS="${LAPIN_ROOT}/assets"
readonly LAPIN_ASSETS

# DocumentRoot is EXACTLY this — the LFI traversal depth depends on it.
CARROT_DOCROOT="/var/www/carrotmart"
readonly CARROT_DOCROOT

log "04-web-carrotmart: starting (docroot=${CARROT_DOCROOT})"

# ---------------------------------------------------------------------------
# Distro abstraction for Apache layout + the web user.
#   _web_user        -> www-data (debian/suse) | apache (rhel) | http (arch)
#   _apache_confdir  -> where this module drops its authoritative vhost conf
#   _apache_a2enmod / _apache_a2ensite — Debian uses a2*; others are shimmed.
# Apache tooling genuinely differs by distro; the Debian path is the tested
# one. Best-effort faithful equivalents for rhel/arch/suse are noted inline.
# ---------------------------------------------------------------------------
_web_user() {
    case "${LAPIN_DISTRO_FAMILY:-debian}" in
        rhel)  echo "apache" ;;
        arch)  echo "http" ;;
        *)     echo "www-data" ;;   # debian, suse, fallback
    esac
}
WEB_USER="$(_web_user)"
readonly WEB_USER

# Apache config directory used for our drop-in vhost/conf files. On Debian we
# use sites-available + a2ensite; elsewhere a conf.d-equivalent that Apache
# Include's by default.
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

# a2enmod shim: Debian has the real tool; elsewhere modules are usually
# statically built or LoadModule'd in the main conf — log + best-effort.
_apache_enmod() {
    local m="$1"
    if command -v a2enmod >/dev/null 2>&1; then
        run a2enmod "$m"
    else
        log "04-web-carrotmart: a2enmod unavailable (non-Debian); assuming '$m' built-in/LoadModule'd by distro default"
    fi
}

# a2ensite shim: Debian symlinks into sites-enabled; elsewhere the conf.d
# drop-in is auto-included so there is nothing to enable.
_apache_ensite() {
    local site="$1"
    if command -v a2ensite >/dev/null 2>&1; then
        run a2ensite "$site"
    else
        log "04-web-carrotmart: a2ensite unavailable (non-Debian); conf.d drop-in is auto-included, nothing to enable"
    fi
}

# Disable Debian's stock default site so our :80 vhost is THE default.
_apache_dissite_default() {
    if command -v a2dissite >/dev/null 2>&1; then
        # 000-default is Debian's shipped default vhost; ignore if absent.
        run a2dissite 000-default || log "04-web-carrotmart: 000-default not enabled (ok)"
    fi
}

# ---------------------------------------------------------------------------
# 1. Packages — this module owns the base Apache + PHP install.
# ---------------------------------------------------------------------------
log "04-web-carrotmart: installing apache2 + php + libapache2-mod-php"
ensure_pkg apache2 php libapache2-mod-php

# Enable the modules we rely on (PHP + rewrite for tidy 403 handling).
# Debian's libapache2-mod-php auto-enables phpN; the a2enmod is belt-and-braces
# and a no-op if already enabled.
_apache_enmod rewrite
if command -v a2enmod >/dev/null 2>&1; then
    # Enable whatever php* module exists (php8.x / php7.x — name varies).
    _php_mod="$(find /etc/apache2/mods-available -maxdepth 1 -name 'php*.load' \
                  -printf '%f\n' 2>/dev/null | sed 's/\.load$//' | sort | tail -n1)"
    if [[ -n "${_php_mod:-}" ]]; then
        run a2enmod "${_php_mod}"
    else
        log "04-web-carrotmart: no php*.load module found yet (mod-php may be statically linked)"
    fi
    unset _php_mod
fi

# ---------------------------------------------------------------------------
# 2. DocumentRoot — create + deploy the asset tree.
#    cp -aT mirrors assets/carrotmart/ -> /var/www/carrotmart (preserves the
#    inc/, assets/, carrot-cms/, products/ subtrees incl. dot-less dirs) and is
#    re-run safe (overwrites). Authoritative: the deployed site always matches
#    the asset bundle.
# ---------------------------------------------------------------------------
ensure_dir /var/www              0755 root:root
ensure_dir "${CARROT_DOCROOT}"   0755 "root:root"

log "04-web-carrotmart: deploying asset tree assets/carrotmart -> ${CARROT_DOCROOT}"
if [[ ! -d "${LAPIN_ASSETS}/carrotmart" ]]; then
    die "04-web-carrotmart: missing asset tree ${LAPIN_ASSETS}/carrotmart (was the bundle deployed correctly?)"
fi
# cp -aT: copy CONTENTS of src into dest (no nested carrotmart/carrotmart),
# preserving perms/symlinks; overwrites existing files for idempotency.
run cp -aT "${LAPIN_ASSETS}/carrotmart" "${CARROT_DOCROOT}"

# Ownership: readable/served by the web user. Files stay non-writable by the
# web user (the admin lockout writes to /tmp, not the docroot).
run chown -R "root:${WEB_USER}" "${CARROT_DOCROOT}"
run find "${CARROT_DOCROOT}" -type d -exec chmod 0755 {} +
run find "${CARROT_DOCROOT}" -type f -exec chmod 0644 {} +

# ---------------------------------------------------------------------------
# 3. robots.txt (8 entries incl. /carrot-cms/) — authoritative.
#    The asset bundle ships one; we OVERWRITE with the canonical content
#    so this module is the single authoritative owner regardless of asset
#    drift (8 entries, must include /carrot-cms/).
# ---------------------------------------------------------------------------
log "04-web-carrotmart: writing authoritative ${CARROT_DOCROOT}/robots.txt"
if is_dry_run; then
    log "[DRY-RUN] would write ${CARROT_DOCROOT}/robots.txt (8 entries incl /carrot-cms/)"
else
    cat > "${CARROT_DOCROOT}/robots.txt" <<'ROBOTS_TXT'
User-agent: *
Disallow: /admin/
Disallow: /backup/
Disallow: /old/
Disallow: /dev/
Disallow: /test/
Disallow: /warren/
Disallow: /internal/
Disallow: /carrot-cms/
ROBOTS_TXT
    chmod 0644 "${CARROT_DOCROOT}/robots.txt"
    chown "root:${WEB_USER}" "${CARROT_DOCROOT}/robots.txt"
    log "04-web-carrotmart: robots.txt written"
fi

# ---------------------------------------------------------------------------
# 4. Empty directories.
#    /old /dev /test /backup /internal -> empty, return 403.
#    /admin/ /carrot-cms/ /warren/ are app dirs (came from the asset
#    tree) — they are NOT 403'd.
#    These five dirs created empty; the vhost <Directory> blocks below
#    return 403 for them. /backups/ (holds the zip) is created here too.
# ---------------------------------------------------------------------------
log "04-web-carrotmart: creating empty 403 dirs (old dev test backup internal) + /backups"
for _d in old dev test backup internal backups; do
    ensure_dir "${CARROT_DOCROOT}/${_d}" 0755 "root:${WEB_USER}"
done
unset _d

# ---------------------------------------------------------------------------
# 5. Authoritative :80 vhost (the default site -> CarrotMart).
#    Uses <VirtualHost _default_:80> — Apache's explicit catch-all for :80.
#    In Apache 2.x, _default_:80 has higher catch-all priority than any *:80
#    name-based vhost, making CarrotMart the :80 default by construction (not
#    just by alphabetical conf-load order). 05's generic *:80 safety-net only
#    fires if this _default_:80 vhost is absent.
#    - DirectoryIndex index.php index.html (storefront + the warren page)
#    - .php executed everywhere under the docroot
#    - AllowOverride/Require all granted for the docroot
#    - NO dotfile deny here; we do NOT emit a <FilesMatch "^\."> deny for
#      this docroot.
#    - <Directory> Require all denied for the 5 empty dirs -> 403
#    - /admin /carrot-cms /warren explicitly NOT denied (served normally)
# ---------------------------------------------------------------------------
APACHE_CONFDIR="$(_apache_confdir)"
CARROT_VHOST_CONF="${APACHE_CONFDIR}/lapin-carrotmart.conf"
readonly APACHE_CONFDIR CARROT_VHOST_CONF

log "04-web-carrotmart: writing authoritative vhost ${CARROT_VHOST_CONF}"
if is_dry_run; then
    log "[DRY-RUN] would write ${CARROT_VHOST_CONF} (:80 default vhost -> ${CARROT_DOCROOT})"
    log "[DRY-RUN] would write 403 <Directory> blocks for old/dev/test/backup/internal"
else
    ensure_dir "${APACHE_CONFDIR}"
    cat > "${CARROT_VHOST_CONF}" <<CARROT_VHOST
# ==========================================================================
# ${CARROT_VHOST_CONF} — Lapin Logistics — managed by configuration
# DO NOT EDIT MANUALLY — this file is overwritten by configuration management.
#
# CarrotMart storefront — explicit _default_:80 catch-all vhost.
# _default_:80 takes priority over any *:80 name-based vhost regardless of
# conf load order, so CarrotMart is the :80 default by construction.
# ==========================================================================
<VirtualHost _default_:80>
    ServerName carrotmart.local
    DocumentRoot ${CARROT_DOCROOT}

    DirectoryIndex index.php index.html

    <Directory ${CARROT_DOCROOT}>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Ensure .php is executed (handler name varies by php module version;
    # SetHandler application/x-httpd-php is the version-agnostic form and is a
    # no-op harmless duplicate if mod_php already maps it).
    <FilesMatch "\.php\$">
        SetHandler application/x-httpd-php
    </FilesMatch>

    <Directory ${CARROT_DOCROOT}/old>
        Require all denied
    </Directory>
    <Directory ${CARROT_DOCROOT}/dev>
        Require all denied
    </Directory>
    <Directory ${CARROT_DOCROOT}/test>
        Require all denied
    </Directory>
    <Directory ${CARROT_DOCROOT}/backup>
        Require all denied
    </Directory>
    <Directory ${CARROT_DOCROOT}/internal>
        Require all denied
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/carrotmart_error.log
    CustomLog \${APACHE_LOG_DIR}/carrotmart_access.log combined
</VirtualHost>
CARROT_VHOST
    log "04-web-carrotmart: vhost written"
fi

# Enable our site, disable Debian's stock default so ours is THE :80 default.
_apache_dissite_default
_apache_ensite "lapin-carrotmart"

# ---------------------------------------------------------------------------
# 6. /backups/lapin_backup_2024.zip — gen-zip into a staging dir, copy ONLY
#    that one zip into the docroot (archived_emails.zip is FTP's, not
#    here). Generator NEVER runs in dry-run; real-run pre-flight checks.
# ---------------------------------------------------------------------------
log "04-web-carrotmart: deploying /backups/lapin_backup_2024.zip"
if is_dry_run; then
    log "[DRY-RUN] would run: python3 ${LAPIN_ASSETS}/gen-zip.py --outdir <staging>"
    log "[DRY-RUN] would cp staging/lapin_backup_2024.zip ${CARROT_DOCROOT}/backups/"
else
    command -v python3 >/dev/null 2>&1 \
        || die "04-web-carrotmart: python3 not found; run 00-prereqs.sh first"
    [[ -f "${LAPIN_ASSETS}/gen-zip.py" ]] \
        || die "04-web-carrotmart: missing asset generator ${LAPIN_ASSETS}/gen-zip.py (bundle deployed correctly?)"

    _staging="$(mktemp -d)"
    trap 'rm -rf -- "${_staging:-}"' EXIT
    log "04-web-carrotmart: staging dir ${_staging}"

    python3 "${LAPIN_ASSETS}/gen-zip.py" --outdir "${_staging}"

    if [[ ! -f "${_staging}/lapin_backup_2024.zip" ]]; then
        die "04-web-carrotmart: gen-zip.py did not produce lapin_backup_2024.zip"
    fi
    # Copy ONLY lapin_backup_2024.zip (archived_emails.zip belongs to FTP).
    run cp "${_staging}/lapin_backup_2024.zip" "${CARROT_DOCROOT}/backups/"
    run chmod 0644 "${CARROT_DOCROOT}/backups/lapin_backup_2024.zip"
    run chown "root:${WEB_USER}" "${CARROT_DOCROOT}/backups/lapin_backup_2024.zip"
    log "04-web-carrotmart: installed ${CARROT_DOCROOT}/backups/lapin_backup_2024.zip"

    rm -rf -- "${_staging}"
    trap - EXIT
    unset _staging
fi

# ---------------------------------------------------------------------------
# 7. /.git/ working tree. gen-git-repo.sh creates /var/www/carrotmart/.git/
#    with a short commit history and replaces any existing .git/ at that path
#    (idempotent). Real-run only; pre-flight checks.
# ---------------------------------------------------------------------------
log "04-web-carrotmart: deploying .git/ via gen-git-repo.sh"
if is_dry_run; then
    log "[DRY-RUN] would run: bash ${LAPIN_ASSETS}/gen-git-repo.sh ${CARROT_DOCROOT}"
else
    command -v git >/dev/null 2>&1 \
        || die "04-web-carrotmart: git not found; run 00-prereqs.sh first"
    [[ -f "${LAPIN_ASSETS}/gen-git-repo.sh" ]] \
        || die "04-web-carrotmart: missing asset generator ${LAPIN_ASSETS}/gen-git-repo.sh (bundle deployed correctly?)"

    run bash "${LAPIN_ASSETS}/gen-git-repo.sh" "${CARROT_DOCROOT}"
    # The .git/ must be readable by the web user (no dotfile deny in this
    # docroot, see vhost above).
    run chown -R "root:${WEB_USER}" "${CARROT_DOCROOT}/.git"
    run find "${CARROT_DOCROOT}/.git" -type d -exec chmod 0755 {} +
    run find "${CARROT_DOCROOT}/.git" -type f -exec chmod 0644 {} +
    log "04-web-carrotmart: .git/ deployed at ${CARROT_DOCROOT}/.git"
fi

# ---------------------------------------------------------------------------
# 8. AppArmor/SELinux reminder (handled centrally — do NOT duplicate).
# ---------------------------------------------------------------------------
log "04-web-carrotmart: NOTE — AppArmor/SELinux can block Apache PHP include();"
log "04-web-carrotmart:        install.sh's handle_lsm sets LSM permissive."

# ---------------------------------------------------------------------------
# 9. Enable + (re)start Apache.
# ---------------------------------------------------------------------------
log "04-web-carrotmart: enabling and starting apache"
apache_restart_safe

log "04-web-carrotmart: DONE"
