#!/bin/bash
set -e

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: Working tree is not clean. Commit or stash changes before running this script."
    exit 1
fi

trap 'echo "Reverting Apex changes..."; git checkout -- .' EXIT

TARGET_FILES=(
    "force-app/main/default/classes/Async.cls"
    "force-app/main/default/classes/queue/QueueableJob.cls"
    "force-app/main/default/classes/queue/QueueableBuilder.cls"
    "force-app/main/default/classes/batch/BatchableBuilder.cls"
    "force-app/main/default/classes/schedule/SchedulableBuilder.cls"
    "force-app/main/default/classes/schedule/CronBuilder.cls"
    "force-app/main/default/classes/mocks/AsyncMock.cls"
)

echo "Adding global modifiers to API surface classes..."
for file in "${TARGET_FILES[@]}"; do
    sed -i '' 's/public /global /g' "$file"
done

echo "Reverting internal-type references back to public..."
sed -i '' 's/global QueueableManager\.EnqueueType/public QueueableManager.EnqueueType/g' \
    "force-app/main/default/classes/Async.cls"
sed -i '' 's/global QueueableChainState setEnqueueType/public QueueableChainState setEnqueueType/g' \
    "force-app/main/default/classes/Async.cls"
sed -i '' 's/global void enqueue(QueueableChain chain)/public void enqueue(QueueableChain chain)/g' \
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

echo "Package version created successfully."
