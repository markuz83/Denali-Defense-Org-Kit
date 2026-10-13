#!/usr/bin/env bash
# Deploys force-app to a NEW org (one that has never had the Pricing Rationale prompt template).
#
# The template file carries the version identifiers of the org the kit was built in, and a new org
# rejects them. This builds a temporary metadata copy of force-app, keeps only the template's latest
# version without identifiers, and deploys that copy. The repo's files are left alone, so normal
# `sf project deploy start --source-dir force-app` keeps working for the original org.
#
# Usage:
#   scripts/deploy_core_new_org.sh <target-org> [extra sf deploy flags, e.g. --dry-run]
#   scripts/deploy_core_new_org.sh --build-only <output-dir>    # build the copy without deploying
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--build-only" ]]; then
    out="${2:?usage: scripts/deploy_core_new_org.sh --build-only <output-dir>}"
    target=""
    shift 2
else
    target="${1:?usage: scripts/deploy_core_new_org.sh <target-org> [sf deploy flags]}"
    shift
    out="$(mktemp -d)/core"
fi

sf project convert source --source-dir force-app --output-dir "$out" >/dev/null

python3 - "$out/genAiPromptTemplates/Pricing_Rationale.genAiPromptTemplate" <<'PY'
import re, sys
path = sys.argv[1]
xml = open(path).read()
versions = re.findall(r'\n[ ]*<templateVersions>.*?</templateVersions>', xml, re.S)
latest = re.sub(r'\n[ ]*<versionIdentifier>[^<]*</versionIdentifier>', '', versions[-1])
for v in versions:
    xml = xml.replace(v, '')
xml = re.sub(r'\n[ ]*<activeVersionIdentifier>[^<]*</activeVersionIdentifier>', '', xml)
xml = xml.replace('</masterLabel>', '</masterLabel>' + latest, 1)
open(path, 'w').write(xml)
print(f'Prompt template: kept the latest of {len(versions)} versions, without version identifiers.')
PY

if [[ -z "$target" ]]; then
    echo "Built $out"
    exit 0
fi
sf project deploy start --metadata-dir "$out" --target-org "$target" --wait 30 "$@"
