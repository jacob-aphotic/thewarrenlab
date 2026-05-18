#!/usr/bin/env python3
"""
gen-zip.py — Lapin Logistics asset generator: password-protected ZIP files.

Usage:
    python3 assets/gen-zip.py --outdir <directory>

Outputs (always written; overwrites any existing files):
    archived_emails.zip     — 64-char random password
    lapin_backup_2024.zip   — 64-char random password

Each archive contains a few themed text files.

Exit codes:
    0  success
    1  argument/dependency error
"""

import argparse
import os
import secrets
import string
import sys
import tempfile


def parse_args():
    p = argparse.ArgumentParser(description="Generate Lapin Logistics password-protected ZIPs")
    p.add_argument("--outdir", required=True, help="Directory to write generated ZIP files into")
    return p.parse_args()


def random_password(length: int = 64) -> str:
    """Generate a cryptographically random password of the given length."""
    # Avoid chars that pyminizip can't handle in passwords on some platforms
    safe = string.ascii_letters + string.digits + "!@#$%^&*()-_=+[]{}"
    return "".join(secrets.choice(safe) for _ in range(length))


def write_temp_file(tmpdir: str, filename: str, content: str) -> str:
    path = os.path.join(tmpdir, filename)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    return path


def make_archived_emails_zip(outdir: str) -> str:
    """
    archived_emails.zip — archived internal email threads.
    """
    import pyminizip

    password = random_password(64)
    out_path = os.path.join(outdir, "archived_emails.zip")

    with tempfile.TemporaryDirectory() as tmpdir:
        files = []

        files.append(write_temp_file(tmpdir, "thread_q3_logistics.eml",
            "From: warehouse@lapinlogistics.local\n"
            "To: dispatch@lapinlogistics.local\n"
            "Subject: Q3 Shipment Delays\n"
            "Date: Mon, 14 Oct 2024 09:12:00 +0200\n"
            "\n"
            "Hi team,\n"
            "\n"
            "Just a heads-up that the Q3 carrot shipments from Lodz are running 2 days behind.\n"
            "Please update the client portal accordingly. The cold-chain certificates are attached.\n"
            "\n"
            "Regards,\n"
            "Warehouse Operations\n"
        ))

        files.append(write_temp_file(tmpdir, "reminder_password_reset.eml",
            "From: it-noreply@lapinlogistics.local\n"
            "To: all-staff@lapinlogistics.local\n"
            "Subject: [ACTION REQUIRED] Quarterly Password Reset\n"
            "Date: Tue, 01 Oct 2024 08:00:00 +0200\n"
            "\n"
            "This is an automated reminder from IT Security.\n"
            "\n"
            "Your password is due for quarterly rotation. Please log in to the HR portal\n"
            "and update your credentials before 15 October 2024.\n"
            "\n"
            "If you have difficulty resetting your password, contact ext. 555.\n"
            "\n"
            "-- IT Security\n"
        ))

        files.append(write_temp_file(tmpdir, "invoice_carrot_q3_2024.txt",
            "INVOICE #2024-Q3-0847\n"
            "Date: 2024-09-30\n"
            "Vendor: Eastern Carrot Growers Co-op\n"
            "PO Number: LLP-2024-0312\n"
            "\n"
            "Item                  Qty (kg)   Unit Price   Total\n"
            "Nantes Carrots        12,000      €0.42        €5,040.00\n"
            "Chantenay Carrots      8,500      €0.48        €4,080.00\n"
            "Imperator Carrots      5,200      €0.39        €2,028.00\n"
            "                                 SUBTOTAL:   €11,148.00\n"
            "                                 VAT (23%):   €2,564.04\n"
            "                                 TOTAL:      €13,712.04\n"
            "\n"
            "Payment due: 30 days. Bank details on file.\n"
        ))

        # pyminizip requires list of source files and list of prefixes (can be empty strings)
        prefixes = [""] * len(files)
        pyminizip.compress_multiple(files, prefixes, out_path, password, 5)

    # Password is not retained (callers do not need it)
    return out_path


def make_lapin_backup_zip(outdir: str) -> str:
    """
    lapin_backup_2024.zip — archived website/system backup.
    """
    import pyminizip

    password = random_password(64)
    out_path = os.path.join(outdir, "lapin_backup_2024.zip")

    with tempfile.TemporaryDirectory() as tmpdir:
        files = []

        files.append(write_temp_file(tmpdir, "db_schema.sql",
            "-- Lapin Logistics Database Schema Backup\n"
            "-- Exported: 2024-01-15 02:00:01\n"
            "-- Host: db01.lapinlogistics.local\n"
            "\n"
            "CREATE DATABASE IF NOT EXISTS `lapin_cms`;\n"
            "USE `lapin_cms`;\n"
            "\n"
            "CREATE TABLE `products` (\n"
            "  `id` int(11) NOT NULL AUTO_INCREMENT,\n"
            "  `name` varchar(255) NOT NULL,\n"
            "  `category` varchar(100) DEFAULT NULL,\n"
            "  `price_eur` decimal(10,2) DEFAULT NULL,\n"
            "  `stock_kg` int(11) DEFAULT 0,\n"
            "  PRIMARY KEY (`id`)\n"
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;\n"
            "\n"
            "CREATE TABLE `orders` (\n"
            "  `id` int(11) NOT NULL AUTO_INCREMENT,\n"
            "  `client_id` int(11) NOT NULL,\n"
            "  `created_at` datetime NOT NULL,\n"
            "  `status` enum('pending','dispatched','delivered','cancelled') DEFAULT 'pending',\n"
            "  PRIMARY KEY (`id`)\n"
            ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;\n"
        ))

        files.append(write_temp_file(tmpdir, "config_backup.txt",
            "# Lapin Logistics CMS Configuration Backup\n"
            "# Generated: 2024-01-15\n"
            "# WARNING: This file contains environment-specific settings only.\n"
            "#          Credentials are stored in the secure vault (see IT).\n"
            "\n"
            "[database]\n"
            "host = db01.lapinlogistics.local\n"
            "port = 3306\n"
            "name = lapin_cms\n"
            "# credentials redacted — see vault\n"
            "\n"
            "[cache]\n"
            "driver = redis\n"
            "host = cache01.lapinlogistics.local\n"
            "port = 6379\n"
            "ttl = 3600\n"
            "\n"
            "[mail]\n"
            "driver = smtp\n"
            "host = mail.lapinlogistics.local\n"
            "port = 587\n"
            "from = noreply@lapinlogistics.local\n"
        ))

        files.append(write_temp_file(tmpdir, "htaccess_backup.txt",
            "# .htaccess backup — lapinlogistics.local DocumentRoot\n"
            "# Snapshot date: 2024-01-15\n"
            "\n"
            "Options -Indexes\n"
            "ServerSignature Off\n"
            "\n"
            "RewriteEngine On\n"
            "RewriteBase /\n"
            "RewriteRule ^index\\.php$ - [L]\n"
            "RewriteCond %{REQUEST_FILENAME} !-f\n"
            "RewriteCond %{REQUEST_FILENAME} !-d\n"
            "RewriteRule . /index.php [L]\n"
            "\n"
            "<Files wp-config.php>\n"
            "    order allow,deny\n"
            "    deny from all\n"
            "</Files>\n"
        ))

        prefixes = [""] * len(files)
        pyminizip.compress_multiple(files, prefixes, out_path, password, 5)

    # Password is not retained (callers do not need it)
    return out_path


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()
    outdir = args.outdir

    try:
        import pyminizip  # noqa: F401
    except ImportError as exc:
        print(f"[ERROR] Missing dependency: {exc}", file=sys.stderr)
        print("Install with: pip install pyminizip", file=sys.stderr)
        sys.exit(1)

    os.makedirs(outdir, exist_ok=True)

    files = []

    path = make_archived_emails_zip(outdir)
    print(f"[gen-zip] wrote {path}")
    files.append(path)

    path = make_lapin_backup_zip(outdir)
    print(f"[gen-zip] wrote {path}")
    files.append(path)

    print(f"[gen-zip] done — {len(files)} files written to {outdir}")


if __name__ == "__main__":
    main()
