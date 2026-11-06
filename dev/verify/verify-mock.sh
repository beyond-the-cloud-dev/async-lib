#!/usr/bin/env bash
# Phase 2: mock-based smoke test. Runs only the AsyncTest @IsTest methods
# that exercise AsyncMock - they're the fastest behavioral signal because
# they short-circuit System.enqueueJob with mocked QueueableContexts.
#
# Heuristic: extract @IsTest methods whose body references AsyncMock or
# .mockId( on the builder.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

test_file="force-app/main/default/classes/AsyncTest.cls"
if [ ! -f "$test_file" ]; then
  echo "ERROR: $test_file not found." >&2
  exit 2
fi

# awk pass: collect @IsTest method bodies, keep names whose body matches the
# mock heuristic. Reasonable enough for a 1700-line file with consistent style.
methods=()
while IFS= read -r _method_name; do
  [ -n "$_method_name" ] && methods+=("$_method_name")
done < <(awk '
  /@IsTest/                  { in_anno=1; next }
  in_anno && /static void/   {
    if (match($0, /void *[A-Za-z_][A-Za-z0-9_]*/)) {
      s = substr($0, RSTART, RLENGTH);
      sub(/void */, "", s);
      name = s;
    }
    in_anno=0; in_method=1
    body = $0
    n_open  = gsub(/\{/, "{")
    n_close = gsub(/\}/, "}")
    depth = n_open - n_close
    if (depth <= 0 && body ~ /\{/) {
      if (body ~ /AsyncMock\.|\.mockId\(/) print name
      in_method=0; body=""
    }
    next
  }
  in_method {
    body = body "\n" $0
    n_open  = gsub(/\{/, "{")
    n_close = gsub(/\}/, "}")
    depth += n_open - n_close
    if (depth <= 0 && body ~ /\{/) {
      if (body ~ /AsyncMock\.|\.mockId\(/) print name
      in_method=0; body=""
    }
  }
' "$test_file")

if [ "${#methods[@]}" -eq 0 ]; then
  echo "No mock-using tests detected - skipping mock phase."
  exit 0
fi

org="$(sf config get target-org --json 2>/dev/null | sed -n 's/.*"value": *"\([^"]*\)".*/\1/p')"
if [ -z "$org" ]; then
  echo "ERROR: no target-org set." >&2
  exit 3
fi

# Build --tests flags. sf accepts repeated --tests of the form ClassName.methodName.
tests_args=()
for m in "${methods[@]}"; do
  tests_args+=(--tests "AsyncTest.$m")
done

echo "── Mock-using tests detected: ${#methods[@]}"
printf '   • %s\n' "${methods[@]}"

sf apex run test \
  --target-org "$org" \
  --result-format human \
  --wait 15 \
  --synchronous \
  "${tests_args[@]}"
