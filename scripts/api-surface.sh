#!/bin/bash
# Single source of truth for the `public` -> `global` rewrite applied to Apex
# source before a package version is built.
#
# Source this, do not execute it:
#     source scripts/api-surface.sh
#     globalize_api_surface        # rewrite, then revert internal wiring
#     api_surface_files            # prints the touched files, one per line
#
# Both scripts/create-unlocked-package-version.sh and scripts/release.sh
# use it. They used to keep separate copies, which drifted: the chunk classes were
# added to one and not the other, so a release would have shipped ChunkJob and
# friends as `public` and no subscriber could have used Async.chunk.

API_SURFACE_FILES=(
    "force-app/main/default/classes/Async.cls"
    "force-app/main/default/classes/queue/QueueableJob.cls"
    "force-app/main/default/classes/queue/QueueableBuilder.cls"
    "force-app/main/default/classes/queue/ChunkSource.cls"
    "force-app/main/default/classes/queue/ChunkJob.cls"
    "force-app/main/default/classes/queue/ChunkBuilder.cls"
    "force-app/main/default/classes/queue/Backoff.cls"
    "force-app/main/default/classes/batch/BatchableBuilder.cls"
    "force-app/main/default/classes/cleanup/AsyncResultCleanupBatch.cls"
    "force-app/main/default/classes/schedule/SchedulableBuilder.cls"
    "force-app/main/default/classes/schedule/CronBuilder.cls"
    "force-app/main/default/classes/mocks/AsyncMock.cls"
)

api_surface_files() {
    printf '%s\n' "${API_SURFACE_FILES[@]}"
}

# sed -i.bak is portable across GNU (Linux/CI) and BSD (macOS) sed; the bare
# `sed -i ''` form only works on BSD and breaks on GNU.
api_surface_sed() {
    local expr="$1" file="$2"
    sed -i.bak "$expr" "$file"
    rm -f "$file.bak"
}

globalize_api_surface() {
    local file
    for file in "${API_SURFACE_FILES[@]}"; do
        if [ ! -f "$file" ]; then
            echo "Error: API surface file not found: $file" >&2
            return 1
        fi
        api_surface_sed 's/public /global /g' "$file"
    done

    revert_internal_wiring
}

# The blanket rename also hits members that must stay namespace-internal. Anything
# returning or accepting a type that is not itself global has to come back, or the
# package will not compile.
revert_internal_wiring() {
    api_surface_sed 's/global QueueableManager\.EnqueueType/public QueueableManager.EnqueueType/g' \
        "force-app/main/default/classes/Async.cls"
    api_surface_sed 's/global QueueableChainState setEnqueueType/public QueueableChainState setEnqueueType/g' \
        "force-app/main/default/classes/Async.cls"
    api_surface_sed 's/global void enqueue(QueueableChain chain)/public void enqueue(QueueableChain chain)/g' \
        "force-app/main/default/classes/queue/QueueableJob.cls"

    api_surface_sed 's/global ChunkRun getRun(/public ChunkRun getRun(/g' \
        "force-app/main/default/classes/queue/ChunkJob.cls"
    api_surface_sed 's/global ChunkJob nextPageOrNull(/public ChunkJob nextPageOrNull(/g' \
        "force-app/main/default/classes/queue/ChunkJob.cls"

    api_surface_sed 's/global ChunkBuilder(ChunkJob job, ChunkSource source, String lastChainedCustomJobId)/public ChunkBuilder(ChunkJob job, ChunkSource source, String lastChainedCustomJobId)/g' \
        "force-app/main/default/classes/queue/ChunkBuilder.cls"
    api_surface_sed 's/global QueueableBuilder(QueueableJob job, String lastChainedCustomJobId)/public QueueableBuilder(QueueableJob job, String lastChainedCustomJobId)/g' \
        "force-app/main/default/classes/queue/QueueableBuilder.cls"

    # The blanket rename rewrites the "public override ..." guidance string inside
    # QueueableJob.cloneJob(); restore it so consumers get correct override syntax.
    api_surface_sed 's/global override QueueableJob cloneForDeepCopy/public override QueueableJob cloneForDeepCopy/g' \
        "force-app/main/default/classes/queue/QueueableJob.cls"
}
