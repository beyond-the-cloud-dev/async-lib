#!/bin/bash
set -e

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: Working tree is not clean. Commit or stash changes before running this script."
    exit 1
fi

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

TARGET_FILES=(
    "force-app/main/default/classes/Async.cls"
    "force-app/main/default/classes/queue/QueueableJob.cls"
    "force-app/main/default/classes/queue/QueueableBuilder.cls"
    "force-app/main/default/classes/queue/Backoff.cls"
    "force-app/main/default/classes/batch/BatchableBuilder.cls"
    "force-app/main/default/classes/cleanup/AsyncResultCleanupBatch.cls"
    "force-app/main/default/classes/schedule/SchedulableBuilder.cls"
    "force-app/main/default/classes/schedule/CronBuilder.cls"
    "force-app/main/default/classes/mocks/AsyncMock.cls"
)

# sed -i.bak is portable across GNU (Linux/CI) and BSD (macOS) sed; the bare
# `sed -i ''` form only works on BSD and breaks on GNU.
sedi() {
    local expr="$1" file="$2"
    sed -i.bak "$expr" "$file"
    rm -f "$file.bak"
}

echo "Adding global modifiers to API surface classes..."
for file in "${TARGET_FILES[@]}"; do
    sedi 's/public /global /g' "$file"
done

echo "Reverting internal-type references back to public..."
sedi 's/global QueueableManager\.EnqueueType/public QueueableManager.EnqueueType/g' \
    "force-app/main/default/classes/Async.cls"
sedi 's/global QueueableChainState setEnqueueType/public QueueableChainState setEnqueueType/g' \
    "force-app/main/default/classes/Async.cls"
sedi 's/global void enqueue(QueueableChain chain)/public void enqueue(QueueableChain chain)/g' \
    "force-app/main/default/classes/queue/QueueableJob.cls"

# The blanket rename rewrites the "public override ..." guidance string inside
# QueueableJob.cloneJob(); restore it so consumers get correct override syntax.
sedi 's/global override QueueableJob cloneForDeepCopy/public override QueueableJob cloneForDeepCopy/g' \
    "force-app/main/default/classes/queue/QueueableJob.cls"

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
