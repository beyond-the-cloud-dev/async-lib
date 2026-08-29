#!/bin/bash
set -euo pipefail

# The CLI's update banner goes to stderr; `2>&1` captures on --json calls feed
# it to jq, which then fails to parse. Suppress it.
export SF_SKIP_NEW_VERSION_CHECK=true

# SF_TARGET_ORG in the environment outranks `sf config set target-org` and
# silently redirects every org-less sf call. Drop it so the configured
# default org is authoritative (same guard as scripts/agent/verify.sh).
unset SF_TARGET_ORG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0
SKIPPED=0
FAILURES=()

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Run namespace integration tests for Async Lib."
    echo "Tests validate consumer-perspective behavior using btcdev.* namespace prefix."
    echo ""
    echo "Options:"
    echo "  --deploy-helpers   Deploy consumer helper classes before running tests"
    echo "  --cleanup          Clean up scheduled jobs after tests"
    echo "  --all              Deploy + test + cleanup (default)"
    echo "  --test-only        Run tests without deploy or cleanup"
    echo "  --help             Show this help"
    exit 0
}

deploy_helpers() {
    echo -e "${BLUE}=== Deploying consumer helper classes ===${NC}"
    local result
    result=$(sf project deploy start \
        --source-dir "$SCRIPT_DIR/consumer-app/force-app" \
        --json 2>&1)

    local status
    status=$(echo "$result" | jq -r '.result.status // "Unknown"')

    if [ "$status" = "Succeeded" ]; then
        echo -e "${GREEN}Helper classes deployed successfully${NC}"
        return 0
    else
        local message
        message=$(echo "$result" | jq -r '.message // .result.details.componentFailures[0].problem // "Unknown error"')
        echo -e "${RED}Helper deploy failed: $message${NC}"
        return 1
    fi
}

cleanup_jobs() {
    echo -e "${BLUE}=== Cleaning up scheduled jobs ===${NC}"
    local result
    result=$(sf apex run --file /dev/stdin --json 2>&1 <<'APEX'
Integer aborted = 0;
for (CronTrigger ct : [
    SELECT Id, CronJobDetail.Name FROM CronTrigger
    WHERE CronJobDetail.Name LIKE 'NS_Test_%'
       OR CronJobDetail.Name LIKE 'QueueableChainSchedulable%'
]) {
    System.abortJob(ct.Id);
    aborted++;
}
System.debug('Aborted ' + aborted + ' scheduled jobs');
APEX
    )

    local success
    success=$(echo "$result" | jq -r '.result.success')
    if [ "$success" = "true" ]; then
        echo -e "${GREEN}Cleanup complete${NC}"
    else
        echo -e "${YELLOW}Cleanup warning: some jobs may not have been aborted${NC}"
    fi
}

run_script() {
    local script="$1"
    local name
    name=$(basename "$script" .apex)

    echo -e "${BLUE}--- $name ---${NC}"

    local result
    result=$(sf apex run --file "$script" --json 2>&1)

    local success
    success=$(echo "$result" | jq -r '.result.success // false')

    if [ "$success" = "true" ]; then
        local has_pass
        has_pass=$(echo "$result" | jq -r '.result.logs // ""' | grep -c "PASS:" || true)
        echo -e "  ${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        local error
        error=$(echo "$result" | jq -r '
            .result.compileProblem //
            .result.exceptionMessage //
            .message //
            "Unknown error"
        ')
        echo -e "  ${RED}FAIL: $error${NC}"
        FAILED=$((FAILED + 1))
        FAILURES+=("$name: $error")
        return 1
    fi
}

run_apex_test_class() {
    local class_name="$1"
    echo -e "${BLUE}--- $class_name ---${NC}"

    local result
    result=$(sf apex run test \
        --tests "$class_name" \
        --result-format json \
        --wait 15 \
        --synchronous 2>&1)

    local outcome
    outcome=$(echo "$result" | jq -r '.result.summary.outcome // .result.summary.testsRan // "Unknown"')
    local failing
    failing=$(echo "$result" | jq -r '.result.summary.failing // 0')

    if [ "$outcome" = "Passed" ] || { [ "$failing" = "0" ] && [ "$outcome" != "Unknown" ]; }; then
        echo -e "  ${GREEN}PASS${NC}"
        PASSED=$((PASSED + 1))
        return 0
    else
        local error
        error=$(echo "$result" | jq -r '
            .result.tests[]? | select(.Outcome == "Fail") |
            "\(.FullName): \(.Message)"
        ' | head -n1)
        [ -z "$error" ] && error=$(echo "$result" | jq -r '.message // "Unknown error"')
        echo -e "  ${RED}FAIL: $error${NC}"
        FAILED=$((FAILED + 1))
        FAILURES+=("$class_name: $error")
        return 1
    fi
}

discover_deployed_test_classes() {
    local deploy_classes_dir="$SCRIPT_DIR/consumer-app/force-app/main/default/classes"
    [ -d "$deploy_classes_dir" ] || return 0
    grep -l '^@IsTest' "$deploy_classes_dir"/*.cls 2>/dev/null | while IFS= read -r f; do
        basename "$f" .cls
    done
}

run_tests() {
    echo -e "${BLUE}=== Running namespace integration tests ===${NC}"
    echo ""

    for script in "$SCRIPT_DIR"/anonymous/ns-test-*.apex; do
        [ -f "$script" ] || continue
        run_script "$script" || true
    done

    local test_classes
    test_classes=$(discover_deployed_test_classes)
    if [ -n "$test_classes" ]; then
        echo ""
        echo -e "${BLUE}=== Running deployed @IsTest classes ===${NC}"
        echo ""
        while IFS= read -r class_name; do
            [ -n "$class_name" ] && run_apex_test_class "$class_name" || true
        done <<< "$test_classes"
    fi
}

print_summary() {
    local total=$((PASSED + FAILED + SKIPPED))
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Namespace Integration Test Results${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "  Total:   $total"
    echo -e "  ${GREEN}Passed:  $PASSED${NC}"
    echo -e "  ${RED}Failed:  $FAILED${NC}"

    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failures:${NC}"
        for f in "${FAILURES[@]}"; do
            echo -e "  ${RED}✗ $f${NC}"
        done
    fi

    echo -e "${BLUE}========================================${NC}"

    if [ "$FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

MODE="all"
while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy-helpers) MODE="deploy" ;;
        --cleanup) MODE="cleanup" ;;
        --all) MODE="all" ;;
        --test-only) MODE="test-only" ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

cd "$PROJECT_ROOT"

case $MODE in
    deploy)
        deploy_helpers
        ;;
    cleanup)
        cleanup_jobs
        ;;
    test-only)
        run_tests
        print_summary
        ;;
    all)
        deploy_helpers || {
            echo -e "${YELLOW}Helper deploy failed — skipping namespace tests${NC}"
            exit 1
        }
        echo ""
        cleanup_jobs
        echo ""
        run_tests
        echo ""
        cleanup_jobs
        print_summary
        ;;
esac
