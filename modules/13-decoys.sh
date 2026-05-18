#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/13-decoys.sh — Lapin Logistics — auxiliary data + local tooling
# =============================================================================
# Owned by THIS module (cross-module ownership):
#   /opt/hutch/hutch.dat            ~${LAPIN_HUTCH_SIZE_MB:-200}MB of /dev/urandom
#   /opt/backup/*.tar.gz            stale tarballs of archived carrot-inventory
#                                   CSV exports. World-readable.
#   /usr/local/bin/lapin-status     small SUID-root utility (no input)
#   /usr/local/bin/lapin-greeter    small SUID-root utility (bounded argv)
#   /usr/local/bin/lapin-check      small SUID-root utility (fixed subprocess)
#   pkexec / polkit                 ASSURED PRESENT + CURRENT (current OS
#                                   package; we do NOT install an old build).
#
# Not touched here (owned elsewhere):
#   /opt/lapin-tools/   -> 11-tarpit + 12-privesc   (we never reference it)
#   /etc/cron.d/lapin-rotate-logs -> 12-privesc
#   /home/*/.bash_history -> 14-bash-history ;  flags -> 99-flags
#
# DRY-RUN SAFE: every mutation via run / ensure_* / is_dry_run-gated blocks.
#               In dry-run NO gcc compile and NO dd ever runs, /opt/hutch and
#               /opt/backup are NOT created, no SUID binary is produced.
# IDEMPOTENT:   the 200MB hutch is create-only-if-absent-or-size-mismatch (it
#               is expensive to regenerate); backups/SUIDs are authoritatively
#               rebuilt every run; perms/ownership re-applied each time.
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

# Hutch size — tunable for low-disk VMs. common.sh already exports
# LAPIN_HUTCH_SIZE_MB defaulting to 200; we re-default defensively so a
# standalone run with the var unset still behaves as expected.
_HUTCH_MB="${LAPIN_HUTCH_SIZE_MB:-200}"
if ! [[ "$_HUTCH_MB" =~ ^[0-9]+$ ]] || [[ "$_HUTCH_MB" -lt 1 ]]; then
    warn "13-decoys: LAPIN_HUTCH_SIZE_MB='${_HUTCH_MB}' is not a positive integer — falling back to 200"
    _HUTCH_MB=200
fi

log "13-decoys: starting (hutch=${_HUTCH_MB}MB, 3 SUID utilities, /opt/backup archives, pkexec assurance)"

# ===========================================================================
# 1. /opt/hutch/ — ~${_HUTCH_MB}MB binary data blob. Create-only-if-absent-or-
#    size-mismatch: 200MB is expensive to regenerate, so we do NOT overwrite a
#    correctly-sized existing file on every re-run (idempotent + cheap).
# ===========================================================================
ensure_dir /opt/hutch 755 root:root
_HUTCH_FILE="/opt/hutch/hutch.dat"
_HUTCH_BYTES=$(( _HUTCH_MB * 1024 * 1024 ))

# Decide whether (re)generation is needed — pure inspection, dry-run safe.
_hutch_need_gen=1
if [[ -f "$_HUTCH_FILE" ]]; then
    _cur_bytes="$(stat -c '%s' "$_HUTCH_FILE" 2>/dev/null || echo -1)"
    if [[ "$_cur_bytes" == "$_HUTCH_BYTES" ]]; then
        _hutch_need_gen=0
        log "13-decoys: ${_HUTCH_FILE} already present at exactly ${_HUTCH_BYTES} bytes — keeping (idempotent)"
    else
        log "13-decoys: ${_HUTCH_FILE} present but ${_cur_bytes} bytes != ${_HUTCH_BYTES} — regenerating"
    fi
    unset _cur_bytes
fi

if [[ "$_hutch_need_gen" -eq 1 ]]; then
    if is_dry_run; then
        log "[DRY-RUN] would dd if=/dev/urandom of=${_HUTCH_FILE} bs=1M count=${_HUTCH_MB} (NO dd run in dry-run)"
    else
        log "13-decoys: generating ${_HUTCH_MB}MB of /dev/urandom -> ${_HUTCH_FILE} (this can take a while)"
        # status=none keeps the transcript clean; the size check below is the
        # real verification. Write to a temp then move so an interrupted run
        # never leaves a wrong-sized file that a re-run would 'keep'.
        _hutch_tmp="${_HUTCH_FILE}.tmp.$$"
        if ! dd if=/dev/urandom of="$_hutch_tmp" bs=1M count="$_HUTCH_MB" status=none 2>/dev/null; then
            rm -f "$_hutch_tmp" 2>/dev/null || true
            die "13-decoys: dd failed generating ${_HUTCH_FILE} (disk full? lower LAPIN_HUTCH_SIZE_MB)"
        fi
        _got="$(stat -c '%s' "$_hutch_tmp" 2>/dev/null || echo -1)"
        if [[ "$_got" != "$_HUTCH_BYTES" ]]; then
            rm -f "$_hutch_tmp" 2>/dev/null || true
            die "13-decoys: hutch size mismatch (got ${_got}, want ${_HUTCH_BYTES} bytes) — aborting"
        fi
        mv "$_hutch_tmp" "$_HUTCH_FILE"
        unset _hutch_tmp _got
        log "13-decoys: ${_HUTCH_FILE} written (${_HUTCH_BYTES} bytes)"
    fi
fi
if ! is_dry_run; then
    run chmod 0644 "$_HUTCH_FILE"
    run chown root:root "$_HUTCH_FILE"
fi
unset _hutch_need_gen

# ===========================================================================
# 2. /opt/backup/ — 7 world-readable tarballs of archived carrot-inventory
#    CSV exports. Authoritatively rebuilt each run (small files; keeps content
#    deterministic so re-runs do not drift).
# ===========================================================================
ensure_dir /opt/backup 755 root:root

# Archive names by year/quarter. 7 tarballs.
_BACKUP_TARBALLS=(
    "carrot_db_2019.tar.gz|carrot_inventory_2019"
    "carrot_db_2020.tar.gz|carrot_inventory_2020"
    "warehouse_export_2021.tar.gz|warehouse_export_2021"
    "produce_audit_2021Q4.tar.gz|produce_audit_2021Q4"
    "lettuce_stock_2022.tar.gz|lettuce_stock_2022"
    "shipping_manifest_2022.tar.gz|shipping_manifest_2022"
    "hutch_census_2023.tar.gz|hutch_census_2023"
)

log "13-decoys: building ${#_BACKUP_TARBALLS[@]} archive tarballs in /opt/backup/ (world-readable)"
if is_dry_run; then
    for _bt in "${_BACKUP_TARBALLS[@]}"; do
        log "[DRY-RUN] would write /opt/backup/${_bt%%|*} (~5MB CSV export, mode 0644)"
    done
    unset _bt
else
    command -v tar >/dev/null 2>&1 \
        || die "13-decoys: 'tar' not found — cannot build /opt/backup tarballs"
    _bk_work="$(mktemp -d /tmp/lapin-backup.XXXXXX)" \
        || die "13-decoys: could not create temp workdir for backup tarballs"
    # Always clean the scratch workdir however we leave this block.
    trap 'rm -rf "${_bk_work:-}" 2>/dev/null || true' EXIT
    _bk_i=0
    for _bt in "${_BACKUP_TARBALLS[@]}"; do
        _bk_name="${_bt%%|*}"
        _bk_inner="${_bt#*|}"
        _bk_i=$((_bk_i + 1))
        _bk_dir="${_bk_work}/${_bk_inner}"
        mkdir -p "$_bk_dir"
        _csv="${_bk_dir}/inventory.csv"
        # Deterministic CSV header + ~5MB of inventory rows.
        printf 'sku,description,region,qty,unit_cost,last_audit\n' > "$_csv"
        awk -v seed="$_bk_i" 'BEGIN{
            srand(seed*7919);
            regions[0]="north"; regions[1]="south"; regions[2]="east"; regions[3]="west"; regions[4]="central";
            kinds[0]="Nantes"; kinds[1]="Imperator"; kinds[2]="Danvers"; kinds[3]="Chantenay"; kinds[4]="Babette";
            # ~70000 rows ~= 5MB of pure junk.
            for(i=1;i<=70000;i++){
                sku=sprintf("CR-%06d", i);
                k=kinds[int(rand()*5)];
                r=regions[int(rand()*5)];
                q=int(rand()*5000)+1;
                c=sprintf("%.2f", rand()*3+0.10);
                d=sprintf("20%02d-%02d-%02d", int(rand()*5)+18, int(rand()*12)+1, int(rand()*28)+1);
                printf "%s,%s carrots crate,%s,%d,%s,%s\n", sku, k, r, q, c, d;
            }
        }' >> "$_csv"
        # Archive README inside each tarball.
        printf '%s\n' \
            "Lapin Logistics — archived carrot inventory export." \
            "Retained for accounting/audit retention. Refer to the live" \
            "inventory system for current figures." \
            > "${_bk_dir}/README.txt"
        tar -czf "/opt/backup/${_bk_name}" -C "$_bk_work" "$_bk_inner" \
            || die "13-decoys: failed to build /opt/backup/${_bk_name}"
        chmod 0644 "/opt/backup/${_bk_name}"
        chown root:root "/opt/backup/${_bk_name}"
    done
    log "13-decoys: wrote ${_bk_i} tarballs to /opt/backup/ (0644, root:root)"
    rm -rf "$_bk_work" 2>/dev/null || true
    trap - EXIT
    unset _bk_work _bk_i _bt _bk_name _bk_inner _bk_dir _csv
fi

# ===========================================================================
# 3. Three small SUID-root utilities. Compiled C — Linux ignores the setuid
#    bit on scripts. We embed tiny C sources, gcc them, then chown root:root
#    + chmod 4755:
#      lapin-status  — no argv use at all, prints a fixed line.
#      lapin-greeter — uses argv[1] ONLY via a bounded copy with a fixed
#                      "%s" format string, then a length-capped copy. No
#                      system()/exec*, no %n, no unbounded strcpy/sprintf.
#      lapin-check   — execl("/bin/true",...) — fixed program, no user input,
#                      no user-controlled path or args.
# ===========================================================================
_SUID_DIR="/usr/local/bin"
ensure_dir "$_SUID_DIR" 755 root:root

# C sources kept as heredoc-able strings written to a scratch dir, compiled,
# installed. (Embedded verbatim so the module is self-contained.)
_build_suid() {
    # $1 = basename ; $2 = path to .c source already written
    local name="$1" src="$2" out
    out="${_SUID_DIR}/${name}"
    gcc -O2 -w -o "$out" "$src" \
        || die "13-decoys: gcc failed compiling ${name}"
    chown root:root "$out"
    chmod 4755 "$out"
    log "13-decoys: installed SUID-root ${out} (mode 4755, root:root)"
}

log "13-decoys: building 3 SUID-root utilities in ${_SUID_DIR}/"
if is_dry_run; then
    log "[DRY-RUN] would gcc-compile + install: lapin-status, lapin-greeter, lapin-check (NO gcc run in dry-run)"
    log "[DRY-RUN] would chown root:root + chmod 4755 each of the 3 SUID binaries"
else
    command -v gcc >/dev/null 2>&1 \
        || die "13-decoys: gcc not found — 00-prereqs installs build-essential; run it first (need a C compiler)"

    _suid_work="$(mktemp -d /tmp/lapin-suid.XXXXXX)" \
        || die "13-decoys: could not create temp workdir for SUID compile"
    trap 'rm -rf "${_suid_work:-}" 2>/dev/null || true' EXIT

    # ---- lapin-status: no input at all, fixed status line ----------------
    cat > "${_suid_work}/lapin-status.c" <<'STATUS_C'
/* lapin-status — Lapin Logistics health blip.
 * Ignores argc/argv/env and prints one fixed status line.
 */
#include <stdio.h>

int main(void) {
    puts("lapin-status: warehouse telemetry OK (all hutches nominal)");
    return 0;
}
STATUS_C

    # ---- lapin-greeter: argv[1] used ONLY via bounded, non-fmt copy ------
    cat > "${_suid_work}/lapin-greeter.c" <<'GREETER_C'
/* lapin-greeter — prints a friendly greeting.
 * Takes an optional argv[1] name, copied with a hard length cap into a
 * fixed buffer; the format string is the fixed literal "%s" and only
 * printable ASCII is kept. No system()/exec-family/popen.
 */
#include <stdio.h>
#include <stddef.h>
#include <ctype.h>

#define NAME_MAX_LEN 31

int main(int argc, char **argv) {
    char name[NAME_MAX_LEN + 1];
    size_t n = 0;

    if (argc < 2) {
        printf("%s\n", "Hello, fellow rabbit. Welcome to Lapin Logistics.");
        return 0;
    }

    /* Bounded copy of argv[1]: printable ASCII only, hard cap. */
    for (const char *p = argv[1]; *p && n < NAME_MAX_LEN; ++p) {
        unsigned char c = (unsigned char)*p;
        if (isprint(c) && c != '%') {
            name[n++] = (char)c;
        }
    }
    name[n] = '\0';

    /* Fixed "%s" format string. */
    printf("%s", "Hello, ");
    printf("%s", name);
    printf("%s", ". Welcome to Lapin Logistics.\n");
    return 0;
}
GREETER_C

    # ---- lapin-check: fixed subprocess, zero user input ------------------
    cat > "${_suid_work}/lapin-check.c" <<'CHECK_C'
/* lapin-check — runs a fixed health subprocess.
 * execs a hard-coded program (/bin/true) by absolute path with no
 * user-controlled path or arguments; ignores argv/env.
 */
#include <stdio.h>
#include <unistd.h>

int main(void) {
    fputs("lapin-check: running scheduled integrity probe...\n", stdout);
    fflush(stdout);
    /* Absolute path, fixed args, no environment-influenced lookup. */
    execl("/bin/true", "true", (char *)NULL);
    /* Only reached if /bin/true is missing. */
    fputs("lapin-check: probe completed.\n", stdout);
    return 0;
}
CHECK_C

    _build_suid lapin-status  "${_suid_work}/lapin-status.c"
    _build_suid lapin-greeter "${_suid_work}/lapin-greeter.c"
    _build_suid lapin-check   "${_suid_work}/lapin-check.c"

    rm -rf "$_suid_work" 2>/dev/null || true
    trap - EXIT
    unset _suid_work
fi

# ===========================================================================
# 4. pkexec / polkit — ASSURED PRESENT + CURRENT. We install/refresh the
#    current OS package (never an old build). We do NOT pin a version and
#    we do NOT downgrade — just assure presence.
# ===========================================================================
case "${LAPIN_DISTRO_FAMILY:-debian}" in
    debian) _POLKIT_PKG="policykit-1" ;;   # Debian/Ubuntu pre-22.10 name
    *)      _POLKIT_PKG="polkit" ;;        # rhel/arch/suse and Debian 22.10+
esac
log "13-decoys: assuring polkit/pkexec present + current via '${_POLKIT_PKG}'"
# ensure_pkg is dry-run safe (delegates through run); on Debian families where
# the package was renamed, fall back to the modern 'polkit' name if the legacy
# one is unavailable so the assurance still succeeds.
if ! ensure_pkg "$_POLKIT_PKG"; then
    warn "13-decoys: '${_POLKIT_PKG}' install failed — retrying with generic 'polkit'"
    ensure_pkg polkit || warn "13-decoys: polkit install failed; pkexec may already be present from base image"
fi

if is_dry_run; then
    log "[DRY-RUN] would verify pkexec is present and report its (patched) version"
else
    if command -v pkexec >/dev/null 2>&1; then
        _pkexec_path="$(command -v pkexec)"
        _pkexec_ver="$(pkexec --version 2>/dev/null | head -1 || true)"
        log "13-decoys: pkexec present at ${_pkexec_path} (${_pkexec_ver:-version unknown})"
        unset _pkexec_path _pkexec_ver
    else
        warn "13-decoys: pkexec not on PATH after polkit install (non-fatal; depends on base image/policy)"
    fi
fi

log "13-decoys: DONE — hutch (${_HUTCH_MB}MB), /opt/backup archives, 3 SUID utilities, pkexec assurance in place"
