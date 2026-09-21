#!/usr/bin/env bash
#
# Model credentials for the AI workspace. Dev Spaces mounts them as environment
# variables because of the mount-to-devworkspace label, so nothing has to be
# written into devfile-ai.yaml.
#
#   ./hack/create-ai-secret.sh <base-url> <api-key> [model] [workspace-namespace]
set -euo pipefail

BASE_URL="${1:?usage: create-ai-secret.sh <base-url> <api-key> [model] [namespace]}"
API_KEY="${2:?usage: create-ai-secret.sh <base-url> <api-key> [model] [namespace]}"
MODEL="${3:-deepseek-r1-distill-qwen-14b}"
WORKSPACE_NS="${4:-$(oc project -q)}"

oc create secret generic ice-demo-ai -n "${WORKSPACE_NS}" \
  --from-literal=OPENAI_BASE_URL="${BASE_URL}" \
  --from-literal=OPENAI_API_KEY="${API_KEY}" \
  --from-literal=AI_MODEL="${MODEL}" \
  --dry-run=client -o yaml | oc apply -f -

oc label secret ice-demo-ai -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-to-devworkspace=true \
  controller.devfile.io/watch-secret=true --overwrite

oc annotate secret ice-demo-ai -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-as=env --overwrite

echo "Done. Restart the AI workspace to pick the values up."
