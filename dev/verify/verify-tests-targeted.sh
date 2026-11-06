#!/usr/bin/env bash
# Phase 3: run a specific subset of @IsTest methods.
# Usage: verify-tests-targeted.sh Method1 [Method2 ...]
#
# Names may be bare ("shouldChainXyz") or qualified ("AsyncTest.shouldChainXyz").
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ "$#" -eq 0 ]; then
  echo "Usage: verify-tests-targeted.sh Method1 [Method2 ...]" >&2
  exit 2
fi

org="$(sf config get target-org --json 2>/dev/null | sed -n 's/.*"value": *"\([^"]*\)".*/\1/p')"
if [ -z "$org" ]; then
  echo "ERROR: no target-org set." >&2
  exit 3
fi

tests_args=()
for raw in "$@"; do
  case "$raw" in
    *.*) qualified="$raw" ;;
    *)   qualified="AsyncTest.$raw" ;;
  esac
  tests_args+=(--tests "$qualified")
done

echo "── Targeted test methods:"
printf '   • %s\n' "${tests_args[@]}" | grep -v '^   • --tests' || true

sf apex run test \
  --target-org "$org" \
  --result-format human \
  --code-coverage \
  --wait 20 \
  --synchronous \
  "${tests_args[@]}"
