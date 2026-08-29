#!/bin/bash
set -e

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: Working tree is not clean. Commit or stash changes before running this script."
    exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/api-surface.sh"

PACKAGE_CREATED=false
cleanup() {
    if [ "$PACKAGE_CREATED" = true ]; then
        echo "Staging sfdx-project.json with new version alias..."
        git add sfdx-project.json
        echo "Reverting Apex changes..."
        git checkout -- .
    else
        echo "Package creation failed. Reverting all changes..."
        git checkout -- .
    fi
}
trap cleanup EXIT

echo "Adding global modifiers to API surface classes..."
globalize_api_surface

echo "Creating unlocked package version..."
sf package version create \
    --package "Async Lib" \
    --definition-file ./config/project-scratch-def.json \
    --installation-key-bypass \
    --code-coverage \
    --wait 50 \
    --json \
    "$@"

PACKAGE_CREATED=true
echo "Package version created successfully."
