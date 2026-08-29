#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }
ok()    { echo -e "${GREEN}✔ $1${NC}"; }
fail()  { echo -e "${RED}✖ $1${NC}"; exit 1; }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }

# Portable in-place sed (works on BSD macOS and GNU Linux). Avoids the
# `sed -i ''` BSD-only syntax. Usage: psed 's/old/new/g' path/to/file
psed() {
    local script="$1"
    local file="$2"
    sed "$script" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

SFDX_PROJECT="$PROJECT_ROOT/sfdx-project.json"
INSTALL_PAGE="$PROJECT_ROOT/website/introduction/installation.md"

CURRENT_VERSION=$(jq -r '.packageDirectories[0].versionNumber' "$SFDX_PROJECT" | sed 's/\.NEXT$//')
PACKAGE_NAME=$(jq -r '.packageDirectories[0].package' "$SFDX_PROJECT")

echo -e "${BOLD}Async Lib Release Process${NC}"
echo -e "Package: ${BOLD}$PACKAGE_NAME${NC}"
echo -e "Current version: ${BOLD}$CURRENT_VERSION${NC}"
echo ""

# ─────────────────────────────────────────────────
# Step 1: Run all Apex tests
# ─────────────────────────────────────────────────
step "Step 1/5 — Running Apex Tests"

TEST_OUTPUT=$(sf apex run test --tests AsyncTest --code-coverage --result-format json --wait 10 --json 2>&1)
TEST_OUTCOME=$(echo "$TEST_OUTPUT" | jq -r '.result.summary.outcome')
TEST_PASS_RATE=$(echo "$TEST_OUTPUT" | jq -r '.result.summary.passRate')
TEST_COVERAGE=$(echo "$TEST_OUTPUT" | jq -r '.result.summary.orgWideCoverage')
TESTS_RAN=$(echo "$TEST_OUTPUT" | jq -r '.result.summary.testsRan')

if [ "$TEST_OUTCOME" != "Passed" ]; then
    fail "Tests failed! Pass rate: $TEST_PASS_RATE ($TESTS_RAN tests)"
fi

ok "All $TESTS_RAN tests passed ($TEST_PASS_RATE) — Org coverage: $TEST_COVERAGE"

FAILED_TESTS=$(echo "$TEST_OUTPUT" | jq -r '.result.tests[] | select(.Outcome == "Fail") | "  - \(.MethodName): \(.Message)"')
if [ -n "$FAILED_TESTS" ]; then
    echo -e "${RED}Failed tests:${NC}"
    echo "$FAILED_TESTS"
    fail "Cannot release with failing tests"
fi

# ─────────────────────────────────────────────────
# Step 2: Determine new version
# ─────────────────────────────────────────────────
step "Step 2/5 — Version Selection"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

echo "Current version: $CURRENT_VERSION"
echo ""
echo "  1) Patch  → $MAJOR.$MINOR.$((PATCH + 1))"
echo "  2) Minor  → $MAJOR.$((MINOR + 1)).0"
echo "  3) Major  → $((MAJOR + 1)).0.0"
echo "  4) Custom"
echo ""
read -p "Select version bump [1-4]: " VERSION_CHOICE

case "$VERSION_CHOICE" in
    1) NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
    2) NEW_VERSION="$MAJOR.$((MINOR + 1)).0" ;;
    3) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
    4)
        read -p "Enter custom version (e.g. 3.0.0): " NEW_VERSION
        if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            fail "Invalid version format. Must be X.Y.Z"
        fi
        ;;
    *) fail "Invalid choice" ;;
esac

echo ""
ok "New version: $NEW_VERSION"

read -p "Continue with v$NEW_VERSION? [y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    fail "Aborted by user"
fi

# Update sfdx-project.json
step "Updating sfdx-project.json"

jq --arg vn "$NEW_VERSION" --arg vnName "Async Lib $NEW_VERSION" \
    '.packageDirectories[0].versionNumber = ($vn + ".NEXT") | .packageDirectories[0].versionName = $vnName' \
    "$SFDX_PROJECT" > "${SFDX_PROJECT}.tmp" && mv "${SFDX_PROJECT}.tmp" "$SFDX_PROJECT"

ok "sfdx-project.json updated to $NEW_VERSION.NEXT"

# ─────────────────────────────────────────────────
# Step 3: Create package version
# ─────────────────────────────────────────────────
step "Step 3/5 — Creating Package Version"
echo "This may take several minutes..."

source "$PROJECT_ROOT/scripts/api-surface.sh"

REVERT_APEX_ON_EXIT=0
revert_apex_surface() {
    if [ "$REVERT_APEX_ON_EXIT" = "1" ]; then
        echo "Reverting public→global edits on Apex source files..."
        while IFS= read -r f; do
            git checkout -- "$f" 2>/dev/null || true
        done < <(api_surface_files)
    fi
}
trap revert_apex_surface EXIT
# Arm the revert BEFORE any source edits, so a mid-sed failure still triggers
# cleanup via the EXIT trap.
REVERT_APEX_ON_EXIT=1

echo "Applying public→global on API-surface classes..."
globalize_api_surface

PKG_OUTPUT=$(sf package version create \
    --package "$PACKAGE_NAME" \
    --installation-key-bypass \
    --wait 20 \
    --code-coverage \
    --json 2>&1)

PKG_STATUS=$(echo "$PKG_OUTPUT" | jq -r '.status')
if [ "$PKG_STATUS" != "0" ]; then
    echo "$PKG_OUTPUT" | jq -r '.message // .result.Error // "Unknown error"'
    fail "Package version creation failed"
fi

SUBSCRIBER_PKG_VERSION_ID=$(echo "$PKG_OUTPUT" | jq -r '.result.SubscriberPackageVersionId')
PKG_VERSION_ID=$(echo "$PKG_OUTPUT" | jq -r '.result.Id')

if [ -z "$SUBSCRIBER_PKG_VERSION_ID" ] || [ "$SUBSCRIBER_PKG_VERSION_ID" = "null" ]; then
    fail "Could not extract SubscriberPackageVersionId from package creation output"
fi

ok "Package version created!"
echo "  Subscriber Package Version ID: $SUBSCRIBER_PKG_VERSION_ID"
echo "  Package Version ID: $PKG_VERSION_ID"

# Install what was just built and run the consumer tests against it, before the
# alias, the install page or any tag exist. A version that fails here is simply
# never promoted, so aborting now costs a rebuild and nothing else.
echo "Verifying the built package in a subscriber org..."
if ! bash "$PROJECT_ROOT/scripts/verify-package-install.sh" "$SUBSCRIBER_PKG_VERSION_ID"; then
    fail "Package verification failed. Version $SUBSCRIBER_PKG_VERSION_ID must not be shipped."
fi
ok "Package verified against a subscriber org"

# Add the clean alias (e.g. "Async Lib@2.7.0") and drop the build-numbered one
# (e.g. "Async Lib@2.7.0-2") that `sf package version create` writes itself.
# The regex sweep also removes any build-numbered aliases left by earlier runs,
# so the file self-heals to one clean key per released version.
ALIAS_KEY="$PACKAGE_NAME@$NEW_VERSION"
jq --arg key "$ALIAS_KEY" --arg val "$SUBSCRIBER_PKG_VERSION_ID" \
    '.packageAliases[$key] = $val
     | .packageAliases |= with_entries(select(.key | test("@[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$") | not))' \
    "$SFDX_PROJECT" > "${SFDX_PROJECT}.tmp" && mv "${SFDX_PROJECT}.tmp" "$SFDX_PROJECT"

ok "Added alias '$ALIAS_KEY' to sfdx-project.json"

# ─────────────────────────────────────────────────
# Step 4: Update installation page
# ─────────────────────────────────────────────────
step "Step 4/5 — Updating Installation Page"

OLD_PKG_ID=$(grep -o 'p0=[0-9a-zA-Z]*' "$INSTALL_PAGE" | head -1 | sed 's/p0=//')

if [ -z "$OLD_PKG_ID" ]; then
    fail "Could not find existing package ID in installation page"
fi

psed "s/$OLD_PKG_ID/$SUBSCRIBER_PKG_VERSION_ID/g" "$INSTALL_PAGE"
psed "s/text=\"v[0-9]*\.[0-9]*\.[0-9]*\"/text=\"v$NEW_VERSION\"/" "$INSTALL_PAGE"

ok "Updated installation page"
echo "  Old package ID: $OLD_PKG_ID"
echo "  New package ID: $SUBSCRIBER_PKG_VERSION_ID"
echo "  Badge version: v$NEW_VERSION"

# ─────────────────────────────────────────────────
# Step 5: Generate release notes
# ─────────────────────────────────────────────────
step "Step 5/5 — Generating Release Notes"

LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [ -z "$LAST_TAG" ]; then
    COMMIT_LOG=$(git log --oneline --no-merges)
    CHANGED_FILES=$(git diff --stat HEAD~20 2>/dev/null || git diff --stat)
else
    COMMIT_LOG=$(git log "$LAST_TAG"..HEAD --oneline --no-merges)
    CHANGED_FILES=$(git diff "$LAST_TAG"..HEAD --stat)
fi

RELEASE_DIR="$PROJECT_ROOT/release-notes"
mkdir -p "$RELEASE_DIR"
RELEASE_FILE="$RELEASE_DIR/v$NEW_VERSION.md"

cat > "$RELEASE_FILE" << RELEASE_EOF
# GitHub Release

**Title:** v$NEW_VERSION
**Tag:** v$NEW_VERSION

---

## Description (copy below)

<!-- gh-release-start -->
# What's Changed

## New Features
<!-- Add new features here. Example: -->
<!-- ## Feature Name -->
<!-- Description of the feature with code example -->

## Improvements
<!-- Add improvements here. Use bullet points: -->
<!-- - Improvement description -->

## Bug Fixes
<!-- Add bug fixes here. Use bullet points: -->
<!-- - Fix description -->

## Documentation
<!-- Link to relevant docs -->
- [Documentation](https://async.beyondthecloud.dev)
- [Installation](https://async.beyondthecloud.dev/introduction/installation.html)

## Install

\`\`\`
https://login.salesforce.com/packaging/installPackage.apexp?p0=$SUBSCRIBER_PKG_VERSION_ID
\`\`\`
<!-- gh-release-end -->

---

# LinkedIn Post (copy below)

New Async Lib release v$NEW_VERSION! 🚀

<!-- Describe the headline change in 1-2 sentences -->

<!-- List 3-5 key highlights with ✅ emoji -->

----
Release: https://github.com/beyond-the-cloud-dev/async-lib/releases/tag/v$NEW_VERSION
Github: https://github.com/beyond-the-cloud-dev/async-lib
Documentation: https://async.beyondthecloud.dev

---

# Reference: Commits since $LAST_TAG

$COMMIT_LOG

# Reference: Changed files

$CHANGED_FILES
RELEASE_EOF

ok "Release notes template created at:"
echo "  $RELEASE_FILE"

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo ""
echo -e "${BLUE}━━━ Release Summary ━━━${NC}"
echo ""
echo -e "  Version:         ${BOLD}v$NEW_VERSION${NC}"
echo -e "  Package ID:      ${BOLD}$SUBSCRIBER_PKG_VERSION_ID${NC}"
echo -e "  Install URL:     https://login.salesforce.com/packaging/installPackage.apexp?p0=$SUBSCRIBER_PKG_VERSION_ID"
echo ""
echo -e "${YELLOW}Remaining manual steps:${NC}"
echo "  1. Review and fill in the release notes:  $RELEASE_FILE"
echo "  2. Commit changes:  git add -A && git commit -m 'Release v$NEW_VERSION'"
echo "  3. Tag the release: git tag v$NEW_VERSION"
echo "  4. Push:            git push origin main --tags"
echo "  5. Create GitHub release from tag with the notes from the file above"
echo "  6. Deploy website:  npm run docs:build"
echo ""
ok "Release v$NEW_VERSION prepared successfully!"
