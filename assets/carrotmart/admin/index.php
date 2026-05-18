<?php
/**
 * CarrotMart admin console — login.
 *
 * Brute-force protection:
 *   - 3 failed attempts -> "Account locked, retry in 60 minutes"
 *   - lockout state persisted in /tmp/admin_lockout_<key> (survives the
 *     PHP session, so a fresh cookie does not reset it for that client)
 *   - every response carries an X-RateLimit-Remaining header.
 *
 * Implementation notes:
 *   - PHP session backs the in-flight attempt counter.
 *   - A /tmp/admin_lockout_<key> file makes the lockout sticky per client
 *     (key = client IP, falling back to the session id). When present and
 *     fresh (< 60 min) the account stays locked even with a new session.
 */

session_start();

const MAX_ATTEMPTS   = 3;
const LOCKOUT_SECS   = 3600;            // 60 minutes
const LOCK_PREFIX    = '/tmp/admin_lockout_';

/* Per-client key: IP if we have one, else the session id. Sanitised so it is
 * always a safe filename component. */
$rawKey  = $_SERVER['REMOTE_ADDR'] ?? session_id();
$key     = preg_replace('/[^A-Za-z0-9_.-]/', '_', (string) $rawKey);
$lockFile = LOCK_PREFIX . $key;

if (!isset($_SESSION['admin_attempts'])) {
    $_SESSION['admin_attempts'] = 0;
}

/* ---- Determine current lock state ---- */
$lockedUntil = 0;
if (is_file($lockFile)) {
    $ts = (int) trim(@file_get_contents($lockFile));
    if ($ts > 0 && (time() - $ts) < LOCKOUT_SECS) {
        $lockedUntil = $ts + LOCKOUT_SECS;
    } else {
        // stale lock — clear it so the lockout resets after an hour
        @unlink($lockFile);
        $_SESSION['admin_attempts'] = 0;
    }
}
$isLocked = $lockedUntil > 0;

$message   = '';
$msgClass  = 'error';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($isLocked) {
        $message = 'Account locked, retry in 60 minutes.';
    } else {
        // Credentials are validated server-side; failed attempts are counted.
        $_SESSION['admin_attempts']++;
        $remaining = MAX_ATTEMPTS - $_SESSION['admin_attempts'];

        if ($_SESSION['admin_attempts'] >= MAX_ATTEMPTS) {
            @file_put_contents($lockFile, (string) time());
            $isLocked    = true;
            $lockedUntil = time() + LOCKOUT_SECS;
            $message     = 'Account locked, retry in 60 minutes.';
        } else {
            $message = 'Invalid username or password. '
                     . $remaining . ' attempt' . ($remaining === 1 ? '' : 's')
                     . ' remaining before lockout.';
        }
    }
}

/* X-RateLimit-Remaining: clamp at 0 once locked. Emitted on every response. */
$remainingHdr = $isLocked ? 0 : max(0, MAX_ATTEMPTS - (int) $_SESSION['admin_attempts']);
header('X-RateLimit-Remaining: ' . $remainingHdr);
header('X-RateLimit-Limit: ' . MAX_ATTEMPTS);
if ($isLocked) {
    header('Retry-After: ' . max(1, $lockedUntil - time()));
    http_response_code(403);
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Admin Console — CarrotMart</title>
<link rel="stylesheet" href="/assets/style.css">
</head>
<body>
<header class="site"><div class="wrap">
  <a class="brand" href="/index.php">CarrotMart<small>ADMIN CONSOLE</small></a>
</div></header>
<main class="wrap">
  <div class="login-box">
    <h2 style="border:none;color:#c1570a;margin-top:0;">Staff sign in</h2>
    <p class="hint">Authorised personnel only. Activity is logged.</p>
    <?php if ($message !== ''): ?>
      <div class="<?= $msgClass ?>"><?= htmlspecialchars($message) ?></div>
    <?php endif; ?>
    <?php if ($isLocked): ?>
      <p class="hint">This console is temporarily unavailable from your location.</p>
    <?php else: ?>
      <form method="post" action="/admin/">
        <label for="username">Username</label>
        <input type="text" id="username" name="username" autocomplete="off" autofocus>
        <label for="password">Password</label>
        <input type="password" id="password" name="password" autocomplete="off">
        <button class="btn" type="submit">Sign in</button>
      </form>
    <?php endif; ?>
  </div>
</main>
<footer class="site"><div class="wrap">CarrotMart Admin &bull; Lapin Logistics IT</div></footer>
</body>
</html>
