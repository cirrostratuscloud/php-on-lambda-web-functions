<?php
/**
 * Interactive dashboard for the PHP-on-Lambda-Web-Functions PoC.
 *
 * Renders real server-side PHP facts (version, SAPI, loaded extensions,
 * environment) with graphics and a small interactive "playground" that calls
 * server-side PHP demos over fetch().
 */

require __DIR__ . '/_layout.php';

$notFound = $GLOBALS['__not_found'] ?? null;

$exts = get_loaded_extensions();
sort($exts, SORT_FLAG_CASE | SORT_STRING);
$extCount = count($exts);

$mem = ini_get('memory_limit');
$arch = php_uname('m');
$osRelease = php_uname('r');
$requestId = $_SERVER['HTTP_LAMBDA_WEB_REQUEST_ID'] ?? null;
$region = getenv('AWS_REGION') ?: null;
$endpoint = getenv('AWS_LAMBDA_HTTP_ENDPOINT') ?: null;

$hasGd = extension_loaded('gd');

render_head('PHP on Lambda Web Functions');
?>
<?php if ($notFound): ?>
  <div class="hero" style="border-color:var(--bad)">
    <div>
      <div class="badge" style="background:var(--bad);color:#fff">404</div>
      <h1>No route for <?= htmlspecialchars($notFound, ENT_QUOTES) ?></h1>
      <p class="sub">Try the <a class="back" href="/">dashboard</a>, <a class="back" href="/extensions">extensions</a>, or <a class="back" href="/info">phpinfo()</a>.</p>
    </div>
  </div>
<?php endif; ?>

<div class="hero">
  <div class="spin" aria-hidden="true">
    <svg width="84" height="84" viewBox="0 0 120 120">
      <defs>
        <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="#6E5BE4"/>
          <stop offset="1" stop-color="#37D0C2"/>
        </linearGradient>
      </defs>
      <circle cx="60" cy="60" r="50" fill="none" stroke="url(#g)" stroke-width="6" stroke-dasharray="40 18" stroke-linecap="round"/>
      <circle cx="60" cy="60" r="34" fill="none" stroke="#2a2f52" stroke-width="4"/>
      <text x="60" y="68" text-anchor="middle" font-size="26" fill="#e7e9f5" font-family="system-ui" font-weight="700">PHP</text>
    </svg>
  </div>
  <div>
    <div class="badge">live · it really runs</div>
    <h1>PHP <?= htmlspecialchars(PHP_VERSION, ENT_QUOTES) ?> inside a Node-only runtime</h1>
    <p class="sub" style="margin-bottom:0">
      This page is rendered by a real PHP process, spawned by a Node.js shim
      and reverse-proxied inside an AWS Lambda Web Function.
    </p>
    <div class="pill-row">
      <span class="pill">SAPI <b><?= htmlspecialchars(php_sapi_name(), ENT_QUOTES) ?></b></span>
      <span class="pill">arch <b><?= htmlspecialchars($arch, ENT_QUOTES) ?></b></span>
      <span class="pill">kernel <b><?= htmlspecialchars($osRelease, ENT_QUOTES) ?></b></span>
      <?php if ($region): ?><span class="pill">region <b><?= htmlspecialchars($region, ENT_QUOTES) ?></b></span><?php endif; ?>
    </div>
  </div>
</div>

<div class="grid">
  <div class="card"><h3>PHP version</h3><div class="big ok"><?= htmlspecialchars(PHP_VERSION, ENT_QUOTES) ?></div></div>
  <div class="card"><h3>Loaded extensions</h3><div class="big"><?= $extCount ?></div></div>
  <div class="card"><h3>Memory limit</h3><div class="big"><?= htmlspecialchars($mem, ENT_QUOTES) ?></div></div>
  <div class="card"><h3>Zend engine</h3><div class="big"><?= htmlspecialchars(zend_version(), ENT_QUOTES) ?></div></div>
  <div class="card"><h3>Listen endpoint</h3><div class="big" style="font-size:16px"><?= htmlspecialchars($endpoint ?? '—', ENT_QUOTES) ?></div></div>
  <div class="card"><h3>Web request id</h3><div class="big" style="font-size:14px;font-family:ui-monospace,Menlo,monospace"><?= htmlspecialchars($requestId ?? '—', ENT_QUOTES) ?></div></div>
</div>

<section>
  <h2>Interactive playground</h2>
  <div class="playground">
    <p class="sub" style="margin-top:0">Each action runs server-side in PHP and returns the result. Nothing is evaluated from your input &mdash; the demos are a fixed, safe allowlist.</p>
    <div class="row">
      <div>
        <label for="demo">Demo</label>
        <select id="demo">
          <option value="hash">Hashing (md5 / sha256 / crc32)</option>
          <option value="date">Date math (parse &amp; add interval)</option>
          <option value="json">Pretty-print &amp; validate JSON</option>
          <option value="uuid">Random UUID v4 (random_bytes)</option>
          <option value="image"<?= $hasGd ? '' : ' ' ?>>Generate an image (<?= $hasGd ? 'gd' : 'SVG fallback' ?>)</option>
        </select>
      </div>
      <div>
        <label for="arg">Input</label>
        <input type="text" id="arg" value="hello from the browser" placeholder="input for the demo">
      </div>
    </div>
    <button class="run" id="runBtn">Run in PHP</button>
    <div class="out" id="out">Pick a demo and hit “Run in PHP”.</div>
  </div>
</section>

<section>
  <h2>Loaded extensions <span style="color:var(--muted);font-weight:400">(<?= $extCount ?>)</span></h2>
  <div class="ext-grid">
    <?php foreach ($exts as $e): $v = phpversion($e); ?>
      <div class="ext">
        <span class="dot"></span>
        <span><?= htmlspecialchars($e, ENT_QUOTES) ?></span>
        <?php if ($v): ?><span class="ver"><?= htmlspecialchars($v, ENT_QUOTES) ?></span><?php endif; ?>
      </div>
    <?php endforeach; ?>
  </div>
  <p style="margin-top:12px"><a class="back" href="/extensions">Full extension detail &rarr;</a> &nbsp;·&nbsp; <a class="back" href="/api/extensions">as JSON</a></p>
</section>

<script>
const out = document.getElementById('out');
const btn = document.getElementById('runBtn');
btn.addEventListener('click', async () => {
  const demo = document.getElementById('demo').value;
  const arg = document.getElementById('arg').value;
  out.textContent = 'Running in PHP…';
  try {
    const res = await fetch('/api/run?' + new URLSearchParams({ demo, arg }));
    const ct = res.headers.get('content-type') || '';
    if (ct.startsWith('image/') || ct.includes('svg')) {
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      out.innerHTML = '';
      const img = document.createElement('img');
      img.src = url;
      out.appendChild(img);
    } else {
      const data = await res.json();
      out.textContent = JSON.stringify(data, null, 2);
    }
  } catch (err) {
    out.textContent = 'Error: ' + err;
  }
});
</script>
<?php
render_foot();
