#!/usr/bin/env bash
# Phase 4: full local Apex test run - same surface as CI's RunLocalTests.
# This is the authoritative gate before flipping ready_for_pr.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

org="$(sf config get target-org --json 2>/dev/null | sed -n 's/.*"value": *"\([^"]*\)".*/\1/p')"
if [ -z "$org" ]; then
  echo "ERROR: no target-org set." >&2
  exit 3
fi

# Deploy current source to ensure org reflects the working tree.
echo "── sf project deploy start (no test execution)"
sf project deploy start \
  --source-dir force-app \
  --target-org "$org" \
  --test-level NoTestRun \
  --ignore-conflicts \
  --wait 15

echo "── sf apex run test --test-level RunLocalTests"
sf apex run test \
  --target-org "$org" \
  --test-level RunLocalTests \
  --code-coverage \
  --result-format human \
  --wait 30 \
  --synchronous
