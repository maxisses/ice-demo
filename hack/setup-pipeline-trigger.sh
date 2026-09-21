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

# Identity first. Without these two, git refuses to commit at all - and it
# fails at commit time, not now, which is a rotten thing to discover on stage.
git -C "${REPO_ROOT}" config user.name  "${GIT_AUTHOR_NAME:-Max Dargatz}"
git -C "${REPO_ROOT}" config user.email "${GIT_AUTHOR_EMAIL:-max.dargatz@mailbox.org}"
echo "git identity: $(git -C "${REPO_ROOT}" config user.name) <$(git -C "${REPO_ROOT}" config user.email)>"

# Dev Spaces mounts secrets read-only and world-readable; ssh refuses to touch
# a private key like that, so we take a copy with the permissions it wants.
MOUNTED_KEY="/home/user/.ssh-mounted/id_ed25519"
if [ -r "${MOUNTED_KEY}" ]; then
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
  install -m 0600 "${MOUNTED_KEY}" "${HOME}/.ssh/id_ed25519"
  ssh-keyscan -t ed25519,rsa github.com > "${HOME}/.ssh/known_hosts" 2>/dev/null
  cat > "${HOME}/.ssh/config" <<SSHCFG
Host github.com
  IdentityFile ${HOME}/.ssh/id_ed25519
  IdentitiesOnly yes
SSHCFG
  chmod 600 "${HOME}/.ssh/config"
  # The project is cloned over https, which is read-only for us.
  git -C "${REPO_ROOT}" remote set-url origin git@github.com:maxisses/ice-demo.git
  echo "git remote: switched to ssh, you can push from here"
else
  echo "git remote: no deploy key mounted, origin stays read-only https."
  echo "            run hack/create-git-ssh-secret.sh and restart the workspace."
fi

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
