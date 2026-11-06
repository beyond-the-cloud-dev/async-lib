#!/usr/bin/env bash
# Phase orchestrator for async-lib local verification.
# Usage: verify.sh {bootstrap|static|mock|targeted <Method>...|full|ns|all}
#
# Two scratch orgs, two consumer perspectives:
#   async-lib-scratch          (non-namespaced) - vendor-as-source consumer
#   async-lib-btcdev-scratch   (btcdev namespace) - package-install consumer
#
# Phases mock|targeted|full run against vanilla. Phase ns runs against the
# namespaced one. Phase static needs no org. `bootstrap` provisions both.
set -euo pipefail

# This script switches orgs per phase via `sf config set target-org`. A
# SF_TARGET_ORG in the environment outranks that config, which silently pins
# every phase to one org - the `ns` phase then runs run.sh against the
# non-namespaced org and fails with "Invalid type: btcdev.*". Drop it so the
# script's own per-phase target switching is authoritative.
unset SF_TARGET_ORG

phase="${1:-all}"; shift || true
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cd "$root"

VANILLA_ALIAS="${ASYNC_LIB_SCRATCH_ALIAS:-async-lib-scratch}"
NS_ALIAS="${ASYNC_LIB_NS_SCRATCH_ALIAS:-async-lib-btcdev-scratch}"

set_target() {
  local alias="$1"
  sf config set "target-org=$alias" >/dev/null
  echo "▸ target-org: $alias"
}

use_vanilla() {
  "$here/ensure-scratch.sh" vanilla
  set_target "$VANILLA_ALIAS"
}

use_namespaced() {
  "$here/ensure-scratch.sh" namespaced
  set_target "$NS_ALIAS"
}

run() {
  echo
  echo "▶ $*"
  "$@"
}

deploy_framework() {
  local alias="$1"
  echo
  echo "▶ sf project deploy start (framework, no tests) → $alias"
  sf project deploy start \
    --source-dir force-app \
    --target-org "$alias" \
    --test-level NoTestRun \
    --ignore-conflicts \
    --wait 15
}

case "$phase" in
  bootstrap)
    run "$here/ensure-scratch.sh" both
    ;;
  static)
    run "$here/verify-static.sh"
    ;;
  mock)
    use_vanilla
    run "$here/verify-mock.sh"
    ;;
  targeted)
    if [ "$#" -eq 0 ]; then
      echo "ERROR: targeted needs at least one test method name." >&2
      echo "       Hint: bash $here/discover-tests.sh <substring>" >&2
      exit 2
    fi
    use_vanilla
    run "$here/verify-tests-targeted.sh" "$@"
    ;;
  full)
    use_vanilla
    run "$here/verify-tests-full.sh"
    ;;
  ns)
    use_namespaced
    deploy_framework "$NS_ALIAS"
    run "$root/dev/package-tests/run.sh"
    ;;
  all)
    run "$here/ensure-scratch.sh" both
    run "$here/verify-static.sh"
    use_vanilla
    run "$here/verify-mock.sh"
    if [ -n "${TARGETED_TESTS:-}" ]; then
      # shellcheck disable=SC2086
      run "$here/verify-tests-targeted.sh" $TARGETED_TESTS
    fi
    run "$here/verify-tests-full.sh"
    use_namespaced
    deploy_framework "$NS_ALIAS"
    run "$root/dev/package-tests/run.sh"
    ;;
  *)
    echo "Usage: verify.sh {bootstrap|static|mock|targeted <Method>...|full|ns|all}" >&2
    echo "  TARGETED_TESTS env var seeds 'all' phase with specific methods." >&2
    exit 2
    ;;
esac

echo
echo "✓ verify.sh: phase '$phase' passed"
