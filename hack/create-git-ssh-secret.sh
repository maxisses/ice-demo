#!/usr/bin/env bash
#
# Mounts the repository's deploy key into your Dev Spaces workspaces, so that
# you can push from the browser IDE without typing a token.
#
# Pass the private key file as the first argument. The public half has to sit
# on https://github.com/maxisses/ice-demo/settings/keys with write access.
set -euo pipefail

KEY_FILE="${1:?usage: create-git-ssh-secret.sh <private-key-file> [workspace-namespace]}"
WORKSPACE_NS="${2:-$(oc project -q)}"

oc create secret generic ice-demo-git-ssh -n "${WORKSPACE_NS}" \
  --from-file=id_ed25519="${KEY_FILE}" \
  --dry-run=client -o yaml | oc apply -f -

oc label secret ice-demo-git-ssh -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-to-devworkspace=true \
  controller.devfile.io/watch-secret=true --overwrite

oc annotate secret ice-demo-git-ssh -n "${WORKSPACE_NS}" \
  controller.devfile.io/mount-path=/home/user/.ssh-mounted \
  controller.devfile.io/mount-as=file --overwrite

echo "Done. Restart your workspace; the postStart hook copies the key into ~/.ssh."
