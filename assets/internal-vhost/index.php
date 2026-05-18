<?php
/**
 * Lapin Logistics — Internal Company Directory (internal.lapinlogistics.local)
 *
 * Served over HTTPS:443 by module 05. Visitors who haven't added the vhost to
 * /etc/hosts get the generic Apache default (configured by module 05); this
 * page is what they see once they resolve the name.
 */
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lapin Logistics — Internal Directory</title>
<style>
  body { font-family:"Segoe UI",Arial,sans-serif; color:#1f2a14; background:#f3f6ec; margin:0; }
  header { background:#3d5a2a; color:#fff; padding:18px 30px; }
  header h1 { margin:0; font-size:1.4rem; }
  header p { margin:4px 0 0; font-size:.8rem; opacity:.85; letter-spacing:1px; }
  .wrap { max-width:900px; margin:0 auto; padding:28px 30px 60px; }
  .banner { background:#fff7e6; border:1px solid #e3c98a; border-radius:6px; padding:14px 18px; margin:22px 0; }
  table { width:100%; border-collapse:collapse; background:#fff; margin-top:10px; }
  th,td { text-align:left; padding:10px 12px; border-bottom:1px solid #e2e6d6; }
  th { background:#e8efdb; color:#3d5a2a; }
  code { background:#eef0e6; padding:1px 5px; border-radius:3px; }
  footer { text-align:center; color:#7a8463; font-size:.8rem; padding:20px; }
  a { color:#3d5a2a; }
</style>
</head>
<body>
<header>
  <h1>Lapin Logistics &mdash; Internal Company Directory</h1>
  <p>INTERNAL USE ONLY &middot; internal.lapinlogistics.local</p>
</header>
<div class="wrap">

  <div class="banner">
    <strong>Email format:</strong> every employee is reachable at
    <code>firstname.lastname@lapinlogistics.com</code>. HR keeps this directory
    current; raise a ticket if your entry is wrong.
  </div>

  <h2>Staff directory</h2>
  <table>
    <tr><th>Name</th><th>Title</th><th>Team</th><th>Email</th></tr>
    <tr><td>Peter Cottontail</td><td>Junior Warehouse Worker</td><td>Fulfilment</td><td>peter.cottontail@lapinlogistics.com</td></tr>
    <tr><td>Roger Rabbit</td><td>Systems Administrator</td><td>IT</td><td>roger.rabbit@lapinlogistics.com</td></tr>
    <tr><td>Bugs Bunny</td><td>Depot Coordinator</td><td>Logistics</td><td>bugs.bunny@lapinlogistics.com</td></tr>
    <tr><td>Thumper</td><td>Sorting Line Lead</td><td>Fulfilment</td><td>thumper@lapinlogistics.com</td></tr>
    <tr><td>Harvey</td><td>Inventory Auditor</td><td>Quality</td><td>harvey@lapinlogistics.com</td></tr>
    <tr><td>Andrea Hare</td><td>Brand &amp; Communications Manager</td><td>Marketing</td><td>andrea.hare@lapinlogistics.com</td></tr>
  </table>

  <h2 style="margin-top:34px;">Internal resources</h2>
  <ul>
    <li><a href="/docs.php?file=onboarding.txt">IT onboarding checklist</a></li>
    <li><a href="/docs.php?file=vpn-setup.txt">VPN setup guide</a></li>
    <li><a href="/docs.php?file=expense-policy.txt">Expense policy</a></li>
  </ul>
  <p style="font-size:.85rem;color:#7a8463;">
    The legacy WordPress marketing site is being migrated. Configuration is
    being consolidated; do not edit the live config without an IT ticket.
  </p>

</div>
<footer>Lapin Logistics internal systems &middot; unauthorised access is prohibited</footer>
</body>
</html>
