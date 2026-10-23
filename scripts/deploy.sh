#!/usr/bin/env bash
#
# Deploy the PHP-on-Web-Functions PoC using the `aws lambda-web` CLI.
#
# This uses the high-level `deploy` command, which zips the --code directory,
# uploads it to a managed S3 bucket, creates the Web Function + revision, and
# creates/updates a HomeRegion endpoint. On first run it creates a default
# execution role and bucket for you.
#
# Requirements:
#   - AWS CLI v2 with the `lambda-web` commands (run: aws lambda-web help)
#   - credentials + region configured
#   - bin/php present (run scripts/fetch-php.sh first)
#
# Env overrides:
#   NAME           Web Function name (default: php-web-poc)
#   ENDPOINT_NAME  endpoint name (default: dev)
#   REGION         AWS region (otherwise your CLI default)
#
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="${NAME:-php-web-poc}"
ENDPOINT_NAME="${ENDPOINT_NAME:-dev}"
REGION_ARG=()
if [ -n "${REGION:-}" ]; then
  REGION_ARG=(--region "$REGION")
fi

if [ ! -f bin/php ]; then
  echo "ERROR: bin/php missing. Run: scripts/fetch-php.sh" >&2
  exit 1
fi

# Sanity check: the deploy command must exist in this CLI build.
if ! aws lambda-web help >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: `aws lambda-web` is not available in your AWS CLI.
Update to a CLI v2 release that includes Web Functions:
  aws --version
  aws update           # if installed via the official installer/script
Then retry.
EOF
  exit 1
fi

echo ">> Deploying Web Function '$NAME' (endpoint '$ENDPOINT_NAME')"

# --create confirms resource creation non-interactively (role/bucket/function).
# --code . zips THIS directory. .lambdaignore (see repo) keeps the zip lean.
aws lambda-web deploy \
  --name "$NAME" \
  --code . \
  --endpoint-name "$ENDPOINT_NAME" \
  --create \
  ${REGION_ARG[@]+"${REGION_ARG[@]}"}

echo
echo ">> Fetching endpoint URL..."
aws lambda-web get-web-function-endpoint \
  --function-name "$NAME" \
  --endpoint-name "$ENDPOINT_NAME" \
  ${REGION_ARG[@]+"${REGION_ARG[@]}"}

cat <<EOF

>> Done. Test it with:
     curl https://<domainName-from-above>/
   You should get JSON with "php_version" and php_sapi":"cli-server",
   which proves PHP executed inside the Web Function.
EOF
