#!/usr/bin/env bash
#
# Puts the EventListener URL and its shared secret into your Dev Spaces
# namespace, labelled so that Dev Spaces mounts them into every workspace as
# environment variables. Run this once, from a shell that is logged in as you.
set -euo pipefail

DEMO_NS="${ICE_DEMO_NAMESPACE:-md-ice-demo-part1}"
WORKSPACE_NS="${1:-$(oc project -q)}"

URL="https://$(oc get route ice-demo-webhook -n "${DEMO_NS}" -o jsonpath='{.spec.host}')"
SECRET="$(oc get secret webhook-secret -n "${DEMO_NS}" -o jsonpath='{.data.secretToken}' | base64 -d)"

oc create secret generic ice-demo-webhook -n "${WORKSPACE_NS}" \
  --from-literal=ICE_DEMO_WEBHOOK_URL="${URL}" \
  --from-literal=ICE_DEMO_WEBHOOK_SECRET="${SECRET}" \
  --dry-run=client -o yaml | oc apply -f -

oc label secret ice-demo-webhook -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-to-devworkspace=true \
  controller.devfile.io/watch-secret=true --overwrite

oc annotate secret ice-demo-webhook -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-as=env --overwrite

echo "Done. Restart your workspace and the git hook picks the values up."
