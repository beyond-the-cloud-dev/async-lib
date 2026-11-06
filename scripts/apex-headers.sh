#!/bin/bash
# The license header and version line every Apex file starts with, plus the VERSION the
# Async Jobs card shows in its footer.
#     scripts/apex-headers.sh check        fail on a missing header or a version other than sfdx-project.json's
#     scripts/apex-headers.sh bump 3.1.0   rewrite the version line in every file
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COPYRIGHT_LINE=' * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)'
LICENSE_LINE=' * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)'
VERSION_LINE_NUMBER=5

apex_files() {
    git ls-files --cached --others --exclude-standard '*.cls' '*.trigger'
}

project_version() {
    jq -r '.packageDirectories[0].versionNumber' sfdx-project.json | sed 's/\.NEXT$//'
}

LWC_VERSION_FILE='force-app/main/default/lwc/asyncJobTimelineModel/asyncJobTimelineModel.js'

check() {
    local expected="v$(project_version)"
    local failures=0 file
    if ! grep -q "^export const VERSION = '$(project_version)';" "$LWC_VERSION_FILE"; then
        echo "Expected VERSION = '$(project_version)' in $LWC_VERSION_FILE (the card footer shows it)" >&2
        failures=$((failures + 1))
    fi
    while IFS= read -r file; do
        if [ "$(sed -n 1p "$file")" != '/**' ] ||
            [ "$(sed -n 2p "$file")" != "$COPYRIGHT_LINE" ] ||
            [ "$(sed -n 3p "$file")" != "$LICENSE_LINE" ]; then
            echo "Missing or malformed license header: $file" >&2
            failures=$((failures + 1))
        elif [ "$(sed -n "${VERSION_LINE_NUMBER}p" "$file")" != " * $expected" ]; then
            echo "Expected '$expected' on line $VERSION_LINE_NUMBER: $file" >&2
            failures=$((failures + 1))
        fi
    done < <(apex_files)

    if [ "$failures" -gt 0 ]; then
        echo "$failures Apex file(s) need the header. Copy it from any class, or run: scripts/apex-headers.sh bump $(project_version)" >&2
        return 1
    fi
    echo "All Apex headers carry $expected."
}

bump() {
    local version="$1" file
    if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Version must be X.Y.Z, got '$version'" >&2
        return 1
    fi
    while IFS= read -r file; do
        sed -i.bak "${VERSION_LINE_NUMBER}s/^ \* v[0-9]*\.[0-9]*\.[0-9]*$/ * v$version/" "$file"
        rm -f "$file.bak"
    done < <(apex_files)
    sed -i.bak "s/^export const VERSION = '[0-9]*\.[0-9]*\.[0-9]*';/export const VERSION = '$version';/" "$LWC_VERSION_FILE"
    rm -f "$LWC_VERSION_FILE.bak"
}

case "${1:-}" in
    check) check ;;
    bump) bump "${2:?usage: apex-headers.sh bump X.Y.Z}" ;;
    *)
        echo "usage: apex-headers.sh check | bump X.Y.Z" >&2
        exit 2
        ;;
esac
