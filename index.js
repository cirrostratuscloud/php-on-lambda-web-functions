'use strict';

/**
 * Node.js shim that runs a PHP application inside an AWS Lambda Web Function.
 *
 * Why this exists:
 *   Lambda Web Functions currently support ONLY the Node.js runtime (nodejs24.x).
 *   There is no managed PHP runtime and no documented custom/OS-only runtime path
 *   for Web Functions. But the Web Function contract is just: "be a process that
 *   speaks plain HTTP on the host:port Lambda gives you, and start listening within
 *   10 seconds." Nothing says the process has to BE the thing doing the real work.
 *
 * So: Node is the thin front door. It
 *   1. binds the real Lambda endpoint immediately (to beat the 10s listen deadline),
 *   2. spawns PHP's built-in web server on a private localhost port,
 *   3. reverse-proxies every incoming request to PHP,
 *   4. holds requests briefly while PHP warms up, so the first request doesn't 502.
 *
 * The PHP binary is shipped inside the deployment zip (see README) because the
 * Node runtime image has no PHP. We exec that bundled binary.
 */

const http = require('http');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

// Lambda tells us where to listen via AWS_LAMBDA_HTTP_ENDPOINT (host:port).
// The documented local fallback is localhost:3000 when the var is unset.
const [LISTEN_HOST, LISTEN_PORT] = (
  process.env.AWS_LAMBDA_HTTP_ENDPOINT || 'localhost:3000'
).split(':');

// Private address for the PHP built-in server. Not exposed to Lambda.
const PHP_HOST = '127.0.0.1';
const PHP_PORT = Number(process.env.PHP_INTERNAL_PORT || 8000);

// Document root served by PHP. Overridable for layout flexibility.
const DOC_ROOT = process.env.PHP_DOCROOT
  ? path.resolve(process.env.PHP_DOCROOT)
  : path.join(__dirname, 'public');

// Where the bundled PHP binary lives inside the zip. In the Lambda task root
// this resolves to /var/task/bin/php. Locally it resolves next to this file.
// PHP_BIN lets you point at a system php for local testing.
const PHP_BIN =
  process.env.PHP_BIN || path.join(__dirname, 'bin', 'php');

// How long to wait for PHP to accept connections before giving up (ms).
// Must stay comfortably under the Web Function 10s startup budget.
const PHP_READY_TIMEOUT_MS = Number(process.env.PHP_READY_TIMEOUT_MS || 7000);

// ---------------------------------------------------------------------------
// PHP child process
// ---------------------------------------------------------------------------

let phpReady = false;
let phpProc = null;

function startPhp() {
  // `php -S host:port -t docroot` runs PHP's built-in web server.
  // We route ALL requests through a router so pretty URLs / framework front
  // controllers work; see public/router.php.
  const router = path.join(DOC_ROOT, 'router.php');
  const args = ['-S', `${PHP_HOST}:${PHP_PORT}`, '-t', DOC_ROOT];
  if (fs.existsSync(router)) {
    args.push(router);
  }

  log('spawning php', { bin: PHP_BIN, args });

  phpProc = spawn(PHP_BIN, args, {
    stdio: ['ignore', 'inherit', 'inherit'],
    env: {
      ...process.env,
      // Keep PHP's own output buffering predictable for streaming.
      PHP_CLI_SERVER_WORKERS: process.env.PHP_CLI_SERVER_WORKERS || '4',
    },
  });

  phpProc.on('exit', (code, signal) => {
    phpReady = false;
    log('php exited', { code, signal });
    // If PHP dies, the environment is unusable. Exit so Lambda recycles it.
    process.exit(code == null ? 1 : code);
  });

  phpProc.on('error', (err) => {
    log('php spawn error', { message: err.message });
    process.exit(1);
  });
}

// Poll the PHP server until it accepts a TCP connection.
function waitForPhp() {
  const deadline = Date.now() + PHP_READY_TIMEOUT_MS;

  const attempt = () => {
    const socket = require('net').connect(PHP_PORT, PHP_HOST);
    socket.on('connect', () => {
      socket.destroy();
      phpReady = true;
      log('php is ready');
    });
    socket.on('error', () => {
      socket.destroy();
      if (Date.now() > deadline) {
        log('php did not become ready in time');
        process.exit(1);
      }
      setTimeout(attempt, 100);
    });
  };

  attempt();
}

// ---------------------------------------------------------------------------
// Front-door HTTP server (what Lambda actually talks to)
// ---------------------------------------------------------------------------

const server = http.createServer((clientReq, clientRes) => {
  // If PHP isn't up yet, briefly hold the request rather than failing. The
  // very first request can arrive while PHP is still warming.
  if (!phpReady) {
    const holdUntil = Date.now() + PHP_READY_TIMEOUT_MS;
    const poll = () => {
      if (phpReady) return proxy(clientReq, clientRes);
      if (Date.now() > holdUntil) {
        clientRes.writeHead(503, { 'content-type': 'text/plain' });
        clientRes.end('PHP backend not ready\n');
        return;
      }
      setTimeout(poll, 50);
    };
    return poll();
  }
  proxy(clientReq, clientRes);
});

function proxy(clientReq, clientRes) {
  const options = {
    host: PHP_HOST,
    port: PHP_PORT,
    method: clientReq.method,
    path: clientReq.url,
    headers: { ...clientReq.headers, host: `${PHP_HOST}:${PHP_PORT}` },
  };

  const upstream = http.request(options, (upRes) => {
    clientRes.writeHead(upRes.statusCode, upRes.headers);
    upRes.pipe(clientRes); // streams responses through unchanged
  });

  upstream.on('error', (err) => {
    log('upstream error', { message: err.message });
    if (!clientRes.headersSent) {
      clientRes.writeHead(502, { 'content-type': 'text/plain' });
    }
    clientRes.end('Bad gateway (PHP upstream)\n');
  });

  clientReq.pipe(upstream); // streams request body through unchanged
}

// ---------------------------------------------------------------------------
// Boot sequence
// ---------------------------------------------------------------------------

function log(msg, extra) {
  // Structured-ish logging to CloudWatch via stdout.
  console.log(JSON.stringify({ src: 'php-shim', msg, ...extra }));
}

// Bind the Lambda-facing listener FIRST so we satisfy the 10s startup deadline
// even if PHP is a touch slow to come up.
server.listen(Number(LISTEN_PORT), LISTEN_HOST, () => {
  log('shim listening', { host: LISTEN_HOST, port: LISTEN_PORT, docRoot: DOC_ROOT });
  startPhp();
  waitForPhp();
});

// Graceful-ish shutdown: forward termination to the PHP child.
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    log('received signal, shutting down', { sig });
    if (phpProc) phpProc.kill(sig);
    server.close(() => process.exit(0));
  });
}
