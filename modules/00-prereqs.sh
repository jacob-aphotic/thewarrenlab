#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/00-prereqs.sh — Lapin Logistics — base packages + Python libs
# =============================================================================
# Installs base system packages and Python libraries required by asset
# generators. Must be run before any other module.
#
# Packages: curl wget git python3 python3-pip python3-venv unzip zip jq
#           build-essential python3-dev zlib1g-dev openssl
#           (python3-dev + zlib1g-dev are MANDATORY: pyminizip is source-only
#            on PyPI — no wheel — and its C extension #includes <Python.h> and
#            <zlib.h>; build-essential alone is insufficient. Missing these is
#            why the single batched pip install aborted on the first deploy.)
# Python:   reportlab pillow piexif flask gunicorn pyminizip python-docx
#           pikepdf  ← required by assets/gen-pdfs.py for XMP metadata
#
# DRY-RUN SAFE: all mutations go through run / ensure_pkg.
# IDEMPOTENT:   pkg managers no-op on already-installed packages;
#               pip --break-system-packages is re-runnable.
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

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
log "00-prereqs: installing base system packages"

ensure_pkg \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    unzip \
    zip \
    jq \
    build-essential \
    python3-dev \
    zlib1g-dev \
    openssl

log "00-prereqs: base packages done"

# ---------------------------------------------------------------------------
# 2. Python libraries (requires network; fail fast on error)
# ---------------------------------------------------------------------------
# Use --break-system-packages for Debian/Ubuntu 23+ PEP 668 enforcement.
# Other distros tolerate the flag or it is a no-op; pip ignores unknown flags
# only in older versions, so guard with a version-safe approach: just pass it
# unconditionally (pip ≥ 22.3 understands it; earlier versions error cleanly
# if the flag is unknown, but we target Ubuntu 22+/Debian 12+).

readonly _PY_LIBS="reportlab pillow piexif flask gunicorn pyminizip python-docx pikepdf"

log "00-prereqs: installing Python libraries via pip3 (requires network)"
log "00-prereqs: pip libs: ${_PY_LIBS}"

# We can't use the generic `run` here: it cannot capture pip's output, and on
# the first real deploy that masked the true failure (pyminizip's C build) as a
# misleading "network" error. So replicate run's dry-run + exec-log contract
# for this one command, but funnel pip's full stdout+stderr into the install
# log so any failure is self-diagnosing, and give an accurate advisory.
# shellcheck disable=SC2086  # word-split intentional: expands space-separated lib list
if is_dry_run; then
    log "[DRY-RUN] would: pip3 install --break-system-packages ${_PY_LIBS}"
else
    log "exec: pip3 install --break-system-packages ${_PY_LIBS}"
    if ! pip3 install --break-system-packages ${_PY_LIBS} >>"${LAPIN_LOG_FILE:-/dev/stderr}" 2>&1; then
        die "00-prereqs: pip3 install failed — see the pip output just above in ${LAPIN_LOG_FILE:-the log}." \
            "Most often a C-extension build dep is missing (pyminizip is source-only and needs python3-dev + zlib1g-dev, now in the package list — re-run install.sh)." \
            "If pip shows network/SSL/proxy errors instead, the VM lacks PyPI access; fix connectivity and retry."
    fi
fi

log "00-prereqs: Python libraries installed"
log "00-prereqs: DONE"
