#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/06-web-wordpress.sh — Lapin Logistics — WordPress on :8080
# =============================================================================
# Deploys WordPress 5.7.x on port 8080, on top of the Apache base that
# 04-web-carrotmart.sh installed. Drops its OWN vhost conf and adds
# `Listen 8080` idempotently — never clobbers 04/05's config.
#
# Real-install path (network required):
#   - MariaDB: DB `wordpress` + a generated DB user/password (written ONLY to
#     wp-config.php where WP needs it).
#   - Download WordPress 5.7.2 (PINNED) -> /var/www/wordpress.
#   - Scripted install via wp-cli (downloaded phar) if obtainable, else direct
#     SQL. WP users: peter (administrator), velveteen (subscriber). One post
#     "Reminder: rotate the SNMP community string before Q4 audit" dated ~3y
#     before the build. One approved comment from "roger" about
#     /opt/lapin-tools. One older plugin: wp-statistics 12.6.2, placed
#     inactive.
#
# FALLBACK: if MariaDB / wp-cli / the WP download fails, the module DETECTS
#   the failure and DEGRADES to a STATIC landing page instead of dying — a
#   minimal docroot that still fingerprints as WordPress 5.7.x (generator
#   meta tag + readme.html "Version 5.7.2" + /wp-login.php stub) with users
#   peter & velveteen enumerable (?author=1 / ?author=2 author pages + an
#   authors index). A clear WARN is logged.
#
# DRY-RUN SAFE: every mutation via run / ensure_* / is_dry_run-gated here-doc.
#               The WP/wp-cli downloads, mysql, and php WP-install endpoint are
#               NEVER invoked in dry-run; real-run pre-flight checks die with
#               actionable messages where a hard dep (php) is missing.
# IDEMPOTENT:   vhost authoritatively overwritten; DB/users/post/comment all
#               guarded with existence checks (no duplicates on re-run); the
#               WP tree is only re-downloaded if absent.
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

# 06 has no asset-tree deploy (WordPress is downloaded, not bundled) so it
# needs no LAPIN_ASSETS/LAPIN_ROOT — not derived here.

WP_DOCROOT="/var/www/wordpress"
WP_VERSION="5.7.2"                 # PINNED WordPress version (5.7.x)
WP_TARBALL_URL="https://wordpress.org/wordpress-${WP_VERSION}.tar.gz"
WP_DB_NAME="wordpress"
WP_DB_USER="wp_lapin"
WP_PORT="8080"
WP_URL="http://127.0.0.1:${WP_PORT}"
# Plugin pinned to an older release
WP_PLUGIN_SLUG="wp-statistics"
WP_PLUGIN_VERSION="12.6.2"
WP_PLUGIN_URL="https://downloads.wordpress.org/plugin/${WP_PLUGIN_SLUG}.${WP_PLUGIN_VERSION}.zip"
# ~3 years before today's build date.
WP_POST_DATE="$(date -d '3 years ago' '+%Y-%m-%d 09:14:00' 2>/dev/null || echo '2022-05-15 09:14:00')"
readonly WP_DOCROOT WP_VERSION WP_TARBALL_URL WP_DB_NAME WP_DB_USER WP_PORT WP_URL
readonly WP_PLUGIN_SLUG WP_PLUGIN_VERSION WP_PLUGIN_URL WP_POST_DATE

log "06-web-wordpress: starting (WordPress ${WP_VERSION} on :${WP_PORT}, docroot=${WP_DOCROOT})"

# ---------------------------------------------------------------------------
# Distro abstraction (mirrors 04/05; 04 owns the base apache install).
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

_apache_ensite() {
    local site="$1"
    if command -v a2ensite >/dev/null 2>&1; then
        run a2ensite "$site"
    else
        log "06-web-wordpress: a2ensite unavailable (non-Debian); conf.d drop-in auto-included, nothing to enable"
    fi
}

# ---------------------------------------------------------------------------
# 1. Packages. 04 owns base apache2+php; we add MariaDB + php-mysql here.
# ---------------------------------------------------------------------------
log "06-web-wordpress: ensuring apache2/php (no-op if 04 did it) + mariadb-server + php-mysql"
ensure_pkg apache2 php libapache2-mod-php mariadb-server
# php-mysql/php-mysqli name varies; ensure_pkg passes generic, pkg.sh maps.
ensure_pkg php-mysql || warn "06-web-wordpress: php-mysql pkg best-effort (may be bundled in php)"

# ---------------------------------------------------------------------------
# 2. `Listen 8080` — idempotent, never clobbers 04/05's config.
# ---------------------------------------------------------------------------
case "${LAPIN_DISTRO_FAMILY:-debian}" in
    debian|suse)
        # `Listen 8080` is not in stock ports.conf, but use the same
        # port-aware guard as 05 so a re-run (or any other module) never
        # produces a duplicate Listen -> AH00072.
        if [[ -f /etc/apache2/ports.conf ]]; then
            if apache_port_listened 8080 /etc/apache2/ports.conf; then
                log "06-web-wordpress: Apache already listens on :8080 — not adding a duplicate Listen"
            else
                ensure_line /etc/apache2/ports.conf "Listen 8080"
            fi
        fi
        ;;
    *)
        _listen_conf="$(_apache_confdir)/lapin-wordpress-listen.conf"
        if apache_port_listened 8080 /etc/apache2/ports.conf "${_listen_conf}"; then
            log "06-web-wordpress: Apache already listens on :8080 — not writing ${_listen_conf}"
        elif is_dry_run; then
            log "[DRY-RUN] would write ${_listen_conf} with 'Listen 8080'"
        else
            ensure_dir "$(_apache_confdir)"
            printf 'Listen 8080\n' > "${_listen_conf}"
        fi
        unset _listen_conf
        ;;
esac

# ---------------------------------------------------------------------------
# 3. Authoritative :8080 vhost — OWN conf file, never clobbers 04/05.
# ---------------------------------------------------------------------------
APACHE_CONFDIR="$(_apache_confdir)"
WP_VHOST_CONF="${APACHE_CONFDIR}/lapin-wordpress.conf"
readonly APACHE_CONFDIR WP_VHOST_CONF

ensure_dir /var/www       0755 root:root
ensure_dir "${WP_DOCROOT}" 0755 "root:${WEB_USER}"

log "06-web-wordpress: writing authoritative vhost ${WP_VHOST_CONF}"
if is_dry_run; then
    log "[DRY-RUN] would write ${WP_VHOST_CONF} (:${WP_PORT} -> ${WP_DOCROOT})"
else
    ensure_dir "${APACHE_CONFDIR}"
    cat > "${WP_VHOST_CONF}" <<WP_VHOST
# ==========================================================================
# ${WP_VHOST_CONF} — Lapin Logistics — managed by configuration
# DO NOT EDIT MANUALLY — overwritten by configuration management.
# WordPress ${WP_VERSION} on :${WP_PORT}. Separate conf — never clobbers 04/05.
# ==========================================================================
<VirtualHost *:${WP_PORT}>
    ServerName wordpress.lapinlogistics.local
    DocumentRoot ${WP_DOCROOT}
    DirectoryIndex index.php index.html

    <Directory ${WP_DOCROOT}>
        Options +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch "\.php\$">
        SetHandler application/x-httpd-php
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
WP_VHOST
    log "06-web-wordpress: vhost written"
fi
_apache_ensite "lapin-wordpress"

# ---------------------------------------------------------------------------
# 4. LSM reminder (centralised; do not duplicate).
# ---------------------------------------------------------------------------
log "06-web-wordpress: NOTE — install.sh's handle_lsm sets AppArmor/SELinux permissive"
log "06-web-wordpress:        (AppArmor can otherwise block mysqld / Apache↔DB)."

# In dry-run we stop here: the real install (DB, downloads, scripted WP
# install, or the fallback) mutates the system / hits the network and
# must do NOTHING in a dry run.
if is_dry_run; then
    log "[DRY-RUN] would: start MariaDB; create DB '${WP_DB_NAME}' + user '${WP_DB_USER}'"
    log "[DRY-RUN] would: download ${WP_TARBALL_URL} -> ${WP_DOCROOT}"
    log "[DRY-RUN] would: scripted WP install (wp-cli phar if obtainable, else direct SQL)"
    log "[DRY-RUN] would: create WP users peter (admin) + velveteen (subscriber)"
    log "[DRY-RUN] would: seed post 'Reminder: rotate the SNMP community string before Q4 audit' dated ${WP_POST_DATE}"
    log "[DRY-RUN] would: seed approved comment from 'roger' re /opt/lapin-tools"
    log "[DRY-RUN] would: install plugin ${WP_PLUGIN_SLUG} ${WP_PLUGIN_VERSION}"
    log "[DRY-RUN] fallback path: on any failure above, deploy static landing page ${WP_VERSION} (peter/velveteen enumerable)"
    log "06-web-wordpress: DONE (dry-run)"
    return 0 2>/dev/null || exit 0
fi

# ===========================================================================
# REAL RUN from here. Hard dependency: php (Apache module). MariaDB / network
# are SOFT — their failure triggers the static fallback, not a die.
# ===========================================================================
command -v php >/dev/null 2>&1 \
    || die "06-web-wordpress: php not found; run 04-web-carrotmart.sh / 00-prereqs.sh first"

# DB credential — generated; written ONLY into wp-config.php.
WP_DB_PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32 || echo 'Lapin_Wp_Db_FallbackPw_2026')"

# ---------------------------------------------------------------------------
# Fallback — static docroot that still fingerprints as 5.7.x with
# peter/velveteen enumerable. Called on ANY soft failure below.
# ---------------------------------------------------------------------------
deploy_static_wp() {
    warn "06-web-wordpress: FALLBACK ENGAGED — deploying static landing page ${WP_VERSION} (real install unavailable)"
    # Clean any partial real install so the fingerprint is consistent.
    rm -rf -- "${WP_DOCROOT:?}/"* 2>/dev/null || true
    mkdir -p "${WP_DOCROOT}/wp-content/themes/lapin" \
             "${WP_DOCROOT}/wp-includes" "${WP_DOCROOT}/wp-admin"

    # index.html — generator meta tag wpscan keys on.
    cat > "${WP_DOCROOT}/index.html" <<STATICWP_INDEX
<!DOCTYPE html><html lang="en-US"><head>
<meta charset="UTF-8">
<meta name="generator" content="WordPress ${WP_VERSION}">
<title>Lapin Logistics &#8212; Marketing</title>
<link rel="https://api.w.org/" href="/wp-json/">
<link rel='stylesheet' href='/wp-content/themes/lapin/style.css?ver=${WP_VERSION}'>
</head><body>
<h1>Lapin Logistics Marketing</h1>
<article id="post-1">
<h2>Reminder: rotate the SNMP community string before Q4 audit</h2>
<p class="post-date">Posted ${WP_POST_DATE} by <a href="/?author=1">peter</a></p>
<p>IT keeps flagging this in the quarterly review and it never gets done.
The SNMP community string is still the default and the Q4 audit is coming.
Someone needs to own this before the auditors do.</p>
<div class="comments">
  <p class="comment"><strong>roger</strong>: and while we're at it, the junk
  in <code>/opt/lapin-tools</code> needs cleaning up — half of it is
  world-writable scratch scripts from the migration. Not my circus until
  someone gives me the box.</p>
</div>
</article>
<p>Authors: <a href="/?author=1">peter</a>, <a href="/?author=2">velveteen</a></p>
</body></html>
STATICWP_INDEX

    # readme.html — wpscan parses the version from here too.
    cat > "${WP_DOCROOT}/readme.html" <<STATICWP_README
<!DOCTYPE html><html><head><title>WordPress &#8250; ReadMe</title></head>
<body><h1>WordPress</h1><p>Version ${WP_VERSION}</p>
<p>Semantic Personal Publishing Platform</p></body></html>
STATICWP_README

    # wp-login.php stub — endpoint wpscan probes; also leaks the two usernames
    # on invalid login the way a real WP does ("Unknown username" vs valid).
    cat > "${WP_DOCROOT}/wp-login.php" <<'STATICWP_LOGIN'
<?php
header('Content-Type: text/html; charset=UTF-8');
$u = isset($_POST['log']) ? (string)$_POST['log'] : '';
$known = array('peter', 'velveteen');
echo "<!DOCTYPE html><html><head><title>Log In &lsaquo; Lapin Logistics &#8212; WordPress</title></head><body>";
echo '<form name="loginform" id="loginform" action="/wp-login.php" method="post">';
echo '<input type="text" name="log"><input type="password" name="pwd">';
echo '<input type="submit" value="Log In"></form>';
if ($u !== '') {
    if (in_array(strtolower($u), $known, true)) {
        echo '<div id="login_error">The password you entered for the username <strong>'
             . htmlspecialchars($u) . '</strong> is incorrect.</div>';
    } else {
        echo '<div id="login_error">Unknown username. Check again or try your email address.</div>';
    }
}
echo "</body></html>";
STATICWP_LOGIN

    # Author enumeration stub: /?author=N -> a page naming the user, the way
    # wpscan's author enumeration expects (also an explicit authors index).
    cat > "${WP_DOCROOT}/index.php" <<'STATICWP_PHP'
<?php
header('Content-Type: text/html; charset=UTF-8');
$authors = array(1 => 'peter', 2 => 'velveteen');
$a = isset($_GET['author']) ? (int)$_GET['author'] : 0;
echo '<!DOCTYPE html><html lang="en-US"><head><meta charset="UTF-8">';
echo '<meta name="generator" content="WordPress 5.7.2">';
echo '<title>Lapin Logistics &#8212; Marketing</title></head><body>';
if ($a && isset($authors[$a])) {
    $n = $authors[$a];
    echo '<body class="archive author author-' . $n . ' author-' . $a . '">';
    echo '<h1 class="page-title">Author: <span class="vcard">' . $n . '</span></h1>';
} else {
    echo '<h1>Lapin Logistics Marketing</h1>';
    echo '<ul><li><a href="/?author=1" title="peter">peter</a></li>';
    echo '<li><a href="/?author=2" title="velveteen">velveteen</a></li></ul>';
    echo '<p>See <a href="/index.html">the latest post</a>.</p>';
}
echo '</body></html>';
STATICWP_PHP

    cat > "${WP_DOCROOT}/wp-content/themes/lapin/style.css" <<'STATICWP_CSS'
/* Theme Name: Lapin Marketing */
body{font-family:Arial,sans-serif;margin:40px;color:#1f2a14}
STATICWP_CSS

    chown -R "root:${WEB_USER}" "${WP_DOCROOT}"
    find "${WP_DOCROOT}" -type d -exec chmod 0755 {} +
    find "${WP_DOCROOT}" -type f -exec chmod 0644 {} +
    warn "06-web-wordpress: static fallback deployed — wpscan will still fingerprint WordPress ${WP_VERSION} with users peter/velveteen."
}

# ---------------------------------------------------------------------------
# 5. Try the real install. Any soft failure -> deploy_static_wp + early return.
# ---------------------------------------------------------------------------
_real_wp_ok=1

# 5a. MariaDB up + DB/user. -------------------------------------------------
log "06-web-wordpress: starting MariaDB"
if ! ensure_service_enabled mariadb; then
    warn "06-web-wordpress: MariaDB failed to start"
    _real_wp_ok=0
fi

if [[ "$_real_wp_ok" == "1" ]]; then
    log "06-web-wordpress: creating DB '${WP_DB_NAME}' + user '${WP_DB_USER}' (idempotent)"
    # All guards are IF NOT EXISTS / CREATE-or-update — safe to re-run.
    if ! mysql --protocol=socket -u root <<SQL 2>>"${LAPIN_LOG_FILE:-/dev/null}"
CREATE DATABASE IF NOT EXISTS \`${WP_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASS}';
ALTER USER '${WP_DB_USER}'@'localhost' IDENTIFIED BY '${WP_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${WP_DB_NAME}\`.* TO '${WP_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    then
        warn "06-web-wordpress: MariaDB DB/user provisioning failed"
        _real_wp_ok=0
    fi
fi

# 5b. Download + extract WordPress (only if not already present). -----------
if [[ "$_real_wp_ok" == "1" ]]; then
    if [[ -f "${WP_DOCROOT}/wp-includes/version.php" ]]; then
        log "06-web-wordpress: WordPress core already present at ${WP_DOCROOT}; skipping download"
    else
        log "06-web-wordpress: downloading WordPress ${WP_VERSION}"
        _wpstage="$(mktemp -d)"
        trap 'rm -rf -- "${_wpstage:-}"' EXIT
        _dl_ok=1
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --max-time 120 -o "${_wpstage}/wp.tar.gz" "${WP_TARBALL_URL}" || _dl_ok=0
        elif command -v wget >/dev/null 2>&1; then
            wget -q -T 120 -O "${_wpstage}/wp.tar.gz" "${WP_TARBALL_URL}" || _dl_ok=0
        else
            warn "06-web-wordpress: neither curl nor wget available for download"
            _dl_ok=0
        fi
        if [[ "$_dl_ok" == "1" ]] && tar -xzf "${_wpstage}/wp.tar.gz" -C "${_wpstage}" 2>/dev/null \
           && [[ -d "${_wpstage}/wordpress" ]]; then
            # Mirror the extracted tree into the docroot (overwrite-safe).
            cp -aT "${_wpstage}/wordpress" "${WP_DOCROOT}"
        else
            warn "06-web-wordpress: WordPress download/extract failed (${WP_TARBALL_URL})"
            _real_wp_ok=0
        fi
        rm -rf -- "${_wpstage}"
        trap - EXIT
        unset _wpstage _dl_ok
    fi
fi

# 5c. wp-config.php (authoritative; the only place the DB cred is written). --
if [[ "$_real_wp_ok" == "1" ]]; then
    log "06-web-wordpress: writing wp-config.php"
    _salts="$(curl -fsSL --max-time 20 https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null || true)"
    if [[ -z "${_salts}" ]]; then
        # Offline-safe locally-generated salts.
        _salts=$(for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY \
                          AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
            printf "define('%s', '%s');\n" "$k" \
              "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48)"
        done)
    fi
    cat > "${WP_DOCROOT}/wp-config.php" <<WPCONF
<?php
/* Lapin Logistics — managed by configuration. DO NOT EDIT. */
define( 'DB_NAME', '${WP_DB_NAME}' );
define( 'DB_USER', '${WP_DB_USER}' );
define( 'DB_PASSWORD', '${WP_DB_PASS}' );
define( 'DB_HOST', '127.0.0.1' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );
${_salts}
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
define( 'WP_HOME', '${WP_URL}' );
define( 'WP_SITEURL', '${WP_URL}' );
define( 'FS_METHOD', 'direct' );
if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }
require_once ABSPATH . 'wp-settings.php';
WPCONF
    chown "root:${WEB_USER}" "${WP_DOCROOT}/wp-config.php"
    chmod 0640 "${WP_DOCROOT}/wp-config.php"
    unset _salts
fi

# 5d. Obtain wp-cli (preferred scripted-install path). ----------------------
WP_CLI=""
if [[ "$_real_wp_ok" == "1" ]]; then
    if command -v wp >/dev/null 2>&1; then
        WP_CLI="wp"
    else
        log "06-web-wordpress: fetching wp-cli phar"
        _wpcli_path="/usr/local/bin/wp-lapin"
        if command -v curl >/dev/null 2>&1 \
           && curl -fsSL --max-time 60 -o "${_wpcli_path}" \
                https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar 2>/dev/null \
           && [[ -s "${_wpcli_path}" ]]; then
            chmod 0755 "${_wpcli_path}"
            WP_CLI="${_wpcli_path}"
        else
            warn "06-web-wordpress: wp-cli download failed; will try direct SQL install"
            WP_CLI=""
        fi
        unset _wpcli_path
    fi
fi

# wp-cli wrapper: always run as the web user against the docroot.
_wp() { run sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" "$@"; }

# 5e. Scripted core install + content via wp-cli. ---------------------------
if [[ "$_real_wp_ok" == "1" && -n "${WP_CLI}" ]]; then
    log "06-web-wordpress: scripted install via wp-cli"
    chown -R "${WEB_USER}:${WEB_USER}" "${WP_DOCROOT}"
    # CRITICAL bash gotcha (same trap solved in install.sh's module runner,
    # ~L183-205): errexit is SUPPRESSED for a subshell used as the LHS of
    # `||`/`&&` or as an `if`/`while` condition. So `( set -e; ... ) || flag=0`
    # does NOT abort the subshell on the first inner failure — it runs to the
    # end and exits with its LAST command's status (here the trailing
    # `... || warn` → 0), leaving flag=1 and the broken-WP fallback unreached.
    # The only correct capture is to run the subshell as a PLAIN statement (no
    # test context), drop the caller's errexit around just that statement so a
    # failing wp-cli step doesn't abort the whole module, read $? on the next
    # line, then restore errexit — mirroring install.sh's module runner.
    _wpcli_ok=1
    set +e
    (
        set -euo pipefail
        # Idempotent: is-installed short-circuits a re-run.
        if ! sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" core is-installed 2>/dev/null; then
            _wp core install \
                --url="${WP_URL}" \
                --title="Lapin Logistics — Marketing" \
                --admin_user="peter" \
                --admin_password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)" \
                --admin_email="peter.cottontail@lapinlogistics.com" \
                --skip-email
        fi
        # velveteen — WP subscriber account. Guard: user-exists.
        if ! sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" user get velveteen >/dev/null 2>&1; then
            _wp user create velveteen velveteen@lapinlogistics.com \
                --role=subscriber \
                --user_pass="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"
        fi
        # The SNMP-rotate post, dated ~3y ago. Guard: only if not present.
        if ! sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" \
                post list --post_type=post --field=post_title 2>/dev/null \
                | grep -qF 'rotate the SNMP community string'; then
            _post_id="$(sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" \
                post create --post_type=post --post_status=publish \
                --post_author=1 --post_date="${WP_POST_DATE}" \
                --post_title='Reminder: rotate the SNMP community string before Q4 audit' \
                --post_content='IT keeps flagging this every quarter and it never gets done. The SNMP community string is still the shipped default and the Q4 audit is coming. Someone needs to own this before the auditors do.' \
                --porcelain 2>/dev/null || echo '')"
            # roger's approved comment re /opt/lapin-tools.
            if [[ -n "${_post_id}" ]]; then
                _wp comment create --comment_post_ID="${_post_id}" \
                    --comment_author="roger" \
                    --comment_author_email="roger.rabbit@lapinlogistics.com" \
                    --comment_content="And while we are at it, the junk in /opt/lapin-tools needs cleaning up — half of it is world-writable scratch scripts left over from the migration. Not my problem until someone gives me access to that box though." \
                    --comment_approved=1
            fi
            unset _post_id
        fi
        # Plugin pinned to an older release — installed INACTIVE. wpscan
        # enumerates it from wp-content/plugins/<slug>/readme.txt Stable tag.
        if ! sudo -u "${WEB_USER}" -- "${WP_CLI}" --path="${WP_DOCROOT}" \
                plugin is-installed "${WP_PLUGIN_SLUG}" 2>/dev/null; then
            _wp plugin install "${WP_PLUGIN_URL}" || \
                warn "06-web-wordpress: plugin install via wp-cli failed (non-fatal; core install still valid)"
        fi
    )
    _wpcli_rc=$?
    set -e
    if [[ "$_wpcli_rc" -ne 0 ]]; then
        warn "06-web-wordpress: wp-cli scripted install hit an error — engaging fallback"
        _real_wp_ok=0
    fi
    unset _wpcli_ok _wpcli_rc
fi

# 5f. No wp-cli but core present -> direct-SQL minimal install. --------------
# A faithful minimal scripted install: WP's own installer endpoint, driven
# non-interactively, then username/post/comment normalised via SQL. This is
# the documented fallback ("otherwise direct DB inserts via SQL").
if [[ "$_real_wp_ok" == "1" && -z "${WP_CLI}" ]]; then
    log "06-web-wordpress: no wp-cli — scripted install via WP install endpoint + SQL"
    chown -R "${WEB_USER}:${WEB_USER}" "${WP_DOCROOT}"
    _admin_pw="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 || true)"
    # Drive wp-admin/install.php non-interactively (step=2).
    if ! curl -fsS --max-time 60 \
            --data-urlencode "weblog_title=Lapin Logistics — Marketing" \
            --data-urlencode "user_name=peter" \
            --data-urlencode "admin_password=${_admin_pw}" \
            --data-urlencode "admin_password2=${_admin_pw}" \
            --data-urlencode "pw_weak=1" \
            --data-urlencode "admin_email=peter.cottontail@lapinlogistics.com" \
            --data-urlencode "Submit=Install WordPress" \
            --data-urlencode "language=" \
            "${WP_URL}/wp-admin/install.php?step=2" >/dev/null 2>&1; then
        warn "06-web-wordpress: WP install endpoint did not respond — falling back to static landing page"
        _real_wp_ok=0
    fi
    unset _admin_pw

    if [[ "$_real_wp_ok" == "1" ]]; then
        # Normalise content directly in the DB. Idempotent via INSERT ... SELECT
        # WHERE NOT EXISTS / UPDATE guards.
        if ! mysql --protocol=socket -u root "${WP_DB_NAME}" <<SQL 2>>"${LAPIN_LOG_FILE:-/dev/null}"
-- velveteen WP subscriber account
INSERT INTO wp_users (user_login,user_pass,user_nicename,user_email,user_registered,display_name)
SELECT 'velveteen', MD5(RAND()), 'velveteen', 'velveteen@lapinlogistics.com', NOW(), 'Velveteen Rabbit'
WHERE NOT EXISTS (SELECT 1 FROM wp_users WHERE user_login='velveteen');
INSERT INTO wp_usermeta (user_id, meta_key, meta_value)
SELECT u.ID, 'wp_capabilities', 'a:1:{s:10:"subscriber";b:1;}'
FROM wp_users u WHERE u.user_login='velveteen'
  AND NOT EXISTS (SELECT 1 FROM wp_usermeta m WHERE m.user_id=u.ID AND m.meta_key='wp_capabilities');
-- SNMP-rotate post dated ~3y ago
INSERT INTO wp_posts (post_author,post_date,post_date_gmt,post_content,post_title,post_status,comment_status,post_name,post_modified,post_modified_gmt,post_type)
SELECT 1,'${WP_POST_DATE}','${WP_POST_DATE}',
 'IT keeps flagging this every quarter and it never gets done. The SNMP community string is still the shipped default and the Q4 audit is coming.',
 'Reminder: rotate the SNMP community string before Q4 audit','publish','open','rotate-snmp-q4',
 '${WP_POST_DATE}','${WP_POST_DATE}','post'
WHERE NOT EXISTS (SELECT 1 FROM wp_posts WHERE post_title='Reminder: rotate the SNMP community string before Q4 audit');
-- roger's approved comment re /opt/lapin-tools
INSERT INTO wp_comments (comment_post_ID,comment_author,comment_author_email,comment_content,comment_approved,comment_date,comment_date_gmt)
SELECT p.ID,'roger','roger.rabbit@lapinlogistics.com',
 'And while we are at it, the junk in /opt/lapin-tools needs cleaning up — half of it is world-writable scratch scripts from the migration.',
 '1','${WP_POST_DATE}','${WP_POST_DATE}'
FROM wp_posts p WHERE p.post_title='Reminder: rotate the SNMP community string before Q4 audit'
  AND NOT EXISTS (SELECT 1 FROM wp_comments c WHERE c.comment_author='roger' AND c.comment_post_ID=p.ID);
SQL
        then
            warn "06-web-wordpress: SQL content seeding failed"
            _real_wp_ok=0
        fi
    fi

    # Outdated plugin: drop its files so wpscan enumerates it from readme.txt
    # even without wp-cli (inactive — no RCE).
    if [[ "$_real_wp_ok" == "1" ]]; then
        _plugdir="${WP_DOCROOT}/wp-content/plugins/${WP_PLUGIN_SLUG}"
        if [[ ! -f "${_plugdir}/readme.txt" ]]; then
            _pstage="$(mktemp -d)"
            trap 'rm -rf -- "${_pstage:-}"' EXIT
            if command -v curl >/dev/null 2>&1 \
               && curl -fsSL --max-time 60 -o "${_pstage}/p.zip" "${WP_PLUGIN_URL}" 2>/dev/null \
               && command -v unzip >/dev/null 2>&1 \
               && unzip -q "${_pstage}/p.zip" -d "${WP_DOCROOT}/wp-content/plugins/" 2>/dev/null; then
                log "06-web-wordpress: outdated plugin ${WP_PLUGIN_SLUG} ${WP_PLUGIN_VERSION} placed (inactive)"
            else
                warn "06-web-wordpress: plugin download failed (non-fatal; core WP still fingerprintable)"
            fi
            rm -rf -- "${_pstage}"
            trap - EXIT
            unset _pstage
        fi
        unset _plugdir
    fi
fi

# 5g. Final ownership for a successful real install. ------------------------
if [[ "$_real_wp_ok" == "1" ]]; then
    chown -R "${WEB_USER}:${WEB_USER}" "${WP_DOCROOT}"
    log "06-web-wordpress: real WordPress ${WP_VERSION} install complete"
fi

# ---------------------------------------------------------------------------
# 6. Fallback decision — if anything above failed, degrade (do NOT die).
# ---------------------------------------------------------------------------
if [[ "$_real_wp_ok" != "1" ]]; then
    deploy_static_wp
fi

# ---------------------------------------------------------------------------
# 7. (Re)start Apache so :8080 is live.
# ---------------------------------------------------------------------------
log "06-web-wordpress: enabling and restarting apache"
apache_restart_safe

log "06-web-wordpress: DONE"
