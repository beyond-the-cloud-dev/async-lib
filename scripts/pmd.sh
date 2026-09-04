#!/usr/bin/env bash
# Runs PMD over the Apex source with pmd/ruleset.xml.
#
#   npm run pmd          report only, always exits 0
#   npm run pmd:verify   exits 4 when anything is reported (the CI gate)
#
# PMD is pinned so a finding here is the same finding in CI and in a consumer
# repo that vendors this source. A PMD on PATH is only reused when it matches
# the pin; otherwise the release is downloaded once into .pmd-dist/.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PMD_VERSION="7.5.0"
RULESET="pmd/ruleset.xml"
SOURCE_DIR="force-app"
DIST_DIR=".pmd-dist"

if ! command -v java >/dev/null 2>&1; then
    echo "PMD needs Java 8+ on PATH. Install a JDK (e.g. 'brew install temurin') and re-run." >&2
    exit 1
fi

resolve_pmd() {
    if command -v pmd >/dev/null 2>&1 && pmd --version 2>/dev/null | grep -q "PMD $PMD_VERSION "; then
        command -v pmd
        return
    fi

    local home="$DIST_DIR/pmd-bin-$PMD_VERSION"
    if [ ! -x "$home/bin/pmd" ]; then
        echo "── downloading PMD $PMD_VERSION into $DIST_DIR" >&2
        mkdir -p "$DIST_DIR"
        curl -fsSL -o "$DIST_DIR/pmd.zip" \
            "https://github.com/pmd/pmd/releases/download/pmd_releases%2F$PMD_VERSION/pmd-dist-$PMD_VERSION-bin.zip"
        unzip -q -o "$DIST_DIR/pmd.zip" -d "$DIST_DIR"
        rm -f "$DIST_DIR/pmd.zip"
    fi
    echo "$home/bin/pmd"
}

"$(resolve_pmd)" check \
    --dir "$SOURCE_DIR" \
    --rulesets "$RULESET" \
    --format text \
    --no-progress \
    --cache "$DIST_DIR/analysis-cache" \
    "$@"
