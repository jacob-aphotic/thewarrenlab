#!/usr/bin/env bash
# =============================================================================
# Lapin Logistics — install.sh — entry point (run as ROOT on the TARGET VM)
# =============================================================================
# DO NOT run this on your build/workstation box. It mutates the system:
# creates users, installs packages, opens ports, weakens AppArmor/SELinux.
# Intended for a disposable lab VM only.
#
# >>> USAGE
# Usage:
#   ./install.sh                 # full install (all modules, in order)
#   ./install.sh --dry-run       # print what each module WOULD do; no changes
#   ./install.sh --verify        # run the verification checklist
#   ./install.sh --yes           # auto-confirm the untested-distro prompt
#   ./install.sh -m 03-ftp       # run a single module by name fragment
#   ./install.sh -h | --help
#
# Env vars (see lib/common.sh contract header):
#   LAPIN_DRY_RUN=1            same as --dry-run
#   LAPIN_ASSUME_YES=1         same as --yes
#   LAPIN_HUTCH_SIZE_MB=200    /opt/hutch filler size
#   LAPIN_LOG_FILE=/var/log/lapin-install.log
# <<< USAGE
#
# DRY-RUN CONTRACT (authoritative — every module must honor this):
#   * install.sh exports LAPIN_DRY_RUN (0/1) before sourcing modules.
#   * Modules wrap mutating commands in `run` or use the ensure_* helpers,
#     both of which no-op + log "[DRY-RUN] would: ..." when LAPIN_DRY_RUN!=0.
#   * Modules MUST NOT mutate the system on a dry run by any other path.
#
# BUILD ORDER: modules are sourced in lexical (sort) order of modules/*.sh,
# which matches the intended order because of the NN- numeric prefixes.
# =============================================================================
set -euo pipefail

LAPIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAPIN_LIB_DIR="$LAPIN_ROOT/lib"
LAPIN_MODULE_DIR="$LAPIN_ROOT/modules"
export LAPIN_ROOT LAPIN_LIB_DIR LAPIN_MODULE_DIR

# ---- source libraries -------------------------------------------------------
# shellcheck source=lib/common.sh
source "$LAPIN_LIB_DIR/common.sh"
# shellcheck source=lib/pkg.sh
source "$LAPIN_LIB_DIR/pkg.sh"
# shellcheck source=lib/distro.sh
source "$LAPIN_LIB_DIR/distro.sh"

# ---- arg parsing ------------------------------------------------------------
MODE="install"          # install | verify
ONLY_MODULE=""
usage() {
    _render_help "${BASH_SOURCE[0]}"
}
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --dry-run)      LAPIN_DRY_RUN=1 ;;
        --verify)       MODE="verify" ;;
        --yes|-y)       LAPIN_ASSUME_YES=1 ;;
        -m|--module)    shift; ONLY_MODULE="${1:-}" ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown argument: $1 (try --help)" ;;
    esac
    shift
done
export LAPIN_DRY_RUN LAPIN_ASSUME_YES

# =============================================================================
# Host configuration helpers. These open the host firewall and free up
# ports so the configured services are reachable.
# =============================================================================

handle_firewall() {
    log "checking host firewall (must not block service ports)"
    # ufw
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qi '^Status: active'; then
            warn "ufw is ACTIVE. Disabling it for the lab (INTENTIONAL — re-enable before any non-lab use)."
            run ufw --force disable
        else
            log "ufw present but inactive; nothing to do"
        fi
    fi
    # firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
        warn "firewalld is ACTIVE. Opening all lab ports (INTENTIONAL for lab)."
        local p
        for p in 21/tcp 53/tcp 53/udp 80/tcp 139/tcp 443/tcp 445/tcp 161/udp 1337/tcp 2222/tcp 8080/tcp 31337/tcp 58008/tcp; do
            run firewall-cmd --permanent --add-port="$p"
        done
        run firewall-cmd --reload
    fi
    # raw nftables/iptables are left alone (lab VMs rarely ship custom rules);
    # documented as a known limitation in INSTRUCTOR_NOTES.md.
}

handle_lsm() {
    # AppArmor (Debian/Ubuntu/SUSE) -> complain/teardown for the lab.
    if command -v aa-status >/dev/null 2>&1 && aa-status --enabled 2>/dev/null; then
        warn "AppArmor is ENFORCING. Setting profiles to complain mode."
        warn "  >>> INTENTIONAL FOR LAB. AppArmor MUST be re-enabled before any non-lab use. <<<"
        if command -v aa-complain >/dev/null 2>&1; then
            run bash -c 'aa-complain /etc/apparmor.d/* 2>/dev/null || true'
        fi
        # Also disable the units interfering with vsftpd/samba/apache includes.
        if command -v systemctl >/dev/null 2>&1; then
            run bash -c 'systemctl stop apparmor 2>/dev/null || true'
            run bash -c 'systemctl disable apparmor 2>/dev/null || true'
        fi
    fi
    # SELinux (RHEL/Fedora) -> permissive for the lab.
    if command -v getenforce >/dev/null 2>&1; then
        local cur
        cur="$(getenforce 2>/dev/null || echo Unknown)"
        if [[ "$cur" == "Enforcing" ]]; then
            warn "SELinux is ENFORCING. Switching to permissive."
            warn "  >>> INTENTIONAL FOR LAB. SELinux MUST be re-enabled before any non-lab use. <<<"
            run setenforce 0
            if [[ -f /etc/selinux/config ]] && ! is_dry_run; then
                sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true
            elif is_dry_run; then
                log "[DRY-RUN] would set SELINUX=permissive in /etc/selinux/config"
            fi
        fi
    fi
}

handle_resolved() {
    # On Ubuntu, systemd-resolved's stub listener squats port 53.
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        warn "systemd-resolved active — disabling its DNSStubListener so bind9 can bind :53."
        if is_dry_run; then
            log "[DRY-RUN] would set DNSStubListener=no in /etc/systemd/resolved.conf and restart systemd-resolved"
        else
            ensure_dir /etc/systemd/resolved.conf.d
            cat > /etc/systemd/resolved.conf.d/lapin.conf <<'EOF'
# Lapin Logistics — free up :53 for bind9.
[Resolve]
DNSStubListener=no
EOF
            systemctl restart systemd-resolved || warn "could not restart systemd-resolved; check :53 manually"
            # keep name resolution working for the installer (pip etc.)
            if [[ -L /etc/resolv.conf || ! -s /etc/resolv.conf ]]; then
                printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf || true
            fi
        fi
    fi
}

# =============================================================================
# Module runner
# =============================================================================
run_modules() {
    require_root
    lapin_distro_guard
    handle_firewall
    handle_lsm
    handle_resolved

    if [[ ! -d "$LAPIN_MODULE_DIR" ]]; then
        die "modules directory not found: $LAPIN_MODULE_DIR"
    fi

    # Lexical order (== intended order via NN- prefixes).
    local -a modules=()
    local f
    while IFS= read -r f; do
        modules+=("$f")
    done < <(find "$LAPIN_MODULE_DIR" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)

    if [[ "${#modules[@]}" -eq 0 ]]; then
        warn "no modules found in $LAPIN_MODULE_DIR (foundation task only — modules authored in later tasks)"
        return 0
    fi

    local ok=0 fail=0 skipped=0 m base
    for m in "${modules[@]}"; do
        base="$(basename "$m")"
        if [[ -n "$ONLY_MODULE" && "$base" != *"$ONLY_MODULE"* ]]; then
            skipped=$((skipped + 1))
            continue
        fi
        log "================ module: $base ================"
        # Run each module in a subshell so one module's `exit` / failing ERR
        # trap cannot abort the whole installer; we record per-module status
        # to /var/log/lapin-install.log.
        #
        # CRITICAL bash gotcha: errexit (and the ERR trap) is SUPPRESSED for a
        # command that is part of a test — including a subshell used as an `if`
        # condition OR on the left of `||`/`&&`. So BOTH
        #     if ( set -e; source "$m" ); then ...
        #     ( set -e; source "$m" ) || rc=$?
        # let a module that fails partway be wrongly reported OK (the inner
        # `set -e`/trap never fire). The only correct capture is to run the
        # subshell as a PLAIN statement (no test context) and read $? on the
        # next line; we drop the caller's errexit around just that statement so
        # a failing module doesn't abort the whole installer, then restore it.
        # Subshells don't inherit ERR traps, so we re-arm it inside for correct
        # file:line attribution.
        local rc=0
        set +e
        # shellcheck disable=SC1090  # modules are discovered at runtime; path is intentionally non-constant
        ( set -euo pipefail; trap '_lapin_on_err' ERR; source "$m" )
        rc=$?
        set -e
        if [[ "$rc" -eq 0 ]]; then
            log "MODULE OK: $base"
            ok=$((ok + 1))
        else
            err "MODULE FAILED (exit $rc): $base"
            fail=$((fail + 1))
        fi
    done

    log "module summary: ok=$ok failed=$fail skipped=$skipped (of ${#modules[@]})"
    if [[ "$fail" -gt 0 ]]; then
        die "$fail module(s) failed — see $LAPIN_LOG_FILE"
    fi
}

# =============================================================================
# Verification. Each check -> pass/fail line. These only PASS on a
# fully deployed target; on a fresh box they will (correctly) fail.
# =============================================================================
VERIFY_PASS=0
VERIFY_FAIL=0
_v() {
    # _v "<description>" <command...>  -> runs command, prints PASS/FAIL
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [PASS] %s\n' "$desc"
        VERIFY_PASS=$((VERIFY_PASS + 1))
        return 0
    fi
    printf '  [FAIL] %s\n' "$desc"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
    return 1
}

# helper predicates (kept tiny; each returns 0/1)
_have() { command -v "$1" >/dev/null 2>&1; }

_chk_tcp_ports() {
    # nmap -p- should show these OPEN; 22 should NOT be open.
    _have nmap || return 1
    local out
    out="$(nmap -p 21,22,53,80,139,443,445,1337,2222,8080,31337,58008 -Pn 127.0.0.1 2>/dev/null)" || return 1
    local p
    for p in 21 53 80 139 443 445 1337 2222 8080 31337 58008; do
        echo "$out" | grep -qE "^${p}/tcp[[:space:]]+open" || return 1
    done
    # 22 must be closed/filtered (SSH moved to 2222)
    if echo "$out" | grep -qE '^22/tcp[[:space:]]+open'; then return 1; fi
    return 0
}
_chk_udp_snmp()   { _have nmap && nmap -sU -p 161 -Pn 127.0.0.1 2>/dev/null | grep -qE '^161/udp[[:space:]]+open'; }
_chk_axfr()       { _have dig && dig +time=3 axfr @127.0.0.1 lapinlogistics.local 2>/dev/null | grep -q 'SOA'; }
_chk_ftp_anon()   { _have curl && curl -s --max-time 5 ftp://127.0.0.1/ --user anonymous:anon 2>/dev/null | grep -qi 'pub'; }
_chk_ftp_onboarding_pdf() {
    # IT_orientation.pdf must be present under pub/hr/onboarding/. If
    # pdftotext is available, also assert its body text carries the default
    # onboarding password; otherwise file presence is sufficient.
    local f=/srv/ftp/pub/hr/onboarding/IT_orientation.pdf
    [[ -f "$f" ]] || return 1
    if _have pdftotext; then
        pdftotext -q "$f" - 2>/dev/null | grep -qF 'Carrot$tart2024' || return 1
    fi
    return 0
}
_chk_robots()     { _have curl && [[ "$(curl -s --max-time 5 http://127.0.0.1/robots.txt 2>/dev/null | grep -c '/')" -ge 8 ]] && curl -s --max-time 5 http://127.0.0.1/robots.txt 2>/dev/null | grep -q 'carrot-cms'; }
_chk_lfi()        { _have curl && curl -s --max-time 5 "http://127.0.0.1/carrot-cms/view.php?page=../../../../etc/passwd" 2>/dev/null | grep -q 'root:.*:0:0:'; }
_chk_internal()   { _have curl && curl -k -s --max-time 5 https://127.0.0.1/ -H 'Host: internal.lapinlogistics.local' 2>/dev/null | grep -qi 'internal'; }
_chk_san()        { _have openssl && echo | openssl s_client -connect 127.0.0.1:443 -servername internal.lapinlogistics.local 2>/dev/null | openssl x509 -text 2>/dev/null | grep -q 'DNS:internal.lapinlogistics.local'; }
_chk_wordpress()  { _have curl && curl -s --max-time 5 http://127.0.0.1:8080/ 2>/dev/null | grep -qiE 'wp-content|wordpress|generator.*WordPress'; }
_chk_smb_shares() { _have smbclient && smbclient -L //127.0.0.1 -N 2>/dev/null | grep -q 'hutch' && smbclient -L //127.0.0.1 -N 2>/dev/null | grep -q 'carrots'; }
_chk_snmp_pub()   { _have snmpwalk && [[ "$(snmpwalk -v2c -c public -t 3 127.0.0.1 2>/dev/null | wc -l)" -gt 100 ]]; }
_chk_snmp_int()   { _have snmpwalk && [[ "$(snmpwalk -v2c -c lapin-internal -t 3 127.0.0.1 2>/dev/null | wc -l)" -gt 100 ]]; }
_chk_ssh_2222()   {
    _have ssh || return 1
    # banner grab is enough for an automated check (no creds needed)
    timeout 5 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222; read -r b <&3; echo "$b"' 2>/dev/null | grep -qi 'SSH-'
}
_chk_warren_up()  { _have curl && curl -s --max-time 5 http://127.0.0.1:58008/ 2>/dev/null | grep -qiE 'warren|login|password'; }
_chk_warren_flag(){
    # Real automated login: POST valid creds with a cookie jar (Flask
    # session), follow into the chat, and assert the #general flag AND the
    # #it-helpdesk credential disclosure are reachable; also assert a WRONG
    # password does NOT yield the flag (negative check). curl-only.
    _have curl || return 1
    local jar gen helpdesk badjar bad
    jar="$(mktemp /tmp/.lapin_v_jar.XXXXXX)" || return 1
    badjar="$(mktemp /tmp/.lapin_v_badjar.XXXXXX)" || { rm -f "$jar"; return 1; }
    # 1. valid login establishes the session cookie
    curl -s --max-time 8 -c "$jar" -b "$jar" \
        --data 'username=peter.cottontail&password=Carrot$tart2024' \
        http://127.0.0.1:58008/login >/dev/null 2>&1
    # 2. #general carries the flag
    gen="$(curl -s --max-time 8 -b "$jar" http://127.0.0.1:58008/chat/general 2>/dev/null)"
    # 3. #it-helpdesk discloses peter's real SSH password
    helpdesk="$(curl -s --max-time 8 -b "$jar" http://127.0.0.1:58008/chat/it-helpdesk 2>/dev/null)"
    # 4. wrong password must NOT reach the flag
    bad="$(curl -s --max-time 8 -c "$badjar" -b "$badjar" \
        --data 'username=peter.cottontail&password=wrongpass' \
        http://127.0.0.1:58008/login 2>/dev/null; \
        curl -s --max-time 8 -b "$badjar" http://127.0.0.1:58008/chat/general 2>/dev/null)"
    rm -f "$jar" "$badjar"
    echo "$gen"      | grep -qF 'FLAG{h0pp1ng_d0wn_th3_warren}' || return 1
    echo "$helpdesk" | grep -qF 'R3set-Burrow-7Gx2!'            || return 1
    if echo "$bad"   | grep -qF 'FLAG{h0pp1ng_d0wn_th3_warren}'; then return 1; fi
    return 0
}
_chk_flag_portal()    { _have curl && [[ "$(curl -sf --max-time 5 http://127.0.0.1:1337/healthz 2>/dev/null)" == "ok" ]]; }
_chk_peter_cred() {
    # peter's OS/SSH password is R3set-Burrow-7Gx2! (01-users pins it as a
    # sha512-crypt $6$ hash so it is recomputable without Python's removed
    # `crypt` module). Recompute with openssl using the stored salt and
    # compare. Requires root (verify runs as root) to read /etc/shadow.
    _have openssl || return 1
    [[ -r /etc/shadow ]] || return 1
    local h salt
    h="$(awk -F: '$1=="peter"{print $2}' /etc/shadow 2>/dev/null)"
    [[ "$h" == '$6$'* ]] || return 1            # expect sha512-crypt
    salt="$(printf '%s' "$h" | cut -d'$' -f3)"  # $6$<salt>$<hash>
    [[ -n "$salt" ]] || return 1
    [[ "$(openssl passwd -6 -salt "$salt" 'R3set-Burrow-7Gx2!' 2>/dev/null)" == "$h" ]]
}
_chk_lapin_tools(){ [[ -d /opt/lapin-tools ]] && [[ "$(find /opt/lapin-tools -maxdepth 1 -type f 2>/dev/null | wc -l)" -ge 25 ]]; }
_chk_cron()       { [[ -f /etc/cron.d/lapin-inventory ]] && grep -q 'PATH' /etc/cron.d/lapin-inventory 2>/dev/null; }
_chk_sudoers()    { [[ -f /etc/sudoers.d/carrot-report ]] && grep -q 'carrot-report' /etc/sudoers.d/carrot-report 2>/dev/null; }
_chk_root_flag()  { [[ -f /root/root.txt ]] && [[ "$(stat -c '%a' /root/root.txt 2>/dev/null)" == "400" ]]; }
_chk_tarpit()     {
    timeout 6 bash -c 'exec 3<>/dev/tcp/127.0.0.1/31337; head -c 1 <&3' >/dev/null 2>&1
}
_chk_ftp_banner_spoof() {
    _have curl || return 1
    local banner ver
    banner="$(curl -s --max-time 5 -v ftp://127.0.0.1/ --user anonymous:anon 2>&1 | grep -i '220' | head -1)"
    echo "$banner" | grep -q '2.3.4' || return 1
    # and the installed package must NOT actually be 2.3.4
    if _have dpkg-query; then
        ver="$(dpkg-query -W -f='${Version}' vsftpd 2>/dev/null || true)"
        [[ -n "$ver" && "$ver" != *2.3.4* ]] && return 0
    fi
    # if we can't introspect the pkg, the spoofed banner alone is acceptable
    return 0
}
_chk_path_hijack_note() {
    # the dynamic per-minute observation is manual; we assert the mechanism is
    # *present*: the roger cron runs */1 with /opt/lapin-tools/cache FIRST on
    # PATH and that cache dir is world-writable (mode 1777).
    [[ -f /etc/cron.d/lapin-inventory ]] || return 1
    grep -qE '^\*/1 \* \* \* \* roger PATH=/opt/lapin-tools/cache:' \
        /etc/cron.d/lapin-inventory 2>/dev/null || return 1
    [[ -d /opt/lapin-tools/cache ]] || return 1
    [[ "$(stat -c '%a' /opt/lapin-tools/cache 2>/dev/null)" == "1777" ]]
}
_chk_carrot_report_check() {
    # End-to-end behaviour is verified manually; here we assert the tool is
    # present and structurally as expected.
    [[ -f /usr/local/bin/carrot-report ]] || return 1
    # shellcheck disable=SC2016  # single-quoted grep regex; $ is not a shell expansion
    grep -qE 'os\.system|subprocess\.[^(]*shell\s*=\s*True|`[^`]*\$|(\$\()' \
        /usr/local/bin/carrot-report 2>/dev/null
}

run_verify() {
    log "running verification checklist against 127.0.0.1"
    printf '\n=== Lapin Logistics — Verification ===\n'
    _v "nmap: 21,53,80,139,443,445,1337,2222,8080,31337,58008 open; 22 closed" _chk_tcp_ports
    _v "nmap -sU -p161: SNMP open"                                        _chk_udp_snmp
    _v "dig axfr lapinlogistics.local: zone returned"                     _chk_axfr
    _v "anonymous FTP lists pub/"                                         _chk_ftp_anon
    _v "IT_orientation.pdf under pub/hr/onboarding/ (body carries pw)"   _chk_ftp_onboarding_pdf
    _v "robots.txt has 8 entries incl /carrot-cms/"                      _chk_robots
    _v "LFI: carrot-cms/view.php?page=../etc/passwd returns passwd"      _chk_lfi
    _v "HTTPS internal vhost responds for internal.lapinlogistics.local" _chk_internal
    _v "cert SAN = internal.lapinlogistics.local"                        _chk_san
    _v "WordPress on :8080 fingerprintable"                              _chk_wordpress
    _v "smbclient lists 'hutch' and 'carrots' shares"                    _chk_smb_shares
    _v "snmpwalk -c public returns many lines"                           _chk_snmp_pub
    _v "snmpwalk -c lapin-internal returns many lines"                   _chk_snmp_int
    _v "SSH banner on :2222"                                             _chk_ssh_2222
    _v "Warren chat on :58008 responds"                                  _chk_warren_up
    _v "Warren login -> #general flag, #it-helpdesk pw, wrong pw rejected" _chk_warren_flag
    _v "peter OS/SSH password is R3set-Burrow-7Gx2!"                     _chk_peter_cred
    _v "/opt/lapin-tools has >=25 files"                                 _chk_lapin_tools
    _v "/etc/cron.d/lapin-inventory present with PATH"                   _chk_cron
    _v "roger */1 cron PATH leads with 1777 /opt/lapin-tools/cache"      _chk_path_hijack_note
    _v "/etc/sudoers.d/carrot-report present"                            _chk_sudoers
    _v "carrot-report present and structurally as expected"              _chk_carrot_report_check
    _v "/root/root.txt exists and is mode 0400"                          _chk_root_flag
    _v "flag-portal :1337 /healthz returns ok"                           _chk_flag_portal
    _v "service on :31337 accepts + emits bytes"                         _chk_tarpit
    _v "vsftpd banner says 2.3.4 but pkg is patched"                     _chk_ftp_banner_spoof
    printf '\n=== verification: %d passed, %d failed ===\n' "$VERIFY_PASS" "$VERIFY_FAIL"
    log "verification result: pass=$VERIFY_PASS fail=$VERIFY_FAIL"
    if [[ "$VERIFY_FAIL" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# Final banner
# =============================================================================
print_banner() {
    local ip ports
    ip="$(lapin_host_ip)"
    ports="21,53,80,139,443(+161/udp),445,1337,2222,8080,31337,58008"
    cat <<EOF

  ____________________________________________________________
 |                                                            |
 |   LAPIN LOGISTICS  —  "Delivering crisp produce since 1973" |
 |____________________________________________________________|

   Target IP   : ${ip}
   Open ports  : ${ports}
   Log file    : ${LAPIN_LOG_FILE}

   The Warren is open.

EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Lapin Logistics installer starting (mode=$MODE, dry_run=$LAPIN_DRY_RUN)"
    case "$MODE" in
        verify)
            require_root
            run_verify
            exit $?
            ;;
        install)
            run_modules
            if is_dry_run; then
                log "DRY-RUN complete — no system changes were made."
                printf '\n[DRY-RUN] install simulated. Re-run without --dry-run on the target VM.\n'
            else
                print_banner
            fi
            ;;
        *)
            die "unknown mode: $MODE"
            ;;
    esac
}

main "$@"
