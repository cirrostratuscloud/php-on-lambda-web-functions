<?php
/**
 * Router for PHP's built-in server (`php -S ... router.php`).
 *
 * Serves real files on disk directly (assets), otherwise dispatches a small
 * set of routes to front-controller pages. This keeps nice URLs like /info
 * and /extensions working through the Lambda Web Function.
 */

$docRoot = $_SERVER['DOCUMENT_ROOT'];
$path = rtrim(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/', '/');
if ($path === '') {
    $path = '/';
}

// 1) Serve existing static files (css, images, etc.) directly — but never the
//    PHP page files themselves.
$real = realpath($docRoot . urldecode($path));
if ($real && is_file($real) && !preg_match('/\.php$/', $real)) {
    return false;
}

// 2) Route table.
switch ($path) {
    case '/':
        require $docRoot . '/index.php';
        return true;
    case '/info':
        require $docRoot . '/info.php';
        return true;
    case '/extensions':
        require $docRoot . '/extensions.php';
        return true;
    case '/api/extensions':
        require $docRoot . '/api_extensions.php';
        return true;
    case '/api/run':
        require $docRoot . '/api_run.php';
        return true;
}

// 3) Fallback: 404 via the front controller so it still looks styled.
http_response_code(404);
$GLOBALS['__not_found'] = $path;
require $docRoot . '/index.php';
return true;
