#!/usr/bin/env bash
#
# Installs a pre-push hook that notifies the Tekton EventListener.
#
# GitHub cannot reach this lab cluster, so the push notification comes from
# here instead. The payload and the HMAC signature are exactly what GitHub
# would send, so the EventListener does not know the difference.
set -euo pipefail

NAMESPACE="${ICE_DEMO_NAMESPACE:-md-ice-demo-part1}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
CONF_DIR="${HOME}/.ice-demo"

mkdir -p "${CONF_DIR}"

echo "--> Looking up the webhook route in ${NAMESPACE}"
if ! WEBHOOK_HOST=$(oc get route ice-demo-webhook -n "${NAMESPACE}" \
      -o jsonpath='{.spec.host}' 2>/dev/null) || [ -z "${WEBHOOK_HOST}" ]; then
  cat >&2 <<MSG

  Could not read the webhook route. You are probably not logged in yet.
  Run this, then start command "4. Arm the git hook" again:

      oc login --server=https://api.ocp4.stormshift.coe.muc.redhat.com:6443

MSG
  exit 1
fi

echo "--> Reading the shared webhook secret"
oc get secret webhook-secret -n "${NAMESPACE}" \
  -o jsonpath='{.data.secretToken}' | base64 -d > "${CONF_DIR}/webhook-secret"
chmod 600 "${CONF_DIR}/webhook-secret"

echo "https://${WEBHOOK_HOST}" > "${CONF_DIR}/webhook-url"

install -m 0755 "${REPO_ROOT}/hack/pre-push" "${REPO_ROOT}/.git/hooks/pre-push"

cat <<MSG

  Ready. The hook is armed at .git/hooks/pre-push
  EventListener: https://${WEBHOOK_HOST}

  From now on every 'git push' to main starts the localnews-ci pipeline.

MSG
