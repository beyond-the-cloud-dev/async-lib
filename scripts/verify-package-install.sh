#!/bin/bash
# Install a built package version into a throwaway org and run the consumer test
# classes against it.
#
#     verify-package-install.sh 04t...
#
# This is the only check that exercises what a subscriber actually receives. The
# ns lane deploys *source* into a namespaced org, so it never runs the
# public -> global rewrite; source-level tests never touch it either. A class left
# out of the rewrite list compiles fine everywhere except in a subscriber org.
set -euo pipefail

export SF_SKIP_NEW_VERSION_CHECK=true
unset SF_TARGET_ORG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

PACKAGE_VERSION_ID="${1:-}"
DEVHUB="${ASYNC_LIB_DEVHUB:-}"
ORG_ALIAS="async-lib-pkgverify-$$"
ORG_CREATED=false

if [ -z "$PACKAGE_VERSION_ID" ]; then
    echo -e "${RED}Usage: verify-package-install.sh <04t package version id>${NC}" >&2
    exit 1
fi

cleanup() {
    if [ "$ORG_CREATED" = true ]; then
        echo -e "${BLUE}Deleting scratch org $ORG_ALIAS${NC}"
        sf org delete scratch --target-org "$ORG_ALIAS" --no-prompt >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

devhub_arg=()
[ -n "$DEVHUB" ] && devhub_arg=(--target-dev-hub "$DEVHUB")

echo -e "${BLUE}=== Creating scratch org without a namespace ===${NC}"
sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "$ORG_ALIAS" \
    --duration-days 1 \
    --no-namespace \
    --no-ancestors \
    --wait 20 \
    "${devhub_arg[@]}" >/dev/null
ORG_CREATED=true
echo -e "${GREEN}Created $ORG_ALIAS${NC}"

echo -e "${BLUE}=== Installing $PACKAGE_VERSION_ID ===${NC}"
sf package install \
    --package "$PACKAGE_VERSION_ID" \
    --target-org "$ORG_ALIAS" \
    --installation-key-bypass \
    --wait 20 \
    --no-prompt >/dev/null
echo -e "${GREEN}Installed${NC}"

echo -e "${BLUE}=== Deploying consumer classes ===${NC}"
sf project deploy start \
    --source-dir "$PROJECT_ROOT/package-tests/consumer-app/force-app" \
    --target-org "$ORG_ALIAS" \
    --wait 20 >/dev/null
echo -e "${GREEN}Deployed${NC}"

TEST_CLASSES=$(grep -l '^@IsTest' "$PROJECT_ROOT"/package-tests/consumer-app/force-app/main/default/classes/*.cls |
    while IFS= read -r f; do basename "$f" .cls; done)

if [ -z "$TEST_CLASSES" ]; then
    echo -e "${RED}No consumer test classes found. Nothing would be verified.${NC}" >&2
    exit 1
fi

class_args=()
while IFS= read -r c; do class_args+=(--class-names "$c"); done <<<"$TEST_CLASSES"

echo -e "${BLUE}=== Running consumer tests against the installed package ===${NC}"
echo "$TEST_CLASSES" | sed 's/^/  /'

RESULT=$(sf apex run test \
    --target-org "$ORG_ALIAS" \
    "${class_args[@]}" \
    --synchronous \
    --wait 30 \
    --result-format human 2>&1) || true

echo "$RESULT" | sed -n '/TEST NAME/,/Test Total/p'

if echo "$RESULT" | grep -qE "^Outcome[[:space:]]+Passed|Pass Rate[[:space:]]+100%"; then
    echo -e "${GREEN}Package verified: consumer tests pass against the installed package.${NC}"
    exit 0
fi

echo -e "${RED}Package verification FAILED.${NC}" >&2
echo -e "${RED}Do not promote or ship this version.${NC}" >&2
echo "$RESULT" | tail -40 >&2
exit 1
