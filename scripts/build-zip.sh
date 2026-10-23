#!/usr/bin/env bash
#
# Build the deployment .zip for the Lambda Web Function.
#
# Zip layout (everything relative to the task root, /var/task at runtime):
#   index.js            <- Web Function entry point (loaded by default)
#   bin/php             <- bundled static PHP binary (linux, arch-matched)
#   public/index.php    <- PHP front controller
#   public/router.php   <- built-in-server router
#
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="${OUT:-function.zip}"

if [ ! -f bin/php ]; then
  echo "ERROR: bin/php is missing. Run scripts/fetch-php.sh first." >&2
  exit 1
fi

rm -f "$OUT"

# -X strips extra file attributes for a cleaner, reproducible-ish archive.
zip -r -X "$OUT" \
  index.js \
  bin/php \
  public/index.php \
  public/router.php \
  >/dev/null

echo ">> Built $OUT"
unzip -l "$OUT"
