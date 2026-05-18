#!/usr/bin/env bash
# shellcheck shell=bash
# =============================================================================
# modules/03-ftp.sh — Lapin Logistics — vsftpd FTP service
# =============================================================================
# Configures vsftpd with:
#   - Anonymous access (read-only) rooted at /srv/ftp/pub
#   - Local user access with chroot (peter's home is FTP-visible after auth)
#   - Banner string: "(vsFTPd 2.3.4)"
#
# vsftpd.conf notes:
#   allow_writeable_chroot=YES  — required on modern vsftpd when
#     chroot_local_user=YES and the chroot root (home dir) is writable by the
#     user; without it vsftpd refuses to start.
#   pam_service_name=vsftpd     — explicit; avoids distro-specific PAM
#     fallback surprises on RHEL/Fedora systems.
#   pasv_enable=YES / pasv_min_port / pasv_max_port — passive FTP for clients
#     behind NAT/firewall in lab environments.
#
# Populates /srv/ftp/pub with a deep corporate FTP tree (~12 dirs, >=4 levels)
# containing plausible mundane files requiring full recursive enumeration.
# Asset generators (gen-pdfs.py, gen-zip.py) are run into a staging dir then
# files are copied to their target subdirs.
#
# DRY-RUN SAFE: all mutations via run / ensure_* / is_dry_run-gated blocks.
#               Generators are skipped entirely in dry-run.
# IDEMPOTENT:   vsftpd.conf is authoritatively overwritten on every run.
#               All authored files are overwritten on every run (no -f guards).
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

# Derive the project root and assets path from BASH_SOURCE — never hardcode.
LAPIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LAPIN_ROOT
LAPIN_ASSETS="${LAPIN_ROOT}/assets"
readonly LAPIN_ASSETS

log "03-ftp: starting vsftpd setup"

# ---------------------------------------------------------------------------
# 1. Package
# ---------------------------------------------------------------------------
log "03-ftp: ensuring vsftpd package"
ensure_pkg vsftpd

# ---------------------------------------------------------------------------
# 2. Authoritative vsftpd.conf (OVERWRITE — never append)
# ---------------------------------------------------------------------------
log "03-ftp: writing authoritative /etc/vsftpd.conf"
if is_dry_run; then
    log "[DRY-RUN] would write /etc/vsftpd.conf"
else
    cat > /etc/vsftpd.conf <<'VSFTPD_CONF'
# ==========================================================================
# /etc/vsftpd.conf — Lapin Logistics — managed by configuration
# DO NOT EDIT MANUALLY — this file is overwritten by configuration management.
# ==========================================================================

# ---------------------------------------------------------------------------
# Anonymous access (read-only; rooted at /srv/ftp/pub)
# ---------------------------------------------------------------------------
anonymous_enable=YES
anon_root=/srv/ftp/pub
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# ---------------------------------------------------------------------------
# Local user access (chrooted to home dir)
# ---------------------------------------------------------------------------
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
# Required on modern vsftpd when the chroot root is writable by the user;
# without this vsftpd refuses to start (500 OOPS: vsftpd: refusing to run
# with writable root inside chroot()).
allow_writeable_chroot=YES

# ---------------------------------------------------------------------------
# Banner string
# ---------------------------------------------------------------------------
ftpd_banner=(vsFTPd 2.3.4)

# ---------------------------------------------------------------------------
# Passive mode (required for clients behind NAT in lab environments)
# ---------------------------------------------------------------------------
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# ---------------------------------------------------------------------------
# PAM / logging / misc
# ---------------------------------------------------------------------------
pam_service_name=vsftpd
xferlog_enable=YES
xferlog_std_format=YES
xferlog_file=/var/log/vsftpd.log
connect_from_port_20=YES
listen=YES
listen_ipv6=NO
tcp_wrappers=NO
VSFTPD_CONF
    log "03-ftp: /etc/vsftpd.conf written"
fi

# ---------------------------------------------------------------------------
# 3. FTP root directories
# ---------------------------------------------------------------------------
log "03-ftp: ensuring /srv/ftp and /srv/ftp/pub (root:root 755)"
# The anon chroot ROOT must be root-owned and NOT writable by the 'ftp' user
# that vsftpd chroots anonymous sessions into — otherwise vsftpd aborts with
# "500 OOPS: vsftpd: refusing to run with writable root inside chroot()".
# (allow_writeable_chroot=YES in vsftpd.conf applies to the LOCAL-user path
# only: chroot_local_user=YES chroots e.g. peter into his writable home.)
# ensure_dir re-applies ownership unconditionally, self-healing any prior run
# that left /srv/ftp owned as ftp:ftp.
ensure_dir /srv/ftp     755 root:root
ensure_dir /srv/ftp/pub 755 root:root

# ---------------------------------------------------------------------------
# 4. Deep corporate FTP tree under /srv/ftp/pub
#    Layout (12 subdirs, up to 4 levels deep):
#      pub/public-notices/
#      pub/hr/
#      pub/hr/onboarding/
#      pub/hr/policies/
#      pub/hr/benefits/
#      pub/it/
#      pub/it/guides/
#      pub/it/archive/
#      pub/logistics/
#      pub/logistics/routes/
#      pub/logistics/inventory/2023/
#      pub/logistics/inventory/2024/
#      pub/logistics/suppliers/
#      pub/finance/archive/
#      pub/misc/
# ---------------------------------------------------------------------------
log "03-ftp: building /srv/ftp/pub subdirectory tree"

_PUB=/srv/ftp/pub

_subdirs=(
    "${_PUB}/public-notices"
    "${_PUB}/hr"
    "${_PUB}/hr/onboarding"
    "${_PUB}/hr/policies"
    "${_PUB}/hr/benefits"
    "${_PUB}/it"
    "${_PUB}/it/guides"
    "${_PUB}/it/archive"
    "${_PUB}/logistics"
    "${_PUB}/logistics/routes"
    "${_PUB}/logistics/inventory"
    "${_PUB}/logistics/inventory/2023"
    "${_PUB}/logistics/inventory/2024"
    "${_PUB}/logistics/suppliers"
    "${_PUB}/finance"
    "${_PUB}/finance/archive"
    "${_PUB}/misc"
)

if is_dry_run; then
    log "[DRY-RUN] would mkdir -p tree under /srv/ftp/pub:"
    for _d in "${_subdirs[@]}"; do
        log "[DRY-RUN]   ${_d}"
    done
else
    for _d in "${_subdirs[@]}"; do
        run mkdir -p "${_d}"
        run chmod 755 "${_d}"
        run chown root:root "${_d}"
    done
fi
unset _d _subdirs

# ---------------------------------------------------------------------------
# 5. Authored text/CSV files — generated programmatically, no creds, no hints
#    Each block: dry-run logs intent; real-run writes + chowns.
#    Owner: root:root (consistent with dir ownership; anon read-only).
# ---------------------------------------------------------------------------

# Helper: set permissions on a file placed in /srv/ftp/pub tree
# Usage: _ftp_perms <path>
_ftp_perms() { run chmod 644 "$1"; run chown root:root "$1"; }

log "03-ftp: writing authored filler files"

# --- pub/public-notices/ ---------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/public-notices/notice_server_maintenance_2024.txt"
    log "[DRY-RUN] would write ${_PUB}/public-notices/notice_holiday_schedule_2024.txt"
    log "[DRY-RUN] would write ${_PUB}/public-notices/README.txt"
else
    cat > "${_PUB}/public-notices/notice_server_maintenance_2024.txt" <<'EOF'
LAPIN LOGISTICS — PLANNED MAINTENANCE NOTICE
Issued: 2024-01-08

Scheduled maintenance windows — Q1 2024:

  Sat 2024-01-20 22:00–02:00 CET  File share / NAS (WH-A1, WH-A2)
  Sat 2024-02-03 22:00–02:00 CET  ERP upgrade (read-only mode during window)
  Sat 2024-02-17 22:00–01:00 CET  Network switch replacement (WH-B1 segment)

During each window the affected services will be unavailable.
Please plan data exports accordingly and contact it-support@lapinlogistics.local
with questions.

-- IT Infrastructure Team
EOF
    _ftp_perms "${_PUB}/public-notices/notice_server_maintenance_2024.txt"

    cat > "${_PUB}/public-notices/notice_holiday_schedule_2024.txt" <<'EOF'
LAPIN LOGISTICS — OFFICE CLOSURE SCHEDULE 2024

The following dates are company-wide closures (EU headquarters + all warehouses):

  Mon 2024-01-01   New Year's Day
  Fri 2024-03-29   Good Friday
  Mon 2024-04-01   Easter Monday
  Wed 2024-05-01   Labour Day
  Thu 2024-05-09   Ascension Day
  Mon 2024-05-20   Whit Monday
  Thu 2024-10-03   Unity Day (DE sites only)
  Wed 2024-12-25   Christmas Day
  Thu 2024-12-26   Boxing Day

Warehouse emergency contacts and on-call rota are posted on the intranet.

-- HR Department
EOF
    _ftp_perms "${_PUB}/public-notices/notice_holiday_schedule_2024.txt"

    cat > "${_PUB}/public-notices/README.txt" <<'EOF'
Public Notices — Lapin Logistics FTP

This folder contains company-wide announcements, maintenance windows,
and schedule notices. Files are updated by the IT and HR departments.
For the most recent intranet notices, log in to the staff portal.
EOF
    _ftp_perms "${_PUB}/public-notices/README.txt"
fi

# --- pub/hr/onboarding/ ----------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/hr/onboarding/welcome_letter_template.txt"
    log "[DRY-RUN] would write ${_PUB}/hr/onboarding/new_starter_checklist.txt"
    log "[DRY-RUN] would copy IT_orientation.pdf -> ${_PUB}/hr/onboarding/IT_orientation.pdf"
else
    cat > "${_PUB}/hr/onboarding/welcome_letter_template.txt" <<'EOF'
LAPIN LOGISTICS — NEW STARTER WELCOME LETTER (template)

Dear [NAME],

Welcome to Lapin Logistics. We are glad to have you on board.

Your first day is [START DATE]. Please report to reception at [SITE ADDRESS]
by [TIME]. Bring two forms of ID for the HR records check.

Your line manager [MANAGER NAME] will meet you and walk you through your first
week schedule. A laptop and access credentials will be arranged by IT on or
before your start date.

We look forward to working with you.

Kind regards,
HR Department
Lapin Logistics
hr@lapinlogistics.local
EOF
    _ftp_perms "${_PUB}/hr/onboarding/welcome_letter_template.txt"

    cat > "${_PUB}/hr/onboarding/new_starter_checklist.txt" <<'EOF'
NEW STARTER CHECKLIST — HR / IT JOINT

Before first day:
  [ ] Contract signed and returned
  [ ] Right-to-work documents verified
  [ ] Laptop ordered via IT ticket
  [ ] Building access card requested (Facilities)
  [ ] Email account created by IT
  [ ] Added to relevant mailing lists

Day one:
  [ ] ID check at reception
  [ ] Sign acceptable-use policy
  [ ] Collect access card
  [ ] IT orientation session (see IT_orientation.pdf)
  [ ] Introduction to team and line manager
  [ ] Health & safety induction (Facilities, ~30 min)

First week:
  [ ] Complete mandatory e-learning modules (GDPR, Information Security)
  [ ] Set up VPN client (instructions in IT orientation handbook)
  [ ] Request access to required shared drives via IT helpdesk
  [ ] Meet with payroll to confirm bank details

Contact hr@lapinlogistics.local for questions.
EOF
    _ftp_perms "${_PUB}/hr/onboarding/new_starter_checklist.txt"
fi

# --- pub/hr/policies/ ------------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/hr/policies/acceptable_use_policy_v3.txt"
    log "[DRY-RUN] would write ${_PUB}/hr/policies/remote_work_policy_2023.txt"
    log "[DRY-RUN] would write ${_PUB}/hr/policies/data_retention_summary.txt"
else
    cat > "${_PUB}/hr/policies/acceptable_use_policy_v3.txt" <<'EOF'
ACCEPTABLE USE POLICY — v3.0 — Effective 2023-09-01
Lapin Logistics GmbH

1. SCOPE
   This policy applies to all staff, contractors, and third-party users who
   access Lapin Logistics IT systems, networks, or data.

2. PERMITTED USE
   IT resources are provided for legitimate business purposes. Limited
   personal use that does not consume significant resources is tolerated.

3. PROHIBITED ACTIVITIES
   - Unauthorised access to systems or data
   - Installation of unlicensed software
   - Sharing credentials with colleagues
   - Transmission of confidential data via unencrypted channels
   - Use of company systems for personal commercial activities

4. MONITORING
   All network activity and system access is logged. Users have no expectation
   of privacy on company systems.

5. ENFORCEMENT
   Violations may result in disciplinary action up to and including dismissal.
   Criminal activity will be reported to the relevant authorities.

Approved by: Chief Information Security Officer
Review date: 2024-09-01
EOF
    _ftp_perms "${_PUB}/hr/policies/acceptable_use_policy_v3.txt"

    cat > "${_PUB}/hr/policies/remote_work_policy_2023.txt" <<'EOF'
REMOTE WORK POLICY — 2023 Edition
Lapin Logistics GmbH

Eligibility: Roles deemed suitable for remote work by line manager approval.
Frequency: Up to 3 days/week remote; at least 2 days/week on-site.

Requirements:
  - Approved company laptop or BYOD enrolled in MDM
  - VPN connected for all access to internal systems
  - Secure, private workspace — no public Wi-Fi for sensitive tasks
  - Availability during core hours 09:00–15:00 CET

Equipment:
  Standard remote kit (monitor, keyboard, headset) available via Facilities.
  Submit request via the IT helpdesk with line manager approval attached.

Data handling:
  No company data may be stored on personal devices or unencrypted media.
  Cloud storage must use the approved company SharePoint only.

Contact hr@lapinlogistics.local with questions.
EOF
    _ftp_perms "${_PUB}/hr/policies/remote_work_policy_2023.txt"

    cat > "${_PUB}/hr/policies/data_retention_summary.txt" <<'EOF'
DATA RETENTION SCHEDULE SUMMARY — Lapin Logistics GmbH
Last reviewed: 2023-11

Category                    Retention Period   Storage Location
-----------------------------------------------------------------
Employee HR files           7 years            HR SharePoint (EU)
Payroll records             7 years            Finance ERP
Customer contracts          10 years           Legal SharePoint
Supplier invoices           7 years            Finance ERP
Logistics route logs        3 years            WH NAS + offsite
Quality control records     5 years            QA SharePoint
IT access logs              12 months          SIEM
Email (general)             2 years            Exchange Online
Email (legal hold)          Indefinite         Compliance archive

Full schedule: see DRP-2023-11 on the intranet document library.
Contact legal@lapinlogistics.local for retention queries.
EOF
    _ftp_perms "${_PUB}/hr/policies/data_retention_summary.txt"
fi

# --- pub/hr/benefits/ ------------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/hr/benefits/benefits_overview_2024.txt"
else
    cat > "${_PUB}/hr/benefits/benefits_overview_2024.txt" <<'EOF'
EMPLOYEE BENEFITS OVERVIEW — 2024
Lapin Logistics GmbH

PENSION
  Company contributes 5% of gross salary to the group pension scheme.
  Employee minimum contribution: 3%. Enrol via HR portal within 30 days.

HEALTH
  Private health top-up scheme available; premium deducted monthly pre-tax.
  Optical and dental riders available at additional cost.
  Contact hr@lapinlogistics.local to enrol.

LEAVE
  Annual leave: 28 days (inclusive of public holidays for DE/PL/HU sites).
  Sick leave: follow local statutory provision + company top-up to 100% for
    first 10 days/year (requires medical certificate from day 1).
  Parental leave: per applicable national legislation.

TRAVEL
  Rail/season ticket loan scheme: apply via payroll by the 15th of the month.
  EV salary sacrifice scheme: open to permanent staff over 12 months service.

TRAINING
  Annual learning budget: EUR 800 per employee. Submit requests via manager.
  Language classes (DE, EN, PL) available at company cost.

Questions: hr@lapinlogistics.local | ext. 104
EOF
    _ftp_perms "${_PUB}/hr/benefits/benefits_overview_2024.txt"
fi

# --- pub/it/guides/ --------------------------------------------------------
# IT_orientation.pdf placed here by generator block (section 7 below).

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/it/guides/vpn_setup_guide.txt"
    log "[DRY-RUN] would write ${_PUB}/it/guides/shared_drive_mapping.txt"
    log "[DRY-RUN] would write ${_PUB}/it/guides/printer_setup_wh_a1.txt"
else
    cat > "${_PUB}/it/guides/vpn_setup_guide.txt" <<'EOF'
VPN CLIENT SETUP GUIDE — Lapin Logistics
Version 2.1 | Updated 2023-10

SUPPORTED CLIENTS: OpenVPN 2.6+, Tunnelblick (macOS), OpenVPN Connect (Win/iOS/Android)

STEP 1: Download the VPN client package from the IT helpdesk portal.
STEP 2: Import the configuration profile (.ovpn) attached to your onboarding
         ticket. Do not share this profile — it is user-specific.
STEP 3: Authenticate with your domain credentials (username@lapinlogistics.local).
STEP 4: On first connect, accept the server certificate presented and verify
         the fingerprint with IT if prompted.

TROUBLESHOOTING:
  - Cannot connect: check that your machine clock is within 60 seconds of NTP.
  - Certificate error: your profile may have expired; open a helpdesk ticket.
  - Split-tunnel note: only lapinlogistics.local traffic is routed via VPN by
    default; internet browsing uses your local connection.

SUPPORT: it-support@lapinlogistics.local | ext. 101 | Mon–Fri 08:00–18:00 CET
EOF
    _ftp_perms "${_PUB}/it/guides/vpn_setup_guide.txt"

    cat > "${_PUB}/it/guides/shared_drive_mapping.txt" <<'EOF'
SHARED DRIVE MAPPING REFERENCE — Lapin Logistics IT
Last updated: 2024-01

Drive Letter  UNC Path                           Description
-----------------------------------------------------------------------
H:            \\fileserver01\users\%username%    Personal home drive
L:            \\fileserver01\logistics           Logistics shared
Q:            \\fileserver02\quality             QA / quality records
F:            \\fileserver02\finance             Finance (restricted)
S:            \\fileserver01\software            IT software repository
T:            \\fileserver01\templates           Document templates

Drives are mapped automatically by group policy at logon. If a drive is
missing, log off and back on, then contact it-support@lapinlogistics.local.

Note: access to F: (Finance) requires a separate access request approved
by the Finance Director. Submit via the IT helpdesk.
EOF
    _ftp_perms "${_PUB}/it/guides/shared_drive_mapping.txt"

    cat > "${_PUB}/it/guides/printer_setup_wh_a1.txt" <<'EOF'
PRINTER SETUP — WAREHOUSE A1 (WH-A1)
Updated: 2023-08

DEVICE: Lapin-Print-WH-A1-01
IP:     10.20.1.50
Queue:  \\printserver01\wha1-main

DRIVER: HP Universal Print Driver (PCL6) — available on \\fileserver01\software\printers

INSTALLATION (Windows):
  1. Open Settings > Devices > Printers & Scanners > Add a printer.
  2. Select "The printer I want isn't listed."
  3. Choose "Select a shared printer by name" and enter the queue path above.
  4. Windows will install the driver automatically from the print server.

LABEL PRINTER (Zebra ZT411):
  IP: 10.20.1.51 — use Zebra Setup Utilities (available from IT).

SUPPORT: it-support@lapinlogistics.local | ext. 101
EOF
    _ftp_perms "${_PUB}/it/guides/printer_setup_wh_a1.txt"
fi

# --- pub/it/archive/ -------------------------------------------------------
# archived_emails.zip placed here by generator block (section 7 below).

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/it/archive/README.txt"
    log "[DRY-RUN] would write ${_PUB}/it/archive/it_changelog_2022.txt"
    log "[DRY-RUN] would write ${_PUB}/it/archive/software_inventory_2022.txt"
else
    cat > "${_PUB}/it/archive/README.txt" <<'EOF'
IT Archive — Lapin Logistics

This directory contains archived IT documentation and logs from previous years.
Files here are retained for reference and audit purposes.
For current documentation, see pub/it/guides/.

Contact it-support@lapinlogistics.local with questions.
EOF
    _ftp_perms "${_PUB}/it/archive/README.txt"

    cat > "${_PUB}/it/archive/it_changelog_2022.txt" <<'EOF'
IT INFRASTRUCTURE CHANGELOG — 2022
Lapin Logistics GmbH

2022-01-12  Upgraded fileserver01 to Server 2022. Migration window 22:00–02:00.
2022-02-03  Deployed MDM (Microsoft Intune) for all company-issued laptops.
2022-03-17  Replaced WH-B1 network switches (EOL kit). 4-hour outage.
2022-04-28  MFA enforced on all external-facing services (VPN, webmail).
2022-06-09  SharePoint Online migration completed (EU datacenter region).
2022-07-14  New SIEM platform deployed; log retention increased to 12 months.
2022-09-01  AUP v3.0 published and distributed to all staff.
2022-10-19  WH-D3 extension opened; network installed and tested.
2022-11-30  Exchange Server decommissioned; fully migrated to Exchange Online.
2022-12-15  Annual DR test completed; RTO target met within tolerance.
EOF
    _ftp_perms "${_PUB}/it/archive/it_changelog_2022.txt"

    cat > "${_PUB}/it/archive/software_inventory_2022.txt" <<'EOF'
APPROVED SOFTWARE INVENTORY — 2022 AUDIT SNAPSHOT
Lapin Logistics GmbH | IT Asset Management

Application              Version    Licence Type     Seat Count   Renewal
-----------------------------------------------------------------------
Microsoft 365 E3         Current    Subscription     210          2023-08
Adobe Acrobat DC         2022       Per-user         45           2023-03
AutoCAD LT               2022       Per-user         8            2023-06
SAP ERP (ECC 6.0)        EHP8       Enterprise       1 (server)   2025-01
OpenVPN Access Server    2.11       Subscription     250 concurrent 2023-09
Zebra ZPL Designer       3.1        Perpetual        12           N/A
Veeam Backup             12.0       Subscription     —            2023-11
Sophos Endpoint          Current    Subscription     210          2023-08

This snapshot was generated for the 2022 software audit. For the current
inventory, contact it-support@lapinlogistics.local.
EOF
    _ftp_perms "${_PUB}/it/archive/software_inventory_2022.txt"
fi

# --- pub/logistics/routes/ -------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/logistics/routes/route_master_q3_2023.txt"
    log "[DRY-RUN] would write ${_PUB}/logistics/routes/route_master_q4_2023.txt"
    log "[DRY-RUN] would write ${_PUB}/logistics/routes/driver_roster_2023.txt"
else
    cat > "${_PUB}/logistics/routes/route_master_q3_2023.txt" <<'EOF'
ROUTE MASTER SCHEDULE — Q3 2023 (Jul–Sep)
Lapin Logistics GmbH

Route  Origin          Destination     Frequency  Carrier              Distance_km
------  --------------  --------------  ---------  -------------------  -----------
R-001   WH-A1 (Berlin)  Hamburg DC      Mon/Thu    Baltic Transit GmbH  290
R-002   WH-A2 (Berlin)  Dresden RC      Tue/Fri    IntraLog DE          200
R-003   WH-B1 (Warsaw)  Poznan Hub      Daily      CargoFast PL         310
R-004   WH-B2 (Warsaw)  Gdańsk Port     Wed/Sat    Baltic Transit GmbH  340
R-005   WH-C1 (Vienna)  Budapest DC     Mon/Fri    DanubeFreight HU     250
R-006   WH-D3 (Lyon)    Paris CDG WH    Tue/Thu    TerraRoute FR        470

All routes subject to change. Updated schedules posted by close of business
on the last Friday of the preceding month. Contact logistics@lapinlogistics.local.
EOF
    _ftp_perms "${_PUB}/logistics/routes/route_master_q3_2023.txt"

    cat > "${_PUB}/logistics/routes/route_master_q4_2023.txt" <<'EOF'
ROUTE MASTER SCHEDULE — Q4 2023 (Oct–Dec)
Lapin Logistics GmbH

Route  Origin          Destination     Frequency  Carrier              Distance_km
------  --------------  --------------  ---------  -------------------  -----------
R-001   WH-A1 (Berlin)  Hamburg DC      Mon/Thu    Baltic Transit GmbH  290
R-002   WH-A2 (Berlin)  Dresden RC      Mon/Wed/Fri IntraLog DE         200
R-003   WH-B1 (Warsaw)  Poznan Hub      Daily      CargoFast PL         310
R-004   WH-B2 (Warsaw)  Gdańsk Port     Tue/Fri    Baltic Transit GmbH  340
R-005   WH-C1 (Vienna)  Budapest DC     Mon/Wed/Fri DanubeFreight HU    250
R-006   WH-D3 (Lyon)    Paris CDG WH    Mon/Thu    TerraRoute FR        470
R-007   WH-A1 (Berlin)  Wrocław Hub     Fri only   CargoFast PL         390

Note: R-007 added Q4 to handle seasonal volume increase. Review in January.
EOF
    _ftp_perms "${_PUB}/logistics/routes/route_master_q4_2023.txt"

    cat > "${_PUB}/logistics/routes/driver_roster_2023.txt" <<'EOF'
DRIVER ROSTER — 2023 (INTERNAL REFERENCE)
Lapin Logistics GmbH — Logistics Coordination

ID      Name               Site      Routes       Licence  Exp
------  -----------------  --------  -----------  -------  ----------
DRV-01  K. Malinowski      WH-B1     R-003, R-004 C+E      2026-03-14
DRV-02  A. Hoffmann        WH-A1     R-001, R-007 C+E      2025-11-09
DRV-03  M. Dubois          WH-D3     R-006        C        2027-01-22
DRV-04  B. Németh          WH-C1     R-005        C+E      2025-08-30
DRV-05  P. Kowalczyk       WH-B2     R-004        C+E      2026-06-17
DRV-06  S. Braun           WH-A2     R-002        C        2025-12-03
DRV-07  L. Fournier        WH-D3     R-006        C+E      2026-09-11
DRV-08  T. Varga           WH-C1     R-005        C        2027-04-05

Contact logistics@lapinlogistics.local to update roster entries.
Licence expiry checks run monthly by the Logistics Coordinator.
EOF
    _ftp_perms "${_PUB}/logistics/routes/driver_roster_2023.txt"
fi

# --- pub/logistics/inventory/2023/ -----------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would generate ${_PUB}/logistics/inventory/2023/carrot_inventory_q3_2023.csv (~200 rows)"
    log "[DRY-RUN] would generate ${_PUB}/logistics/inventory/2023/carrot_inventory_q4_2023.csv (~200 rows)"
    log "[DRY-RUN] would write ${_PUB}/logistics/inventory/2023/inventory_notes_q4_2023.txt"
else
    {
        printf 'SKU,Product,Variety,Weight_kg,Quantity,Unit_Price_EUR,Warehouse,Lot,Expiry,Status\n'
        _varieties=("Nantes" "Chantenay" "Imperator" "Danvers" "Bolero" "Bangor" "Nairobi" "Maestro" "Yellowstone" "Purple Haze")
        _warehouses=("WH-A1" "WH-A2" "WH-B1" "WH-B2" "WH-C1" "WH-D3")
        _statuses=("In Stock" "In Stock" "In Stock" "Reserved" "In Transit" "Quarantine")
        for i in $(seq 1 200); do
            _sku="LL-Q3-$(printf '%04d' "$i")"
            _variety="${_varieties[$((i % ${#_varieties[@]}))]}"
            _weight=$(awk "BEGIN{printf \"%.2f\", 0.5 + ($i % 25) * 0.4}")
            _qty=$(( (i * 17 + 83) % 950 + 50 ))
            _price=$(awk "BEGIN{printf \"%.2f\", 0.80 + ($i % 20) * 0.07}")
            _wh="${_warehouses[$((i % ${#_warehouses[@]}))]}"
            _lot="LOT-2023-$(printf '%05d' "$((i * 3 + 1000))")"
            _month=$(printf '%02d' "$(( (i % 3) + 7 ))")
            _expiry="2023-${_month}-$(printf '%02d' "$(( (i % 28) + 1 ))")"
            _status="${_statuses[$((i % ${#_statuses[@]}))]}"
            printf '%s,%s,%s,%s,%d,%s,%s,%s,%s,%s\n' \
                "$_sku" "Carrot" "$_variety" "$_weight" "$_qty" "$_price" \
                "$_wh" "$_lot" "$_expiry" "$_status"
        done
        unset _varieties _warehouses _statuses i _sku _variety _weight _qty _price _wh _lot _month _expiry _status
    } > "${_PUB}/logistics/inventory/2023/carrot_inventory_q3_2023.csv"
    _ftp_perms "${_PUB}/logistics/inventory/2023/carrot_inventory_q3_2023.csv"
    log "03-ftp: carrot_inventory_q3_2023.csv written (200 rows)"

    {
        printf 'SKU,Product,Variety,Weight_kg,Quantity,Unit_Price_EUR,Warehouse,Lot,Expiry,Status\n'
        _varieties=("Nantes" "Chantenay" "Imperator" "Danvers" "Bolero" "Bangor" "Nairobi" "Maestro" "Yellowstone" "Purple Haze")
        _warehouses=("WH-A1" "WH-A2" "WH-B1" "WH-B2" "WH-C1" "WH-D3")
        _statuses=("In Stock" "In Stock" "In Stock" "Reserved" "In Transit" "Quarantine")
        for i in $(seq 1 200); do
            _sku="LL-Q4-$(printf '%04d' "$i")"
            _variety="${_varieties[$((i % ${#_varieties[@]}))]}"
            _weight=$(awk "BEGIN{printf \"%.2f\", 0.5 + ($i % 25) * 0.4}")
            _qty=$(( (i * 19 + 71) % 950 + 50 ))
            _price=$(awk "BEGIN{printf \"%.2f\", 0.82 + ($i % 20) * 0.07}")
            _wh="${_warehouses[$((i % ${#_warehouses[@]}))]}"
            _lot="LOT-2023-$(printf '%05d' "$((i * 3 + 4000))")"
            _month=$(printf '%02d' "$(( (i % 3) + 10 ))")
            _expiry="2024-${_month}-$(printf '%02d' "$(( (i % 28) + 1 ))")"
            _status="${_statuses[$((i % ${#_statuses[@]}))]}"
            printf '%s,%s,%s,%s,%d,%s,%s,%s,%s,%s\n' \
                "$_sku" "Carrot" "$_variety" "$_weight" "$_qty" "$_price" \
                "$_wh" "$_lot" "$_expiry" "$_status"
        done
        unset _varieties _warehouses _statuses i _sku _variety _weight _qty _price _wh _lot _month _expiry _status
    } > "${_PUB}/logistics/inventory/2023/carrot_inventory_q4_2023.csv"
    _ftp_perms "${_PUB}/logistics/inventory/2023/carrot_inventory_q4_2023.csv"
    log "03-ftp: carrot_inventory_q4_2023.csv written (200 rows)"

    cat > "${_PUB}/logistics/inventory/2023/inventory_notes_q4_2023.txt" <<'EOF'
INVENTORY NOTES — Q4 2023
Lapin Logistics GmbH — Quality & Logistics

Reconciliation completed 2024-01-05. Key points:

- Nantes variety: 3 lots quarantined at WH-B1 (temperature excursion during
  transit from Warsaw; root cause under review by QA).
- Yellowstone variety: lower-than-forecast volume from supplier Agro-Carrot;
  Q1 2024 order increased by 15% to compensate.
- WH-D3 (Lyon): shelf capacity reached 92% peak in December; Facilities
  submitted expansion request (ref FAC-2024-0003).
- End-of-year write-off: 1.2 tonnes Chantenay (grading rejection). Disposal
  confirmed by warehouse lead 2024-01-03.

Next full count: March 2024 (end of Q1).
Contact logistics@lapinlogistics.local with queries.
EOF
    _ftp_perms "${_PUB}/logistics/inventory/2023/inventory_notes_q4_2023.txt"
fi

# --- pub/logistics/inventory/2024/ -----------------------------------------
# carrot_quality_standards.pdf placed here by generator block (section 7).

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/logistics/inventory/2024/inventory_notes_q1_2024.txt"
    log "[DRY-RUN] would copy carrot_quality_standards.pdf -> ${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"
else
    cat > "${_PUB}/logistics/inventory/2024/inventory_notes_q1_2024.txt" <<'EOF'
INVENTORY NOTES — Q1 2024
Lapin Logistics GmbH — Quality & Logistics

Period: January–March 2024. Count completed 2024-04-03.

- Overall throughput up 8% vs Q1 2023. Volume increase attributed to new
  R-007 (Berlin–Wrocław) route operational from January.
- Bolero variety: premium batch from new grower (Feldmann Agrar GmbH, DE)
  performing well on grading; re-order authorised.
- WH-A2 refrigeration unit 3 replaced during Feb maintenance window.
  No stock losses incurred.
- Quarantine rate: 0.4% (below 1.0% target). Q2 forecast: maintain.

Next full count: June 2024 (end of Q2).
EOF
    _ftp_perms "${_PUB}/logistics/inventory/2024/inventory_notes_q1_2024.txt"
fi

# --- pub/logistics/suppliers/ ----------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/logistics/suppliers/supplier_directory_2024.txt"
    log "[DRY-RUN] would write ${_PUB}/logistics/suppliers/supplier_onboarding_checklist.txt"
else
    cat > "${_PUB}/logistics/suppliers/supplier_directory_2024.txt" <<'EOF'
SUPPLIER DIRECTORY — 2024
Lapin Logistics GmbH — Procurement

ID       Name                       Country  Category       Primary Contact
-------  -------------------------  -------  -------------  ----------------------------------
SUP-001  Agro-Carrot sp. z o.o.    PL       Grower         M. Wiśniewski | +48 22 555 0142
SUP-002  Feldmann Agrar GmbH        DE       Grower         B. Feldmann   | +49 30 555 0331
SUP-003  Baltic Transit GmbH        DE       Freight        H. Schreiber  | +49 40 555 0288
SUP-004  CargoFast PL sp. z o.o.   PL       Freight        J. Kowal      | +48 61 555 0489
SUP-005  DanubeFreight Kft.         HU       Freight        T. Kovács     | +36 1 555 0521
SUP-006  TerraRoute SAS             FR       Freight        C. Bernard    | +33 4 555 0644
SUP-007  EuroFresh Clearance Kft.   HU       Customs        J. Varga      | +36 1 555 0417
SUP-008  IntraLog DE GmbH           DE       Freight        F. Klein      | +49 351 555 0190
SUP-009  Coldchain Packaging BV     NL       Packaging      A. de Vries   | +31 20 555 0712

For additions or changes contact procurement@lapinlogistics.local.
EOF
    _ftp_perms "${_PUB}/logistics/suppliers/supplier_directory_2024.txt"

    cat > "${_PUB}/logistics/suppliers/supplier_onboarding_checklist.txt" <<'EOF'
SUPPLIER ONBOARDING CHECKLIST — Lapin Logistics Procurement

Document collection:
  [ ] Signed Master Supply Agreement (MSA)
  [ ] Company registration certificate (translated if non-EU)
  [ ] VAT registration number confirmed
  [ ] Bank details on company letterhead (for payment setup in ERP)
  [ ] Current public liability insurance certificate

Quality & compliance:
  [ ] Food safety certification (BRC, IFS, or equivalent) — growers only
  [ ] Cold chain compliance statement — fresh produce and freight carriers
  [ ] GDPR data processing agreement signed
  [ ] Sanctions screening completed (Procurement Manager sign-off required)

System setup:
  [ ] Supplier portal account created
  [ ] EDI integration tested (if applicable)
  [ ] Contact details entered in supplier directory

Approval: requires sign-off from Procurement Manager + Finance Director.
Contact procurement@lapinlogistics.local to initiate onboarding.
EOF
    _ftp_perms "${_PUB}/logistics/suppliers/supplier_onboarding_checklist.txt"
fi

# --- pub/finance/archive/ --------------------------------------------------
# q3_logistics_review.pdf placed here by generator block (section 7).

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/finance/archive/meeting_notes_q3_review_2023.txt"
    log "[DRY-RUN] would write ${_PUB}/finance/archive/cost_centre_codes_2023.txt"
    log "[DRY-RUN] would copy q3_logistics_review.pdf -> ${_PUB}/finance/archive/q3_logistics_review.pdf"
else
    cat > "${_PUB}/finance/archive/meeting_notes_q3_review_2023.txt" <<'EOF'
MEETING NOTES — Q3 LOGISTICS COST REVIEW
Date: 2023-10-12 | Location: Conf. Room B (Berlin HQ) | Chair: R. Steinberg

Attendees: R. Steinberg (CFO), P. Holloway (Logistics Dir.), M. Pietrzak
(WH Ops), A. Fischer (Procurement), T. Müller (Finance Analyst)

AGENDA ITEMS

1. Q3 freight cost variance — actuals vs budget
   Actuals came in 6.2% over Q3 budget, driven primarily by diesel surcharges
   on R-003 and R-004 (Poland–Germany corridor). Baltic Transit notified; rate
   renegotiation scheduled for November.

2. Packaging material costs
   Coldchain Packaging BV invoice for Sep 2023 is under query (line item
   discrepancy on insulated liner quantities). A. Fischer to resolve by 20 Oct.

3. WH-D3 Lyon expansion feasibility
   Facilities quotation received (EUR 280k). Decision deferred to Q4 board.

4. Q4 volume forecast
   Logistics Dir. projects 12–15% volume increase for Nov–Dec (seasonal peak).
   Carrier capacity pre-booked for R-001, R-003, R-006. R-007 added.

ACTION ITEMS
  AF  Resolve Coldchain invoice query     2023-10-20
  RS  Prepare board pack for WH-D3 capex 2023-11-01
  PH  Confirm Q4 carrier capacity         2023-10-25
EOF
    _ftp_perms "${_PUB}/finance/archive/meeting_notes_q3_review_2023.txt"

    cat > "${_PUB}/finance/archive/cost_centre_codes_2023.txt" <<'EOF'
COST CENTRE REFERENCE — 2023
Lapin Logistics GmbH — Finance

Code    Description                      Owner
------  -------------------------------  -------------------------
CC-100  Corporate / HQ Overheads         CFO Office
CC-110  IT Infrastructure                IT Director
CC-120  HR & Recruitment                 HR Director
CC-200  Warehouse Operations — WH-A      WH-A Site Manager
CC-201  Warehouse Operations — WH-B      WH-B Site Manager
CC-202  Warehouse Operations — WH-C      WH-C Site Manager
CC-203  Warehouse Operations — WH-D      WH-D Site Manager
CC-300  Logistics & Transport            Logistics Director
CC-310  Freight — External Carriers      Procurement
CC-400  Sales & Account Management       Sales Director
CC-410  Marketing                        Marketing Manager
CC-500  Quality & Compliance             QA Manager
CC-600  Finance & Controlling            CFO Office

For coding queries contact finance@lapinlogistics.local | ext. 108.
Codes frozen for FY2023. FY2024 codes issued January 2024.
EOF
    _ftp_perms "${_PUB}/finance/archive/cost_centre_codes_2023.txt"
fi

# --- pub/misc/ -------------------------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/misc/office_floor_plan_notes.txt"
    log "[DRY-RUN] would write ${_PUB}/misc/contact_directory_partial_2023.txt"
else
    cat > "${_PUB}/misc/office_floor_plan_notes.txt" <<'EOF'
BERLIN HQ — FLOOR PLAN NOTES (for facilities use)
Lapin Logistics GmbH | 3rd Floor, Müllerstraße 42, 13353 Berlin

Room/Area             Use                         Capacity  Notes
--------------------  --------------------------  --------  -----------------------
3A-01                 Executive suite             —         Key access only
3A-02                 CFO office                  1         —
3A-03                 HR director office          1         —
3B-01                 Open plan — Finance         18        Desks D1–D18
3B-02                 Open plan — Logistics       22        Desks D19–D40
3B-03                 Open plan — IT              10        Desks D41–D50
3C-01                 Conference Room A           12        Booking via Outlook
3C-02                 Conference Room B           8         Booking via Outlook
3C-03                 Conference Room C           4         Booking via Outlook
3D-01                 IT server room              —         Restricted access
3D-02                 Comms / patch room          —         Restricted access
3E-01                 Kitchen / breakout          30        —
3E-02                 Print room                  —         2x MFP, shredder
3F-01                 Stairwell / fire exit        —         Keep clear

Evacuation assembly point: car park, south side of building (Müllerstraße).
Fire marshal: T. Müller (ext. 108), deputy: K. Braun (ext. 114).
EOF
    _ftp_perms "${_PUB}/misc/office_floor_plan_notes.txt"

    cat > "${_PUB}/misc/contact_directory_partial_2023.txt" <<'EOF'
STAFF CONTACT DIRECTORY — PARTIAL EXPORT (2023-Q3)
Lapin Logistics GmbH
(Full directory on intranet — this export covers HQ + WH leads only)

Name                 Title                       Ext   Email
-------------------  --------------------------  ----  ------------------------------------
R. Steinberg         Chief Financial Officer     102   r.steinberg@lapinlogistics.local
P. Holloway          Logistics Director          103   p.holloway@lapinlogistics.local
A. Fischer           Procurement Manager         105   a.fischer@lapinlogistics.local
T. Müller            Finance Analyst             108   t.muller@lapinlogistics.local
M. Pietrzak          WH Operations Manager       120   m.pietrzak@lapinlogistics.local
H. Schreiber (ext.)  Baltic Transit — Dispatch   —     h.schreiber@baltictransit.de
IT Helpdesk          —                           101   it-support@lapinlogistics.local
HR Department        —                           104   hr@lapinlogistics.local
Finance Department   —                           108   finance@lapinlogistics.local
Logistics Coord.     —                           110   logistics@lapinlogistics.local
EOF
    _ftp_perms "${_PUB}/misc/contact_directory_partial_2023.txt"
fi

# --- pub/ top-level welcome.txt --------------------------------------------

if is_dry_run; then
    log "[DRY-RUN] would write ${_PUB}/welcome.txt"
else
    cat > "${_PUB}/welcome.txt" <<'EOF'
Welcome to the Lapin Logistics FTP server.

This server is provided for authorised staff use only.
All access is logged and monitored in accordance with company policy.

For assistance contact it-support@lapinlogistics.local or call ext. 101.

-- The IT Department
   Lapin Logistics | "Delivering crisp produce since 1973."
EOF
    _ftp_perms "${_PUB}/welcome.txt"
    log "03-ftp: welcome.txt written"
fi

# ---------------------------------------------------------------------------
# 6. Peter's FTP home content
#    NOTE: /home/peter/.bash_history is NOT written here.
#    Ownership of that file belongs to modules/14-bash-history.sh.
# ---------------------------------------------------------------------------
log "03-ftp: writing peter's FTP home files"

if is_dry_run; then
    log "[DRY-RUN] would write /home/peter/notes.txt"
    log "[DRY-RUN] would write /home/peter/todo.txt"
else
    cat > /home/peter/notes.txt <<'PETER_NOTES'
Carry forward from last quarter:

- Mileage reimbursement for the Warsaw trip still outstanding (submitted Nov).
- Follow up with facilities on the WH-D3 shelf expansion timeline.
- Remind Thumper to send the updated inventory template before end of month.
- IT helpdesk ticket for shared drive quota — reference INC-2024-0041.
PETER_NOTES
    run chmod 640 /home/peter/notes.txt
    run chown peter:peter /home/peter/notes.txt
    log "03-ftp: /home/peter/notes.txt written"

    cat > /home/peter/todo.txt <<'PETER_TODO'
TODO (week of Q4 close):

[ ] Submit mileage reimbursement for November trip to Warsaw
[ ] Chase accounts payable re: invoice INV-2023-0847 (overdue 60 days)
[ ] Book room for all-hands Q4 review (check Roger's calendar first)
[ ] Renew VPN cert before it expires (Dec 14)
[ ] Update the warehouse contact list — Brigitte left in October
[ ] Ask IT about the shared drive quota warning
[ ] Print and sign updated NDA before end of month
[ ] Send Thumper the new inventory template
PETER_TODO
    run chmod 640 /home/peter/todo.txt
    run chown peter:peter /home/peter/todo.txt
    log "03-ftp: /home/peter/todo.txt written"
fi

# ---------------------------------------------------------------------------
# 7. Generator-produced files (PDFs and zip)
#    Generators run into a staging tmpdir; files are then copied to their
#    subdirs. In dry-run: skip generators entirely, emit intent logs only.
#    Pre-flight checks verify python3 and each generator script exist.
# ---------------------------------------------------------------------------
log "03-ftp: placing generator-produced assets"

if is_dry_run; then
    log "[DRY-RUN] would run: python3 ${LAPIN_ASSETS}/gen-pdfs.py --outdir <staging>"
    log "[DRY-RUN] would cp staging/IT_orientation.pdf -> ${_PUB}/hr/onboarding/IT_orientation.pdf"
    log "[DRY-RUN] would run: python3 ${LAPIN_ASSETS}/gen-zip.py --outdir <staging>"
    log "[DRY-RUN] would cp staging/archived_emails.zip -> ${_PUB}/it/archive/archived_emails.zip"
    log "[DRY-RUN] would cp staging/carrot_quality_standards.pdf -> ${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"
    log "[DRY-RUN] would cp staging/q3_logistics_review.pdf -> ${_PUB}/finance/archive/q3_logistics_review.pdf"
else
    command -v python3 >/dev/null 2>&1 \
        || die "03-ftp: python3 not found; run 00-prereqs.sh first"
    [[ -f "${LAPIN_ASSETS}/gen-pdfs.py" ]] \
        || die "03-ftp: missing asset generator ${LAPIN_ASSETS}/gen-pdfs.py"
    [[ -f "${LAPIN_ASSETS}/gen-zip.py" ]] \
        || die "03-ftp: missing asset generator ${LAPIN_ASSETS}/gen-zip.py"

    _staging="$(mktemp -d)"
    trap 'rm -rf -- "${_staging:-}"' EXIT

    log "03-ftp: staging dir: ${_staging}"

    log "03-ftp: running gen-pdfs.py"
    python3 "${LAPIN_ASSETS}/gen-pdfs.py" --outdir "${_staging}"

    log "03-ftp: running gen-zip.py"
    python3 "${LAPIN_ASSETS}/gen-zip.py" --outdir "${_staging}"

    # Verify all expected outputs were produced before copying.
    _expected_files=(
        IT_orientation.pdf
        carrot_quality_standards.pdf
        q3_logistics_review.pdf
        archived_emails.zip
    )
    for _ef in "${_expected_files[@]}"; do
        [[ -f "${_staging}/${_ef}" ]] \
            || die "03-ftp: generator did not produce expected file: ${_ef}"
    done
    unset _ef _expected_files

    # Copy each file to its designated location in the tree.
    run cp "${_staging}/IT_orientation.pdf"          "${_PUB}/hr/onboarding/IT_orientation.pdf"
    run chmod 644 "${_PUB}/hr/onboarding/IT_orientation.pdf"
    run chown root:root "${_PUB}/hr/onboarding/IT_orientation.pdf"
    log "03-ftp: installed ${_PUB}/hr/onboarding/IT_orientation.pdf"

    run cp "${_staging}/carrot_quality_standards.pdf" "${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"
    run chmod 644 "${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"
    run chown root:root "${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"
    log "03-ftp: installed ${_PUB}/logistics/inventory/2024/carrot_quality_standards.pdf"

    run cp "${_staging}/q3_logistics_review.pdf"      "${_PUB}/finance/archive/q3_logistics_review.pdf"
    run chmod 644 "${_PUB}/finance/archive/q3_logistics_review.pdf"
    run chown root:root "${_PUB}/finance/archive/q3_logistics_review.pdf"
    log "03-ftp: installed ${_PUB}/finance/archive/q3_logistics_review.pdf"

    run cp "${_staging}/archived_emails.zip"          "${_PUB}/it/archive/archived_emails.zip"
    run chmod 644 "${_PUB}/it/archive/archived_emails.zip"
    run chown root:root "${_PUB}/it/archive/archived_emails.zip"
    log "03-ftp: installed ${_PUB}/it/archive/archived_emails.zip"

    log "03-ftp: cleaning up staging dir ${_staging}"
    rm -rf -- "${_staging}"
    trap - EXIT
    unset _staging
fi

# ---------------------------------------------------------------------------
# 8. Additional user homes
#    harvey's home is left empty.
#    bugs, thumper, oswald each get a few ordinary files.
# ---------------------------------------------------------------------------
log "03-ftp: writing user home files (bugs, thumper, oswald; harvey stays empty)"

# ---- bugs ------------------------------------------------------------------
if is_dry_run; then
    log "[DRY-RUN] would write files in /home/bugs/"
else
    cat > /home/bugs/README.txt <<'BUGS_README'
Bugs Bunny — personal workspace notes (archived 2022-03)

This directory was last actively used before the Q1 2022 transition.
All active project files have been moved to the shared drive.
Contact it-support@lapinlogistics.local if you need access to archived content.
BUGS_README

    cat > /home/bugs/authorized_keys.old <<'BUGS_KEYS'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vQ2kLmNpR8fXtJzG4oWdKs3hUvYqBcPnM6xEaZLwT9iDrFgH0uSlCbNkQe5mXoJyRvWtAp2BdKfHcG8nPsYlMuVxZqEjTbOaIwDhRgKv1NcXeF4YmBsLo6PdUqHiAzStRjCwMvKnGxBpFoTeJlDyWsNuCeHQaZmXrGvKtIyPbEoLfMjVqWsNdBrHgKuCxYzAeTlFpJiMoRsVwXbDnKuFyGjZlPcQaHsNtRvWmEbKiTuYxCsDpOzAlGqMnBwFhJeLrXvKyIoPdSuQtZmHaNcEbRgWfVjCkDpYlOxTsUzAqBnMrGeHwJiKvLtFoPdXcQmRsYbNuEzAlWjVpKsItGfBhCeDnMoRqTuXbZlYaJiHgKwFvNpSdOcQeMrBtUzAxLyWjVkCpInGsDhFbNeRoTqMuXlZaJiHyKwGvNpSdOcQeMrBtUzAxLyWjVkCpInGsDhFb== bugs@lapin-wkstn-03.lapinlogistics.local
BUGS_KEYS

    cat > /home/bugs/.htpasswd.old <<'BUGS_HTPASSWD'
# Rotated Q1 2022 — passwords changed; this file retained for audit trail only
bugs:$2y$10$X8vNqKlPmRsToWdAbCeFgOzJhQyUiVxEkBnMrTsLoWdAbCeFgOzJhQ
jessica.rabbit:$2y$10$aB3cDeF4gHiJ5kLmN6oPqR7sT8uVwXyZ9aB3cDeF4gHiJ5kLmN6oP
admin:$apr1$hQ3zKlP/$XqRsTuVwXyZaB3cDeFgHiJkL.
BUGS_HTPASSWD

    cat > /home/bugs/notes_q1_2022.txt <<'BUGS_NOTES'
Q1 2022 Handover Notes

- Inventory DB migrated to new schema (see Roger's handover doc)
- Shared drive quota increased to 500GB by IT (ticket #4421)
- Contact: new warehouse lead is M. Pietrzak (m.pietrzak@lapinlogistics.local)
- Reminder: Q2 audit scheduled for April 14; prepare export reports by April 7
BUGS_NOTES

    for _f in README.txt authorized_keys.old .htpasswd.old notes_q1_2022.txt; do
        run chmod 640 "/home/bugs/${_f}"
        run chown bugs:bugs "/home/bugs/${_f}"
    done
    unset _f
    log "03-ftp: bugs home written (4 files)"
fi

# ---- thumper ---------------------------------------------------------------
if is_dry_run; then
    log "[DRY-RUN] would write files in /home/thumper/"
else
    cat > /home/thumper/README.txt <<'THUMPER_README'
Thumper — logistics coordinator workspace

Last active: 2023-08 (on leave; return TBD)
Active files moved to SharePoint (EU region); this local copy is stale.
THUMPER_README

    cat > /home/thumper/authorized_keys.old <<'THUMPER_KEYS'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDmK8pR2sXqLtNbZjYwUvFoGcHiDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBt== thumper@lapin-wkstn-07.lapinlogistics.local
THUMPER_KEYS

    cat > /home/thumper/.htpasswd.old <<'THUMPER_HTPASSWD'
# Q3 2022 rotation — old hashes; kept per policy (audit retention 12 months)
thumper:$2y$10$Pz9mNqRsTuVwXyZaB3cDeF4gHiJ5kLmN6oPqRsTuVwXyZaB3cDeF4g
warehouse-ro:$apr1$Kx2mNpQr/$YzAbCdEfGhIjKlMnOpQrSt.
THUMPER_HTPASSWD

    cat > /home/thumper/logistics_contacts_2022.txt <<'THUMPER_CONTACTS'
Logistics Partner Contacts (last updated 2022-09 — may be outdated)

Supplier: Agro-Carrot sp. z o.o.
  Contact: Marek Wiśniewski | +48 22 555 0142 | m.wisniewski@agrocarrot.pl
  Orders: orders-pl@agrocarrot.pl

Freight: Baltic Transit GmbH
  Contact: Helene Schreiber | +49 40 555 0288 | h.schreiber@baltictransit.de
  Dispatch: dispatch@baltictransit.de

Customs broker: EuroFresh Clearance
  Contact: Jozsef Varga | +36 1 555 0417 | j.varga@eurofreshclearance.hu
THUMPER_CONTACTS

    for _f in README.txt authorized_keys.old .htpasswd.old logistics_contacts_2022.txt; do
        run chmod 640 "/home/thumper/${_f}"
        run chown thumper:thumper "/home/thumper/${_f}"
    done
    unset _f
    log "03-ftp: thumper home written (4 files)"
fi

# ---- harvey — no extra files ----------------------------------------------
log "03-ftp: harvey home left empty"

# ---- oswald ----------------------------------------------------------------
if is_dry_run; then
    log "[DRY-RUN] would write files in /home/oswald/"
else
    cat > /home/oswald/README.txt <<'OSWALD_README'
Oswald Lucky — systems contractor workspace

Account status: suspended pending security review (see ticket SEC-2023-0031)
Files retained per data retention policy (90 days from suspension date).
Do not delete without approval from infosec@lapinlogistics.local.
OSWALD_README

    cat > /home/oswald/authorized_keys.old <<'OSWALD_KEYS'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCsXpLtNbZjYwUvFoGcHiDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXwJuVlCqKrHgDaEpMrTkBsNyWxVlCqJuOfIzAdGhPeRsYmBtKfNcXw== oswald@lapin-contractor-01.lapinlogistics.local
OSWALD_KEYS

    cat > /home/oswald/.htpasswd.old <<'OSWALD_HTPASSWD'
# Pre-suspension password file — INVALIDATED 2023-09-14
# Retained per SEC-2023-0031 evidence hold
oswald:$2y$10$uVwXyZaB3cDeF4gHiJ5kLmN6oPqRsTuVwXyZaB3cDeF4gHiJ5kLmN6
OSWALD_HTPASSWD

    cat > /home/oswald/suspension_notice.txt <<'OSWALD_NOTICE'
ACCOUNT SUSPENSION NOTICE — CONFIDENTIAL
Issued: 2023-09-14
User: oswald.lucky@lapinlogistics.local
Reason: Suspected policy violation (access outside authorised hours — under investigation)
Action: Account locked; home directory preserved for forensic review.
Contact: infosec@lapinlogistics.local | Reference: SEC-2023-0031
OSWALD_NOTICE

    for _f in README.txt authorized_keys.old .htpasswd.old suspension_notice.txt; do
        run chmod 640 "/home/oswald/${_f}"
        run chown oswald:oswald "/home/oswald/${_f}"
    done
    unset _f
    log "03-ftp: oswald home written (4 files)"
fi

# ---------------------------------------------------------------------------
# 9. Enable and start vsftpd
# ---------------------------------------------------------------------------
log "03-ftp: enabling and starting vsftpd service"
ensure_service_enabled vsftpd

log "03-ftp: DONE"
