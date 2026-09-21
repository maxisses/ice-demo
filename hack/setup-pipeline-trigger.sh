#!/usr/bin/env bash
#
# Installs a pre-push hook that notifies the Tekton EventListener.
#
# This runs as a postStart event, so it must never fail: an exit code other
# than zero takes the whole workspace down with it.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "pipeline trigger: not a git checkout yet, skipping"
  exit 0
}

install -m 0755 "${REPO_ROOT}/hack/pre-push" "${REPO_ROOT}/.git/hooks/pre-push" 2>/dev/null || {
  echo "pipeline trigger: could not install the hook into .git/hooks"
  exit 0
}

if [ -n "${ICE_DEMO_WEBHOOK_URL:-}" ] && [ -n "${ICE_DEMO_WEBHOOK_SECRET:-}" ]; then
  cat <<MSG

  Pipeline trigger armed.
  EventListener: ${ICE_DEMO_WEBHOOK_URL}

  Every 'git push' to main now starts the localnews-ci pipeline.

MSG
else
  cat <<'MSG'

  The hook is installed but has no webhook config, so pushes will not start
  the pipeline. The workspace gets ICE_DEMO_WEBHOOK_URL and
  ICE_DEMO_WEBHOOK_SECRET from a secret in your Dev Spaces namespace. Create
  it once with:

      ./hack/create-webhook-secret.sh

  and restart the workspace. Until then you can start a run by hand:

      tkn pipeline start localnews-ci -n md-ice-demo-part1 \
        --workspace name=shared-workspace,claimName=ice-demo-workspace \
        --workspace name=dockerconfig,secret=quay-push-secret \
        --workspace name=git-ssh,secret=git-push-ssh \
        --serviceaccount pipeline --showlog

MSG
fi

exit 0
