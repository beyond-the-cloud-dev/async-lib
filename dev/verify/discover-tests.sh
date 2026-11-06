#!/usr/bin/env bash
# Lists every @IsTest method in AsyncTest.cls. Optional first arg filters by
# substring (case-insensitive grep on method name).
#
#   discover-tests.sh                # all methods, one per line
#   discover-tests.sh chain          # only methods whose name contains "chain"
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

test_file="force-app/main/default/classes/AsyncTest.cls"
filter="${1:-}"

awk '
  /@IsTest/                { in_anno=1; next }
  in_anno && /static void/ {
    if (match($0, /void *[A-Za-z_][A-Za-z0-9_]*/)) {
      s = substr($0, RSTART, RLENGTH);
      sub(/void */, "", s);
      print s;
    }
    in_anno=0
  }
' "$test_file" | {
  if [ -n "$filter" ]; then
    grep -i -- "$filter"
  else
    cat
  fi
}
