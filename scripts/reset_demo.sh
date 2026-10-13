#!/usr/bin/env bash
# Resets the demo data and reseeds it: 99, then 02, 04, 05, 06, 07, 08, 09, 11 and 03
# (see "Demo readiness" in the README).
#
# Deletes every record the seed scripts created, so it asks first. Metadata (pages,
# layouts, apps) isn't touched. Stops at the first script that fails; rerunning from
# the start is safe, because 99 clears whatever was seeded.
#
# Usage: scripts/reset_demo.sh [target-org] [--yes]
#   target-org  alias or username; defaults to the project's target-org
#   --yes       skip the confirmation prompt
set -euo pipefail
cd "$(dirname "$0")/.."

org=""
assume_yes=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) assume_yes=true ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) org="$arg" ;;
    esac
done

scripts=(
    99_reset_demo_data
    02_seed_demo_data
    04_seed_revenue_history
    05_seed_activity_history
    06_seed_account_plans
    07_seed_products
    08_seed_objective_action_plans
    09_seed_service_cloud
    11_seed_forecast_quotas
    03_recalculate_rollups
)

target="${org:-the default target org}"
if ! $assume_yes; then
    read -r -p "Delete and reseed all Denali demo data in ${target}? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 1; }
fi

result=$(mktemp)
trap 'rm -f "$result"' EXIT

step=0
for name in "${scripts[@]}"; do
    step=$((step + 1))
    echo "[$step/${#scripts[@]}] $name"
    if ! sf apex run --file "scripts/apex/$name.apex" ${org:+--target-org "$org"} --json > "$result" 2>/dev/null; then
        # The scripts log their results at ERROR level; show the failure and stop.
        python3 - "$result" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
except ValueError:
    sys.exit("    Failed, and sf returned no JSON. Run the script on its own to see why.")
print("    FAILED:", (data.get("message") or "unknown error").replace("\n", " "))
PY
        echo "Stopped. Fix the problem, then run scripts/reset_demo.sh again."
        exit 1
    fi
    # Show the script's own result lines (logged at ERROR level so they stand out).
    python3 - "$result" <<'PY'
import json, sys
logs = json.load(open(sys.argv[1]))["result"].get("logs", "")
for line in logs.splitlines():
    if "|USER_DEBUG|" in line and "|ERROR|" in line:
        print("    " + line.split("|ERROR|", 1)[1].replace("&#124;", "|"))
PY
done

echo
echo "Done. Next:"
echo "  - Open both dashboards (Revenue Health, Margin & Competition) and click Refresh."
echo "  - Demo soon: 09 started the SLA clocks just now."
