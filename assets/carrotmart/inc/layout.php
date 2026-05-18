<?php
/**
 * CarrotMart shared layout partials.
 * Storefront chrome only (header/footer/nav).
 */
function cm_header(string $title, string $active = ''): void {
    $nav = [
        'index'    => ['Home', 'index.php'],
        'products' => ['Products', 'products.php'],
        'about'    => ['About', 'about.php'],
        'team'     => ['Team', 'team.php'],
        'contact'  => ['Contact', 'contact.php'],
    ];
    echo "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n";
    echo "<meta charset=\"utf-8\">\n";
    echo "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n";
    echo "<title>" . htmlspecialchars($title) . " — CarrotMart</title>\n";
    echo "<link rel=\"stylesheet\" href=\"/assets/style.css\">\n";
    echo "</head>\n<body>\n";
    echo "<header class=\"site\"><div class=\"wrap\">";
    echo "<a class=\"brand\" href=\"/index.php\">CarrotMart<small>DELIVERING CRISP PRODUCE SINCE 1973</small></a>";
    echo "<nav class=\"main\">";
    foreach ($nav as $key => $item) {
        $cls = ($key === $active) ? ' class="active"' : '';
        echo "<a href=\"/{$item[1]}\"{$cls}>" . htmlspecialchars($item[0]) . "</a>";
    }
    echo "</nav></div></header>\n";
    echo "<main class=\"wrap\">\n";
}

function cm_footer(): void {
    $year = date('Y');
    echo "</main>\n";
    echo "<footer class=\"site\"><div class=\"wrap\">";
    echo "CarrotMart, a division of <strong>Lapin Logistics</strong> &bull; ";
    echo "1973&ndash;{$year} &bull; ";
    echo "<a href=\"/contact.php\">Customer Care</a> &bull; ";
    echo "Warehouse 7, Burrow Industrial Park";
    echo "</div></footer>\n";
    echo "</body>\n</html>\n";
}
