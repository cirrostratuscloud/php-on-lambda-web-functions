#!/usr/bin/env bash
#
# Tear down the PHP-on-Web-Functions PoC.
#
# By default this deletes ONLY the Web Function (which also removes its
# endpoints and revisions). The `aws lambda-web delete-web-function` command
# intentionally leaves behind the resources that `deploy` created or reused:
#   - the default IAM execution role   (awscli-lambdaweb-<name>)
#   - the deployment objects in S3      (s3://<bucket>/lambda-web/<name>/...)
#   - the CloudWatch Logs log group(s)
#
# Those can be swept too with opt-in flags below. The S3 bucket itself is NOT
# deleted: it's the shared default bucket for ALL lambda-web deployments in the
# account+region, so removing it could break other functions.
#
# Usage:
#   scripts/cleanup.sh                 # delete the Web Function only (prompts)
#   scripts/cleanup.sh --all           # also delete role, S3 objects, log group
#   scripts/cleanup.sh --role          # also delete the default execution role
#   scripts/cleanup.sh --s3            # also delete the deployment objects in S3
#   scripts/cleanup.sh --logs          # also delete the CloudWatch log group
#   scripts/cleanup.sh --dry-run       # print what would happen, change nothing
#   scripts/cleanup.sh --yes           # skip confirmation prompts (for CI)
#
# Env overrides:
#   NAME     Web Function name   (default: php-web-poc)
#   REGION   AWS region          (otherwise your CLI default)
#   BUCKET   S3 bucket for --s3  (otherwise derived from account+region)
#   ROLE     IAM role for --role (default: awscli-lambdaweb-<NAME>)
#
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="${NAME:-php-web-poc}"

DO_ROLE=0
DO_S3=0
DO_LOGS=0
DRY_RUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --all)     DO_ROLE=1; DO_S3=1; DO_LOGS=1 ;;
    --role)    DO_ROLE=1 ;;
    --s3)      DO_S3=1 ;;
    --logs)    DO_LOGS=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    -h|--help)
      sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

REGION_ARG=()
if [ -n "${REGION:-}" ]; then
  REGION_ARG=(--region "$REGION")
fi
# Helper that expands the region arg safely under `set -u` (bash 3.2 friendly).
awsx() { aws "$@" ${REGION_ARG[@]+"${REGION_ARG[@]}"}; }

# `run` executes a command, or just prints it in dry-run mode.
run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '   [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

confirm() {
  # Returns 0 to proceed, 1 to skip. Auto-yes under --yes or --dry-run.
  local prompt="$1"
  if [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve account + region for name derivation / messaging.
ACCOUNT_ID="$(awsx sts get-caller-identity --query Account --output text 2>/dev/null || echo '')"
EFF_REGION="${REGION:-$(aws configure get region 2>/dev/null || echo '')}"
ROLE_NAME="${ROLE:-awscli-lambdaweb-${NAME}}"

echo "Cleanup target"
echo "  Web Function : ${NAME}"
echo "  Region       : ${EFF_REGION:-<cli default>}"
echo "  Account      : ${ACCOUNT_ID:-<unknown>}"
echo "  Dry run      : $([ "$DRY_RUN" -eq 1 ] && echo yes || echo no)"
echo

# ---------------------------------------------------------------------------
# 1) Delete the Web Function (also removes endpoints + revisions).
# ---------------------------------------------------------------------------
if awsx lambda-web get-web-function --function-name "$NAME" >/dev/null 2>&1; then
  if confirm ">> Delete Web Function '${NAME}' (and its endpoints + revisions)?"; then
    run awsx lambda-web delete-web-function --function-name "$NAME"
    echo "   Web Function deletion requested."
  else
    echo "   Skipped Web Function deletion."
  fi
else
  echo ">> Web Function '${NAME}' not found (already deleted?). Skipping."
fi

# ---------------------------------------------------------------------------
# 2) Optional: delete the default IAM execution role.
# ---------------------------------------------------------------------------
if [ "$DO_ROLE" -eq 1 ]; then
  echo
  if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
    if confirm ">> Delete IAM role '${ROLE_NAME}'? (only if nothing else uses it)"; then
      # Inline policies must be removed before the role can be deleted.
      POLICIES="$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null || echo '')"
      for p in $POLICIES; do
        run aws iam delete-role-policy --role-name "$ROLE_NAME" --policy-name "$p"
      done
      # Detach any managed policies too.
      ATTACHED="$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo '')"
      for a in $ATTACHED; do
        run aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$a"
      done
      run aws iam delete-role --role-name "$ROLE_NAME"
      echo "   IAM role deleted."
    else
      echo "   Skipped IAM role deletion."
    fi
  else
    echo ">> IAM role '${ROLE_NAME}' not found. Skipping."
  fi
fi

# ---------------------------------------------------------------------------
# 3) Optional: delete the deployment objects in S3 (NOT the bucket).
# ---------------------------------------------------------------------------
if [ "$DO_S3" -eq 1 ]; then
  echo
  BUCKET_NAME="${BUCKET:-}"
  if [ -z "$BUCKET_NAME" ] && [ -n "$ACCOUNT_ID" ] && [ -n "$EFF_REGION" ]; then
    # Default managed bucket name documented as:
    #   awscli-lambdaweb-<account-id>-<region>-an
    BUCKET_NAME="awscli-lambdaweb-${ACCOUNT_ID}-${EFF_REGION}-an"
  fi

  if [ -z "$BUCKET_NAME" ]; then
    echo ">> Could not determine S3 bucket (set BUCKET=... to target it). Skipping S3."
  else
    PREFIX="lambda-web/${NAME}/"
    echo ">> S3 cleanup target: s3://${BUCKET_NAME}/${PREFIX}"
    if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
      if confirm ">> Delete all deployment objects under s3://${BUCKET_NAME}/${PREFIX} (incl. versions)?"; then
        # The managed bucket is versioned, so plain `s3 rm` leaves noncurrent
        # versions behind. Remove all versions + delete markers under the prefix.
        delete_versions() {
          local vtype="$1" # Versions | DeleteMarkers
          local json
          json="$(aws s3api list-object-versions \
                    --bucket "$BUCKET_NAME" --prefix "$PREFIX" \
                    --query "${vtype}[].{Key:Key,VersionId:VersionId}" \
                    --output json 2>/dev/null || echo '[]')"
          [ "$json" = "null" ] && json='[]'
          # Iterate without jq: use python for safe JSON parsing.
          echo "$json" | python3 -c '
import sys, json
items = json.load(sys.stdin) or []
for it in items:
    print(it["Key"] + "\t" + it["VersionId"])
' | while IFS=$'\t' read -r key vid; do
            [ -z "$key" ] && continue
            run aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$vid"
          done
        }
        delete_versions Versions
        delete_versions DeleteMarkers
        echo "   S3 deployment objects removed (bucket itself left intact)."
      else
        echo "   Skipped S3 object deletion."
      fi
    else
      echo ">> Bucket '${BUCKET_NAME}' not found or no access. Skipping S3."
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 4) Optional: delete the CloudWatch log group.
# ---------------------------------------------------------------------------
if [ "$DO_LOGS" -eq 1 ]; then
  echo
  # Web Function log groups live under /aws/lambda-web/<name>. We delete any
  # log group that starts with that prefix.
  LOG_PREFIX="/aws/lambda-web/${NAME}"
  GROUPS="$(awsx logs describe-log-groups --log-group-name-prefix "$LOG_PREFIX" \
              --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo '')"
  if [ -z "$GROUPS" ]; then
    echo ">> No log groups found under '${LOG_PREFIX}'. Skipping."
  else
    for g in $GROUPS; do
      if confirm ">> Delete CloudWatch log group '${g}'?"; then
        run awsx logs delete-log-group --log-group-name "$g"
        echo "   Deleted ${g}."
      else
        echo "   Skipped ${g}."
      fi
    done
  fi
fi

echo
echo ">> Cleanup complete."
if [ "$DO_ROLE" -eq 0 ] || [ "$DO_S3" -eq 0 ] || [ "$DO_LOGS" -eq 0 ]; then
  echo "   Note: leftover defaults are kept unless you pass --all (or --role/--s3/--logs)."
  echo "   The shared managed S3 bucket is never deleted by this script."
fi
