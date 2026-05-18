<?php
/**
 * Product stock lookup.
 *
 * The id is looked up against a fixed in-code product table (stand-in for a
 * parameterised DB query) and used only as an associative-array key. The
 * not-found message echoes the requested id back (HTML-escaped).
 */

require __DIR__ . '/../inc/layout.php';

// Parameterised "query": a fixed catalogue. The id is only ever used as an
// associative-array key — never touches the filesystem.
$catalogue = [
    '1' => ['Imperator #1',   'Root vegetables', '25kg crate', 'In stock',      '412 crates'],
    '2' => ['Nantes Bunch',   'Root vegetables', '20kg crate', 'In stock',      '388 crates'],
    '3' => ['Purple Haze',    'Root vegetables', '12kg crate', 'Low stock',     '17 crates'],
    '4' => ['Chantenay',      'Root vegetables', '18kg crate', 'In stock',      '256 crates'],
    '5' => ['Parsnip Royale', 'Root vegetables', '15kg crate', 'In stock',      '140 crates'],
    '6' => ['Golden Beet',    'Root vegetables', '14kg crate', 'Back ordered',  '0 crates'],
    '7' => ['Butterhead',     'Leafy greens',    'tray of 12', 'In stock',      '90 trays'],
    '8' => ['Wild Rocket',    'Leafy greens',    '2kg bag',    'In stock',      '203 bags'],
    '9' => ['Rainbow Chard',  'Leafy greens',    'bunch of 10','Low stock',     '11 bunches'],
];

$id = isset($_GET['id']) ? (string) $_GET['id'] : '';

cm_header('Stock lookup', 'products');

if ($id !== '' && array_key_exists($id, $catalogue)) {
    [$name, $cat, $unit, $status, $qty] = $catalogue[$id];
    echo '<h1>' . htmlspecialchars($name) . '</h1>';
    echo '<p class="hint">Item ID ' . htmlspecialchars($id) . ' &middot; ' . htmlspecialchars($cat) . '</p>';
    echo '<div class="grid">';
    echo '<div class="card"><h3>Pack size</h3><p>' . htmlspecialchars($unit) . '</p></div>';
    echo '<div class="card"><h3>Availability</h3><p>' . htmlspecialchars($status) . '</p></div>';
    echo '<div class="card"><h3>On hand</h3><p>' . htmlspecialchars($qty) . '</p></div>';
    echo '</div>';
    echo '<p style="margin-top:28px;"><a class="btn" href="/products.php">&laquo; Back to catalogue</a></p>';
} else {
    // Echo the requested id back, HTML-escaped, in the not-found message.
    echo '<div class="error">Item ID ' . htmlspecialchars($id) . ' not found in the CarrotMart catalogue.</div>';
    echo '<p>Please pick a valid item from the <a href="/products.php">catalogue</a>. ';
    echo 'Item IDs are numeric (1&ndash;9).</p>';
}

cm_footer();
