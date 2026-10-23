<?php
/**
 * Native phpinfo() dump, wrapped in our layout. phpinfo() emits a full HTML
 * table of configuration, loaded modules, and their settings — the most
 * complete "what's in this PHP build" view there is.
 */

require __DIR__ . '/_layout.php';

render_head('phpinfo() · PHP on Lambda Web Functions');
echo '<p><a class="back" href="/">&larr; Back to dashboard</a></p>';
echo '<h1>phpinfo()</h1>';
echo '<p class="sub">The complete native configuration report for this runtime, including every loaded module and its settings.</p>';
echo '<div class="phpinfo-wrap">';

// Capture phpinfo()'s own HTML and inline it inside our page.
ob_start();
phpinfo();
$info = ob_get_clean();

// phpinfo() returns a full HTML document; extract just the <body> contents so
// it nests cleanly in our layout.
if (preg_match('#<body[^>]*>(.*)</body>#si', $info, $m)) {
    echo $m[1];
} else {
    echo $info;
}

echo '</div>';
render_foot();
