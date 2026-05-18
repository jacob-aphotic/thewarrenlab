#!/usr/bin/env bash
# gen-git-repo.sh — Lapin Logistics asset generator: CarrotMart .git/ history.
#
# Usage:
#   bash assets/gen-git-repo.sh <dest-parent-dir>
#
# Behaviour:
#   1. Creates a temporary directory and initialises a real git repository there.
#   2. Makes exactly 3 commits with a short CarrotMart CMS history.
#      Commit 2: "TODO: rotate prod DB password (URGENT)"
#      Commit 3: "rotated, see vault."
#   3. Copies the resulting .git/ into <dest-parent-dir>/.git/
#      (overwrites any existing .git/ at that path).
#   4. Cleans up the temp directory.
#
# Arguments:
#   $1  dest-parent-dir   Path to the directory that should receive the .git/
#                         (e.g. /var/www/carrotmart). Created if it does not exist.
#
# Exit codes:
#   0  success
#   1  missing argument or git failure

set -euo pipefail

DEST_PARENT="${1:-}"

if [[ -z "$DEST_PARENT" ]]; then
    echo "[gen-git-repo] ERROR: dest-parent-dir argument is required" >&2
    echo "Usage: bash assets/gen-git-repo.sh <dest-parent-dir>" >&2
    exit 1
fi

# Canonicalise to absolute path (handles relative paths called from any CWD;
# GNU coreutils -m allows the path to not yet exist)
DEST_PARENT="$(realpath -m "$DEST_PARENT")"

# Pre-flight: ensure git is available
command -v git >/dev/null 2>&1 || { echo "[gen-git-repo] ERROR: git not found in PATH" >&2; exit 1; }

# Ensure destination parent exists
mkdir -p "$DEST_PARENT"

# Create isolated temp working directory
TMPDIR_REPO="$(mktemp -d /tmp/lapin-git-XXXXXX)"
trap 'rm -rf "$TMPDIR_REPO"' EXIT

cd "$TMPDIR_REPO"

# Initialise repo with a fixed branch name (avoid git version drift on 'master' vs 'main')
git init -b main
git config user.email "build@lapinlogistics.local"
git config user.name "Lapin Build System"

# ---------------------------------------------------------------------------
# Commit 1 — initial carrot CMS setup (innocuous baseline)
# ---------------------------------------------------------------------------
mkdir -p src

cat > src/config.php << 'PHPEOF'
<?php
// CarrotMart CMS — initial configuration
define('DB_HOST', 'localhost');
define('DB_NAME', 'carrotmart');
define('DB_USER', 'cmsweb');
// DB_PASS loaded from environment
define('SITE_NAME', 'CarrotMart by Lapin Logistics');
define('DEBUG_MODE', false);
PHPEOF

cat > src/index.php << 'PHPEOF'
<?php
require_once 'config.php';
// Front-page stub
echo '<h1>' . SITE_NAME . '</h1>';
echo '<p>Fresh carrots delivered to your door.</p>';
PHPEOF

cat > README.md << 'TXTEOF'
# CarrotMart CMS

Internal source for the Lapin Logistics CarrotMart storefront.
See docs/deployment.md for setup instructions.
TXTEOF

git add .
git commit -m "Initial CMS scaffolding — CarrotMart v1.0"

# ---------------------------------------------------------------------------
# Commit 2 — TODO note about rotating the prod DB password
# ---------------------------------------------------------------------------
cat > src/config.php << 'PHPEOF'
<?php
// CarrotMart CMS — configuration
define('DB_HOST', 'db01.lapinlogistics.local');
define('DB_NAME', 'carrotmart');
define('DB_USER', 'cmsweb');
// TODO: rotate prod DB password (URGENT) — still using the old one from Q1 setup
// temporary: define('DB_PASS', getenv('CARROT_DB_PASS'));
define('DB_PASS', getenv('CARROT_DB_PASS'));
define('SITE_NAME', 'CarrotMart by Lapin Logistics');
define('DEBUG_MODE', false);
PHPEOF

cat >> README.md << 'TXTEOF'

## Deployment notes

- Point DNS lapinlogistics.local → server IP
- Set CARROT_DB_PASS env var (see IT for current value)
TXTEOF

git add .
git commit -m "TODO: rotate prod DB password (URGENT)"

# ---------------------------------------------------------------------------
# Commit 3 — "rotated, see vault."
# ---------------------------------------------------------------------------
cat > src/config.php << 'PHPEOF'
<?php
// CarrotMart CMS — configuration
define('DB_HOST', 'db01.lapinlogistics.local');
define('DB_NAME', 'carrotmart');
define('DB_USER', 'cmsweb');
// Password rotated 2024-Q2 — stored in vault, retrieved at runtime
define('DB_PASS', getenv('CARROT_DB_PASS'));
define('SITE_NAME', 'CarrotMart by Lapin Logistics');
define('DEBUG_MODE', false);
PHPEOF

cat > src/healthcheck.php << 'PHPEOF'
<?php
// Basic health-check endpoint — returns 200 OK if DB is reachable
require_once 'config.php';
try {
    $pdo = new PDO('mysql:host=' . DB_HOST . ';dbname=' . DB_NAME, DB_USER, DB_PASS);
    http_response_code(200);
    echo 'OK';
} catch (PDOException $e) {
    http_response_code(503);
    echo 'DB unavailable';
}
PHPEOF

git add .
git commit -m "rotated, see vault."

# ---------------------------------------------------------------------------
# Copy .git/ into destination
# ---------------------------------------------------------------------------
cd /  # leave the temp dir before we copy from it

DEST_GIT="${DEST_PARENT}/.git"

# Remove any stale .git at destination
if [[ -e "$DEST_GIT" ]]; then
    rm -rf "$DEST_GIT"
fi

cp -r "${TMPDIR_REPO}/.git" "$DEST_GIT"

echo "[gen-git-repo] wrote ${DEST_GIT}"
echo "[gen-git-repo] commits:"
git --git-dir="$DEST_GIT" log --oneline

echo "[gen-git-repo] done"
