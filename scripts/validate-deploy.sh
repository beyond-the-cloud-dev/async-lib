#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

error() { echo -e "  ${RED}ERROR: $1${NC}"; ERRORS=$((ERRORS + 1)); }
warn()  { echo -e "  ${YELLOW}WARN:  $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
pass()  { echo -e "  ${GREEN}OK:    $1${NC}"; }

echo -e "${BLUE}=== Pre-deploy Validation ===${NC}"
echo ""

echo -e "${BLUE}1. API Version Check (must be 65.0)${NC}"
BAD_API=$(grep -rl '<apiVersion>' force-app/ --include='*-meta.xml' | while read f; do
    ver=$(grep -o '<apiVersion>[^<]*' "$f" | sed 's/<apiVersion>//')
    if [ "$ver" != "65.0" ]; then
        echo "  $f: $ver"
    fi
done)
if [ -z "$BAD_API" ]; then
    pass "All metadata files use API version 65.0"
else
    error "Files with wrong API version:"
    echo "$BAD_API"
fi

echo ""
echo -e "${BLUE}2. SOQL/DML in Loop Detection${NC}"
SOQL_IN_LOOP=false
for cls in $(find force-app/main/default/classes -name '*.cls' ! -name '*Test*'); do
    matches=$(grep -n 'for\s*(.*)\s*{' "$cls" 2>/dev/null | while read line; do
        linenum=$(echo "$line" | cut -d: -f1)
        endline=$((linenum + 30))
        sed -n "${linenum},${endline}p" "$cls" | grep -l '\[SELECT\|Database\.\(insert\|update\|delete\|upsert\)' 2>/dev/null && echo "$cls:$linenum"
    done || true)
    if [ -n "$matches" ]; then
        warn "Potential SOQL/DML in loop: $cls"
        SOQL_IN_LOOP=true
    fi
done
if [ "$SOQL_IN_LOOP" = false ]; then
    pass "No obvious SOQL/DML in loops detected"
fi

echo ""
echo -e "${BLUE}3. API Surface Change Detection${NC}"
API_FILE="$PROJECT_ROOT/api-surface.txt"
if [ -f "$API_FILE" ]; then
    TEMP_API=$(mktemp)
    "$PROJECT_ROOT/scripts/generate-api-surface.sh" "$TEMP_API" > /dev/null 2>&1
    if diff -q "$API_FILE" "$TEMP_API" > /dev/null 2>&1; then
        pass "API surface unchanged"
    else
        warn "API surface has changed! Diff:"
        diff "$API_FILE" "$TEMP_API" || true
        echo ""
        echo -e "  ${YELLOW}Run: ./scripts/generate-api-surface.sh to update${NC}"
    fi
    rm -f "$TEMP_API"
else
    warn "No api-surface.txt found — run ./scripts/generate-api-surface.sh to create baseline"
fi

echo ""
echo -e "${BLUE}4. Sharing Model Check${NC}"
WITHOUT_SHARING=$(grep -rl 'without sharing' force-app/main/default/classes/ --include='*.cls' | grep -v 'Test' || true)
if [ -z "$WITHOUT_SHARING" ]; then
    pass "No 'without sharing' classes found"
else
    for f in $WITHOUT_SHARING; do
        warn "Uses 'without sharing': $(basename $f) — verify this is intentional"
    done
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "  Errors:   $ERRORS"
echo -e "  Warnings: $WARNINGS"
echo -e "${BLUE}========================================${NC}"

if [ "$ERRORS" -gt 0 ]; then
    exit 1
fi
exit 0
