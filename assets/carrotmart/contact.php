<?php require __DIR__ . '/inc/layout.php'; cm_header('Contact', 'contact'); ?>
<div class="hero">
  <h1>Customer Care</h1>
  <p>Questions about a crate, a depot run, or a wholesale account? The warren is listening.</p>
</div>

<div class="grid">
  <div class="card">
    <h3>Orders &amp; Deliveries</h3>
    <p>Phone: +1 (555) 0173-CARROT<br>
    Hours: Mon&ndash;Sat, 05:00&ndash;19:00</p>
  </div>
  <div class="card">
    <h3>Wholesale Accounts</h3>
    <p>Email our trade desk for depot pricing and warren-run scheduling.</p>
  </div>
  <div class="card">
    <h3>Press</h3>
    <p>Media enquiries are handled by the Lapin Logistics communications team.</p>
  </div>
</div>

<h2 style="margin-top:40px;">Send us a message</h2>
<form method="post" action="/contact.php" style="max-width:520px;">
  <label for="name">Your name</label>
  <input type="text" id="name" name="name" placeholder="e.g. Jane Grocer">
  <label for="email">Your email</label>
  <input type="email" id="email" name="email" placeholder="you@example.com">
  <label for="message">Message</label>
  <textarea id="message" name="message" rows="4" placeholder="How can the warren help?"></textarea>
  <button class="btn" type="submit">Send to Customer Care</button>
</form>
<?php
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // Storefront contact form: submissions are acknowledged client-side.
    echo '<div class="notice">Thanks! A member of the warren will hop back to you within one business day.</div>';
}
cm_footer();
?>
