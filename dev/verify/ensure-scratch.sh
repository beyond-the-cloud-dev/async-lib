#!/usr/bin/env bash
# Ensure async-lib agent scratches exist. Idempotent.
#
# Usage:
#   ensure-scratch.sh                 # ensures both scratches
#   ensure-scratch.sh vanilla         # only the non-namespaced one
#   ensure-scratch.sh namespaced      # only the btcdev-namespaced one
#
# Scratches:
#   async-lib-scratch          (non-namespaced) - vendor-as-source consumer view
#   async-lib-btcdev-scratch   (btcdev namespace) - package-install consumer view
#
# Env overrides:
#   ASYNC_LIB_DEVHUB              (default: the target-dev-hub set in sf config)
#   ASYNC_LIB_SCRATCH_DAYS        (default: 30)
#   ASYNC_LIB_SCRATCH_ALIAS       (default: async-lib-scratch - overrides vanilla alias)
#   ASYNC_LIB_NS_SCRATCH_ALIAS    (default: async-lib-btcdev-scratch - overrides namespaced alias)
set -euo pipefail

# The CLI's update banner goes to stderr; `2>&1` captures on --json calls feed
# it to jq, which then fails to parse. Suppress it.
export SF_SKIP_NEW_VERSION_CHECK=true

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
cd "$root"

devhub="${ASYNC_LIB_DEVHUB:-}"
days="${ASYNC_LIB_SCRATCH_DAYS:-30}"
vanilla_alias="${ASYNC_LIB_SCRATCH_ALIAS:-async-lib-scratch}"
ns_alias="${ASYNC_LIB_NS_SCRATCH_ALIAS:-async-lib-btcdev-scratch}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required." >&2
  exit 1
fi

# ensure_one <alias> <type>     type ∈ {vanilla, namespaced}
ensure_one() {
  local alias="$1"
  local type="$2"
  local org_json entry is_expired exp needs_create=0 ns

  org_json="$(sf org list --json 2>/dev/null || true)"
  entry="$(echo "$org_json" | jq -c --arg a "$alias" '.result.scratchOrgs[]? | select(.alias == $a)' | head -n1)"

  if [ -z "$entry" ]; then
    # A scratch authed via `sf org login web` without local devhub auth is
    # listed under .result.other, not .result.scratchOrgs. Accept it when
    # reachable instead of recreating; namespace comes from the org itself
    # because org display carries no namespace for such auths.
    if sf org display --target-org "$alias" --json >/dev/null 2>&1; then
      ns="$(sf data query --query "SELECT NamespacePrefix FROM Organization" \
        --target-org "$alias" --json 2>/dev/null \
        | jq -r '.result.records[0].NamespacePrefix // empty')"
      if [ "$type" = "vanilla" ] && [ -n "$ns" ]; then
        echo "ERROR: [$type] '$alias' is reachable but has namespace '$ns'." >&2
        echo "       Cannot recreate without devhub auth. Re-auth the correct org." >&2
        exit 1
      fi
      if [ "$type" = "namespaced" ] && [ "$ns" != "btcdev" ]; then
        echo "ERROR: [$type] '$alias' is reachable but namespace is '${ns:-none}', expected 'btcdev'." >&2
        echo "       Cannot recreate without devhub auth. Re-auth the correct org." >&2
        exit 1
      fi
      echo "▸ [$type] '$alias' healthy via direct auth (namespace=${ns:-none}, no devhub link)"
      return 0
    fi
    echo "▸ [$type] '$alias' not found locally - will create"
    needs_create=1
  else
    is_expired="$(echo "$entry" | jq -r '.isExpired')"
    exp="$(echo "$entry" | jq -r '.expirationDate // "unknown"')"
    if [ "$is_expired" = "true" ]; then
      echo "▸ [$type] '$alias' expired ($exp) - logging out and recreating"
      sf org logout --target-org "$alias" --no-prompt >/dev/null 2>&1 || true
      needs_create=1
    else
      # Verify namespace matches the type
      ns="$(sf org display --target-org "$alias" --json 2>/dev/null | jq -r '.result.namespace // empty')"
      if [ "$type" = "vanilla" ] && [ -n "$ns" ]; then
        echo "▸ [$type] '$alias' has unexpected namespace '$ns' - recreating as non-namespaced"
        sf org delete scratch --target-org "$alias" --no-prompt >/dev/null 2>&1 || true
        sf org logout --target-org "$alias" --no-prompt >/dev/null 2>&1 || true
        needs_create=1
      elif [ "$type" = "namespaced" ] && [ "$ns" != "btcdev" ]; then
        echo "▸ [$type] '$alias' missing btcdev namespace (got '${ns:-none}') - recreating as namespaced"
        sf org delete scratch --target-org "$alias" --no-prompt >/dev/null 2>&1 || true
        sf org logout --target-org "$alias" --no-prompt >/dev/null 2>&1 || true
        needs_create=1
      else
        echo "▸ [$type] '$alias' healthy (expires $exp, namespace=${ns:-none})"
      fi
    fi
  fi

  if [ "$needs_create" -eq 1 ]; then
    local create_args=(
      --definition-file config/project-scratch-def.json
      --alias "$alias"
      --duration-days "$days"
      --no-ancestors
      --wait 20
      --json
    )
    if [ "$type" = "vanilla" ]; then
      create_args+=(--no-namespace)
    fi
    if [ -n "$devhub" ]; then
      create_args+=(--target-dev-hub "$devhub")
    fi

    echo "▸ [$type] creating scratch via devhub '${devhub:-sf config target-dev-hub}' (duration: ${days}d)"
    local create_json status
    create_json="$(sf org create scratch "${create_args[@]}" 2>&1)"
    status="$(echo "$create_json" | jq -r '.status // 1')"
    if [ "$status" != "0" ]; then
      echo "ERROR: scratch create failed for '$alias'" >&2
      echo "$create_json" | jq -r '.message // .' >&2
      exit 1
    fi

    exp="$(sf org list --json 2>/dev/null | jq -r --arg a "$alias" '.result.scratchOrgs[]? | select(.alias == $a) | .expirationDate' | head -n1)"
    echo "▸ [$type] '$alias' created (expires ${exp:-unknown})"
  fi
}

mode="${1:-both}"
case "$mode" in
  vanilla)
    ensure_one "$vanilla_alias" vanilla
    ;;
  namespaced|ns)
    ensure_one "$ns_alias" namespaced
    ;;
  both|all|"")
    ensure_one "$vanilla_alias" vanilla
    ensure_one "$ns_alias" namespaced
    ;;
  *)
    echo "Usage: ensure-scratch.sh [vanilla|namespaced|both]" >&2
    exit 2
    ;;
esac
