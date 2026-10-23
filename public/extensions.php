<?php
/**
 * Detailed loaded-extensions view: every extension, its version, and the
 * functions it provides (count + a sample), rendered as cards.
 */

require __DIR__ . '/_layout.php';

$exts = get_loaded_extensions();
sort($exts, SORT_FLAG_CASE | SORT_STRING);

render_head('Extensions · PHP on Lambda Web Functions');
echo '<p><a class="back" href="/">&larr; Back to dashboard</a></p>';
?>
<h1>Loaded extensions</h1>
<p class="sub"><?= count($exts) ?> extensions compiled into this static PHP build. <a class="back" href="/api/extensions">Get this as JSON &rarr;</a></p>

<div class="grid">
<?php foreach ($exts as $e):
    $ver = phpversion($e) ?: null;
    $fns = @get_extension_funcs(strtolower($e)) ?: [];
    $sample = array_slice($fns, 0, 6);
?>
  <div class="card">
    <h3><?= htmlspecialchars($e, ENT_QUOTES) ?><?php if ($ver): ?> <span style="color:var(--accent-2)">v<?= htmlspecialchars($ver, ENT_QUOTES) ?></span><?php endif; ?></h3>
    <div style="font-size:13px;color:var(--muted);margin-bottom:6px"><?= count($fns) ?> function<?= count($fns) === 1 ? '' : 's' ?></div>
    <?php if ($sample): ?>
      <div style="font:12px/1.5 ui-monospace,Menlo,monospace;color:#cfd3f2;word-break:break-word">
        <?= htmlspecialchars(implode('(), ', $sample), ENT_QUOTES) ?>()<?= count($fns) > count($sample) ? ' …' : '' ?>
      </div>
    <?php endif; ?>
  </div>
<?php endforeach; ?>
</div>
<?php
render_foot();
