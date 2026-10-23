# PHP on AWS Lambda Web Functions (proof of concept)

Lambda Web Functions let you run a long-lived HTTP server as a serverless
function. As of launch, the **only supported runtime is Node.js
(`nodejs24.x`)** — there is no managed PHP runtime, and (unlike Event
Functions) no documented custom / OS-only runtime path for Web Functions.

This PoC runs PHP anyway, by exploiting the one thing the Web Function contract
actually requires: *be a process that speaks plain HTTP on the host:port Lambda
gives you, and start listening within 10 seconds.* It never says that process
has to be the one doing the real work.

So Node is a thin front door:

```
client ──HTTPS──> Lambda endpoint ──HTTP──> index.js (Node shim) ──HTTP──> php -S (PHP app)
                                            │                               (127.0.0.1:8000)
                                            └ binds AWS_LAMBDA_HTTP_ENDPOINT immediately
                                              spawns PHP, reverse-proxies every request
```

Sources:
- [AWS Lambda Web Functions](https://docs.aws.amazon.com/lambda/latest/dg/web-functions.html)
- [Lambda Web Function runtimes (Node.js only)](https://docs.aws.amazon.com/lambda/latest/dg/web-functions-runtimes.html)
- [Creating a Lambda Web Function](https://docs.aws.amazon.com/lambda/latest/dg/web-functions-create.html)

Content was rephrased for compliance with licensing restrictions.

## How it works

`index.js` (the Web Function entry point Lambda loads by default):

1. Reads `AWS_LAMBDA_HTTP_ENDPOINT` (`host:port`) and **binds that listener
   first**, so we satisfy the 10-second startup deadline even if PHP is slow.
2. Spawns the bundled PHP binary running its built-in server:
   `bin/php -S 127.0.0.1:8000 -t public public/router.php`.
3. Reverse-proxies every request to PHP, streaming request and response bodies
   through unchanged (so response streaming still works).
4. Holds the very first request briefly while PHP warms, instead of 502-ing.

`public/index.php` is a front controller that returns JSON proving PHP really
ran (PHP version, `cli-server` SAPI, `zend_version()`, the
`lambda-web-request-id` header Lambda injects, etc.).

## The one hard requirement: a Linux PHP binary in the zip

The `nodejs24.x` image has **no PHP**, so we ship our own. It must be:

- **statically linked** (don't depend on system libraries that may be absent), and
- built for **Linux**, matching the function architecture — **arm64 == `aarch64`**.

`scripts/fetch-php.sh` downloads a static build (from the static-php-cli
project) to `bin/php`. If the asset URL has changed, grab a
`linux-aarch64` static `php` binary manually, drop it at `bin/php`, and
`chmod +x bin/php`. (The binary is Linux-only; it will not run on your Mac —
that's fine, it only runs inside Lambda.)

## Deploy

```bash
# 1. get a static linux/arm64 PHP binary into bin/php
npm run fetch-php              # or: TARGET_ARCH=x86_64 PHP_VERSION=8.3 scripts/fetch-php.sh

# 2. deploy (creates the Web Function, revision, endpoint + default role/bucket)
NAME=php-web-poc npm run deploy
```

Then hit the endpoint URL the deploy prints:

```bash
curl https://<domainName>/
```

## Clean up

```bash
# delete the Web Function only (endpoints + revisions go with it); prompts first
NAME=php-web-poc scripts/cleanup.sh

# also sweep the leftovers deploy created: default IAM role, S3 deploy objects, log group
NAME=php-web-poc scripts/cleanup.sh --all

# see exactly what would be deleted without changing anything
NAME=php-web-poc scripts/cleanup.sh --all --dry-run
```

`aws lambda-web delete-web-function` removes the function, its endpoints, and
its revisions, but deliberately leaves the default IAM role, the S3 deployment
objects, and the CloudWatch log group behind. `--all` (or the individual
`--role` / `--s3` / `--logs` flags) sweeps those too. The script never deletes
the managed S3 bucket itself — it's shared by every `lambda-web` deployment in
the account + region. Use `--dry-run` to preview and `--yes` to skip prompts in
CI.

A JSON response containing `"php_version"` and `"php_sapi":"cli-server"` is
proof PHP executed inside the Web Function.

> The function defaults to **arm64**. Make sure the PHP binary arch matches the
> architecture the Web Function actually runs on. If you deploy as x86_64, fetch
> with `TARGET_ARCH=x86_64`.

### Manual API path (instead of `aws lambda-web deploy`)

If you'd rather drive the raw API:

```bash
scripts/build-zip.sh                               # builds function.zip
aws s3 cp function.zip s3://YOUR_BUCKET/php-web.zip
aws lambda-web create-web-function \
  --function-name php-web-poc \
  --revision-config '{
    "buildConfig": {
      "codeConfig": { "s3Object": { "bucket": "YOUR_BUCKET", "key": "php-web.zip" } },
      "runtimeConfig": { "runtime": "nodejs24.x" }
    },
    "serviceConfig": { "executionRoleArn": "arn:aws:iam::ACCOUNT:role/YOUR_ROLE" }
  }' \
  --endpoint-config '{
    "endpointName": "dev", "endpointType": "HomeRegion",
    "authType": "ApplicationManaged", "autoDeploymentMode": "LatestRevision"
  }'
```

## Known risks / what to watch on the first real run

This PoC is written against the *documented* contract. Two things can only be
confirmed by deploying, because the docs don't promise them either way:

- **Child processes.** The shim assumes the Web Function environment lets Node
  `spawn()` an arbitrary bundled binary. If that's restricted, Option A (this
  design) won't work and you'd fall back to a pure-PHP-less approach.
- **Static binary compatibility.** The static PHP build must run on the Amazon
  Linux 2023 Web Function image for the chosen arch. Arch mismatch (shipping
  x86_64 to an arm64 function, or vice-versa) is the most likely failure — the
  symptom is the shim staying up but every request returning 502/503 because
  PHP never came up. Check CloudWatch logs for the `php-shim` JSON lines
  (`spawning php`, `php is ready`, or `php exited`).

Lambda marks a revision `Active` without verifying your server listens, so a
broken deploy can still *look* healthy until you send a request.

## Files

| File | Purpose |
|------|---------|
| `index.js` | Node shim: binds the Lambda endpoint, spawns + reverse-proxies PHP |
| `public/index.php` | PHP front controller (returns proof-of-PHP JSON) |
| `public/router.php` | Router for `php -S` (static files direct, else front controller) |
| `bin/php` | Static Linux PHP binary — fetched by `fetch-php.sh`, git-ignored (not committed) |
| `scripts/fetch-php.sh` | Download a static PHP binary into `bin/php` |
| `scripts/build-zip.sh` | Build `function.zip` for the manual API path |
| `scripts/deploy.sh` | Deploy via `aws lambda-web deploy` |
| `scripts/cleanup.sh` | Tear down the Web Function (and optionally role/S3/logs) |
| `.lambdaignore` | Keeps docs/scripts/git out of the deployed zip |
