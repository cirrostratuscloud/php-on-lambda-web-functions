<?php
/**
 * JSON view of loaded extensions — machine-readable "all the plugins".
 */

header('Content-Type: application/json');

$exts = get_loaded_extensions();
sort($exts, SORT_FLAG_CASE | SORT_STRING);

$out = [];
foreach ($exts as $e) {
    $fns = @get_extension_funcs(strtolower($e)) ?: [];
    $out[] = [
        'name'           => $e,
        'version'        => phpversion($e) ?: null,
        'function_count' => count($fns),
        'functions'      => $fns,
    ];
}

echo json_encode([
    'php_version' => PHP_VERSION,
    'count'       => count($out),
    'extensions'  => $out,
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
