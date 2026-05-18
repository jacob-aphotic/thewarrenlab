<?php
/**
 * Carrot CMS — page renderer.
 *
 * Legacy content endpoint. Pulls a content fragment by name and renders it
 * inside the CMS chrome. "It's worked fine since 2011, don't touch it."
 *
 *   /carrot-cms/view.php            -> home
 *   /carrot-cms/view.php?page=home  -> home.php
 *   /carrot-cms/view.php?page=news  -> news.php
 *
 * Known nav names map to their *.php fragment; anything else is loaded by
 * name. Stream wrappers are passed through so legacy report tooling that
 * uses php:// inputs keeps working.
 */

$page = $_GET['page'] ?? 'home';

/* Friendly nav names map to local content fragments. Anything not in this
 * map falls through to a name-based include() anchored on the script
 * directory (the include(dirname(__FILE__)."/".$page) shape) so it resolves
 * the same regardless of CWD/include_path. Stream-wrapper inputs are handled
 * by the explicit-wrapper branch below. */
$nav = ['home' => 'home.php', 'news' => 'news.php'];
if (isset($nav[$page])) {
    $target = __DIR__ . '/' . $nav[$page];
} elseif (preg_match('#^[a-zA-Z][a-zA-Z0-9+.-]*://#', $page)) {
    // Stream wrapper (php://filter, data://, …) — pass through verbatim for
    // legacy tooling that feeds wrapper inputs.
    $target = $page;
} else {
    // Name-based path anchored on the CMS dir.
    $target = __DIR__ . '/' . $page;
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Carrot CMS</title>
<style>
  body { font-family: Georgia, "Times New Roman", serif; color:#222; background:#fdfdf7; margin:0; }
  .cms-top { background:#3d5a2a; color:#fff; padding:14px 28px; font-size:1.2rem; font-weight:bold; }
  .cms-top span { font-weight:normal; font-size:.8rem; opacity:.8; }
  .cms-body { max-width:780px; margin:0 auto; padding:30px 28px; }
  .cms-nav { font-size:.85rem; color:#5a6b3f; margin-bottom:18px; }
  .cms-nav a { color:#3d5a2a; }
  .cms-foot { border-top:1px solid #ddd; margin-top:30px; padding-top:12px; font-size:.75rem; color:#999; }
  pre { background:#f4f4ee; padding:14px; overflow:auto; border:1px solid #e0e0d8; }
</style>
</head>
<body>
<div class="cms-top">Carrot CMS <span>&middot; internal content system &middot; v1.4 (2011)</span></div>
<div class="cms-body">
<div class="cms-nav">
  <a href="?page=home">Home</a> &middot;
  <a href="?page=news">News</a> &middot;
  <a href="/index.php">Back to CarrotMart</a>
</div>
<?php
/* ---- Render the requested content fragment. ---- */
include($target);
?>
<div class="cms-foot">Carrot CMS &mdash; &copy; Lapin Logistics. Migration to the new platform pending since 2014.</div>
</div>
</body>
</html>
