#!/usr/bin/env bash
# Phase 1: static checks. No execution, no scratch-org dependency for the JS
# parts - but Apex parser validation needs an authenticated org.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "── prettier:verify"
npm run prettier:verify

echo "── eslint"
if find force-app -type d \( -name lwc -o -name aura \) -print -quit | grep -q .; then
  npm run lint
else
  # The lint script targets **/{aura,lwc}/**; with no LWC/Aura in the lib there is
  # nothing to lint, and ESLint 9 hard-errors on a missing flat config instead of
  # no-op'ing. Skip to keep the gate scoped to lib code that actually exists.
  echo "  (no LWC/Aura sources - skipped)"
fi

echo "── headers:verify"
npm run headers:verify

echo "── pmd:verify"
npm run pmd:verify

echo "── npm test (LWC Jest)"
npm test --silent -- --passWithNoTests

org="$(sf config get target-org --json 2>/dev/null | sed -n 's/.*"value": *"\([^"]*\)".*/\1/p')"
if [ -n "$org" ]; then
  echo "── sf project deploy --dry-run (Apex parser, no commit)"
  # `deploy validate` no longer accepts NoTestRun (it must run tests to enable a
  # later quick-deploy). The static phase only needs a compile/deployability
  # check; tests run in the `full` phase. `deploy start --dry-run` validates
  # without committing and still accepts NoTestRun.
  sf project deploy start \
    --source-dir force-app \
    --target-org "$org" \
    --dry-run \
    --test-level NoTestRun \
    --wait 10
else
  echo "── sf project deploy validate: SKIPPED (no target-org set)"
  echo "    For full static coverage, authenticate a scratch org and re-run."
fi
