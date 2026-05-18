<?php
/**
 * Internal document viewer.
 *
 * Serves plain-text documents from the docs/ directory. The requested name
 * is passed through a str_replace('../','') filter before being read with
 * readfile().
 */

$docRoot = __DIR__ . '/docs';                 // documents live here
$file    = $_GET['file'] ?? 'onboarding.txt';

// Single-pass filter on the requested name.
$clean = str_replace('../', '', $file);

$target = $docRoot . '/' . $clean;

header('Content-Type: text/plain; charset=utf-8');

if (is_file($target)) {
    readfile($target);
} else {
    http_response_code(404);
    echo "Document not found: " . $clean . "\n";
    echo "Available documents: onboarding.txt, vpn-setup.txt, expense-policy.txt\n";
}
