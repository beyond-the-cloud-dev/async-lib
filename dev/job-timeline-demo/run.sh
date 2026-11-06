#!/usr/bin/env bash
set -euo pipefail
ACTION=${1:-}
ORG=${2:-async-lib-scratch}
CHROMIUM=${3:-}
DEMO_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$DEMO_DIR/../.." && pwd)
SHOWCASE_RECORD='Acme Order #00124'
SEED_RECORD='Northwind Order #10248'
MANY_CHAINS_RECORD='Fabrikam Order #20001'
SHOWCASE_SCRIPTS=(00-account 01-stock 02-export 03-close 04-reprice 05-sync 06-fulfilment)

usage() {
    echo "Usage: bash dev/job-timeline-demo/run.sh <seed|live|live-priority|live-delay|live-quick|showcase|screenshots|cleanup|reset> [org-alias] [chromium-path]" >&2
    exit 1
}

run_apex() {
    sf apex run --target-org "$ORG" --file "$DEMO_DIR/scripts/$1" > /dev/null
}

deploy_demo() {
    (cd "$DEMO_DIR" && sf project deploy start --target-org "$ORG" --source-dir force-app/main/default/settings --wait 10 --ignore-conflicts > /dev/null)
    (cd "$DEMO_DIR" && sf project deploy start --target-org "$ORG" --source-dir force-app --wait 10 --ignore-conflicts > /dev/null)
    sf org assign permset --target-org "$ORG" --name AsyncResultAccess --name AsyncRequeueAccess > /dev/null 2>&1 || true
}

record_path() {
    local id
    id=$(sf data query -q "SELECT Id FROM Account WHERE Name = '$1' ORDER BY CreatedDate DESC LIMIT 1" --target-org "$ORG" --json | jq -r '.result.records[0].Id')
    echo "/lightning/r/Account/$id/view"
}

record_url() {
    echo "$(sf org display --target-org "$ORG" --json | jq -r '.result.instanceUrl')$(record_path "$1")"
}

running_user_id() {
    local username
    username=$(sf org display --target-org "$ORG" --json | jq -r '.result.username')
    sf data query -q "SELECT Id FROM User WHERE Username = '$username'" --target-org "$ORG" --json | jq -r '.result.records[0].Id'
}

set_user_locale() {
    sf data update record --sobject User --record-id "$1" --values "LocaleSidKey=$2" --target-org "$ORG" > /dev/null
}

take_shots() {
    local stage=$1 login_file
    login_file=$(mktemp)
    sf org open --target-org "$ORG" --url-only --path "$(record_path "$SHOWCASE_RECORD")" --json > "$login_file" 2> /dev/null
    NODE_PATH=$(npm root -g) node "$DEMO_DIR/screenshots/take.js" "$login_file" "$stage" "$REPO_ROOT/website/public/images/job-timeline" "$CHROMIUM" || {
        rm -f "$login_file"
        exit 1
    }
    rm -f "$login_file"
}

case "$ACTION" in
    seed)
        deploy_demo
        run_apex 01-seed.apex
        run_apex 04-many-chains.apex
        run_apex 05-priority.apex
        echo "Seeded. Settles in about 4 minutes."
        echo "Record page: $(record_url "$SEED_RECORD")"
        echo "More than 50 chains: $(record_url "$MANY_CHAINS_RECORD")"
        ;;
    live)
        run_apex 02-live.apex
        echo "Live chain enqueued. Refresh the card: $(record_url "$SEED_RECORD")"
        ;;
    live-priority)
        run_apex 06-priority-live.apex
        echo "Chain enqueued. Refresh the card, jobs arrive after 30 s: $(record_url "$SEED_RECORD")"
        ;;
    live-delay)
        run_apex 07-delay-live.apex
        echo "Chain enqueued. Refresh the card, it takes about 5 minutes: $(record_url "$SEED_RECORD")"
        ;;
    live-quick)
        run_apex 08-quick-live.apex
        echo "Short chain enqueued. Refresh the card, it takes about 90 seconds: $(record_url "$SEED_RECORD")"
        ;;
    showcase)
        deploy_demo
        for script in "${SHOWCASE_SCRIPTS[@]}"; do
            run_apex "showcase/$script.apex"
            [ "$script" = "00-account" ] || [ "$script" = "06-fulfilment" ] || sleep 60
        done
        sleep 120
        echo "Showcase settled: $(record_url "$SHOWCASE_RECORD")"
        ;;
    screenshots)
        user_id=$(running_user_id)
        user_locale=$(sf data query -q "SELECT LocaleSidKey FROM User WHERE Id = '$user_id'" --target-org "$ORG" --json | jq -r '.result.records[0].LocaleSidKey')
        trap 'set_user_locale "$user_id" "$user_locale"' EXIT
        set_user_locale "$user_id" en_GB
        take_shots settled
        take_shots map
        run_apex showcase/07-live.apex
        take_shots running
        ;;
    cleanup)
        run_apex 03-cleanup.apex
        echo "Cleaned."
        ;;
    reset)
        (cd "$DEMO_DIR/reset" && sf project deploy start --target-org "$ORG" --source-dir force-app --wait 10 --ignore-conflicts > /dev/null)
        echo "QueueableJobSetting.All is back to the repo defaults."
        ;;
    *)
        usage
        ;;
esac
