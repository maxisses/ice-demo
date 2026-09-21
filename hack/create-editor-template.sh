#!/usr/bin/env bash
#
# The DevWorkspaces in cluster/ reference an editor by name. The Dev Spaces
# dashboard normally resolves that for you; when you apply a DevWorkspace with
# oc instead, the template has to exist in your namespace or the workspace
# fails with "plugin for component editor not found".
#
# We generate it from the cluster's own editor definitions rather than pinning
# a copy here, so it always matches the installed Dev Spaces version.
set -euo pipefail

WORKSPACE_NS="${1:-$(oc project -q)}"

oc get cm editors-definitions -n openshift-devspaces \
  -o jsonpath='{.data.che-code\.yaml}' > /tmp/che-code.yaml

python3 - "${WORKSPACE_NS}" <<'PY' | oc apply -f -
import sys, yaml
ns = sys.argv[1]
spec = yaml.safe_load(open('/tmp/che-code.yaml'))
print(yaml.safe_dump({
    'apiVersion': 'workspace.devfile.io/v1alpha2',
    'kind': 'DevWorkspaceTemplate',
    'metadata': {'name': 'che-code', 'namespace': ns},
    'spec': {k: v for k, v in spec.items() if k in ('components', 'commands', 'events')},
}, sort_keys=False))
PY
