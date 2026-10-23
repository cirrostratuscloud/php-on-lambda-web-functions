<?php
/**
 * Tiny shared layout. No external assets — everything inline so it renders
 * identically behind the Lambda Web Function endpoint with no extra requests.
 */

function render_head(string $title): void
{
    $t = htmlspecialchars($title, ENT_QUOTES);
    echo <<<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{$t}</title>
<link rel="icon" href="/favicon.svg">
<link rel="stylesheet" href="/styles.css">
</head>
<body>
<header class="topbar">
  <a class="brand" href="/">
    <svg width="26" height="26" viewBox="0 0 48 48" aria-hidden="true">
      <rect x="2" y="2" width="44" height="44" rx="10" fill="#6E5BE4"/>
      <path d="M14 30 L22 18 L28 26 L34 16" fill="none" stroke="#fff" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
    <span>PHP&nbsp;on&nbsp;Lambda&nbsp;<em>Web&nbsp;Functions</em></span>
  </a>
  <nav>
    <a href="/">Dashboard</a>
    <a href="/extensions">Extensions</a>
    <a href="/info">phpinfo()</a>
  </nav>
</header>
<main>
HTML;
}

function render_foot(): void
{
    $php = PHP_VERSION;
    $sapi = php_sapi_name();
    $rid = htmlspecialchars($_SERVER['HTTP_LAMBDA_WEB_REQUEST_ID'] ?? '—', ENT_QUOTES);
    echo <<<HTML
</main>
<footer class="foot">
  <span>PHP {$php} · SAPI {$sapi} · spawned by a Node.js shim inside a Node-only runtime</span>
  <span class="rid">req {$rid}</span>
</footer>
</body>
</html>
HTML;
}
