#!/usr/bin/env bash
# Publishes the Denali Assistant agent from agentforce/ to an org.
#
# `sf agent publish authoring-bundle` only looks in the project's default package
# directory (force-app), so this makes agentforce/ the default for the publish and
# puts sfdx-project.json back afterwards, even if the publish fails.
#
# Usage: scripts/publish_agent.sh [target-org]
set -euo pipefail
cd "$(dirname "$0")/.."

backup=$(mktemp)
cp sfdx-project.json "$backup"
trap 'cp "$backup" sfdx-project.json; rm -f "$backup"' EXIT

python3 - <<'PY'
import json
with open("sfdx-project.json") as f:
    project = json.load(f)
for package in project["packageDirectories"]:
    package.pop("default", None)
    if package["path"] == "agentforce":
        package["default"] = True
with open("sfdx-project.json", "w") as f:
    json.dump(project, f, indent=2)
    f.write("\n")
PY

sf agent publish authoring-bundle --api-name Denali_Assistant ${1:+--target-org "$1"}
