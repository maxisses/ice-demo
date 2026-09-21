#!/usr/bin/env bash
#
# Rebuilds the whole demo on a cluster from scratch, in the order things have
# to happen. Everything here is either a file in this repo or a secret you have
# to supply - no hidden state.
#
# What it does NOT do: install operators. Dev Spaces, Pipelines, GitOps and
# Lightspeed have to be there already.
#
# Required environment:
#   QUAY_USER, QUAY_TOKEN        push access to quay.io/mdargatz/icedemo
#   GIT_DEPLOY_KEY               path to the private half of the repo's deploy key
# Optional:
#   MAAS_BASE_URL, MAAS_API_KEY  to wire up the AI workspace
#   WORKSPACE_NS                 your Dev Spaces namespace (default: <user>-devspaces)
set -euo pipefail

NS=md-ice-demo-part1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

: "${QUAY_USER:?set QUAY_USER}"
: "${QUAY_TOKEN:?set QUAY_TOKEN}"
: "${GIT_DEPLOY_KEY:?set GIT_DEPLOY_KEY to the private key file}"

echo "==> Namespace"
oc apply -f cluster/00-namespace.yaml

echo "==> Secrets"
oc create secret docker-registry quay-push-secret -n "${NS}" \
  --docker-server=quay.io --docker-username="${QUAY_USER}" \
  --docker-password="${QUAY_TOKEN}" --dry-run=client -o yaml | oc apply -f -

oc create secret generic git-push-ssh -n "${NS}" \
  --from-file=id_ed25519="${GIT_DEPLOY_KEY}" \
  --from-literal=known_hosts="$(ssh-keyscan -t ed25519,rsa github.com 2>/dev/null)" \
  --dry-run=client -o yaml | oc apply -f -

if ! oc get secret webhook-secret -n "${NS}" >/dev/null 2>&1; then
  oc create secret generic webhook-secret -n "${NS}" \
    --from-literal=secretToken="$(openssl rand -hex 20)"
  echo "    generated a new webhook secret"
else
  echo "    keeping the existing webhook secret"
fi

echo "==> Tekton"
oc apply -f tekton/

echo "==> Argo CD"
oc apply -f gitops/argocd/

echo "==> Dev Spaces workspaces"
WORKSPACE_NS="${WORKSPACE_NS:-$(oc get checluster devspaces -n openshift-devspaces \
  -o jsonpath='{.spec.devEnvironments.defaultNamespace.template}' \
  | sed "s|<username>|$(oc whoami | tr -d ':' | tr '[:upper:]' '[:lower:]')|")}"
echo "    workspace namespace: ${WORKSPACE_NS}"

./hack/create-editor-template.sh "${WORKSPACE_NS}"
./hack/create-webhook-secret.sh "${WORKSPACE_NS}"
./hack/create-git-ssh-secret.sh "${GIT_DEPLOY_KEY}" "${WORKSPACE_NS}"

if [ -n "${MAAS_BASE_URL:-}" ] && [ -n "${MAAS_API_KEY:-}" ]; then
  ./hack/create-ai-secret.sh "${MAAS_BASE_URL}" "${MAAS_API_KEY}" \
    "${AI_MODEL:-deepseek-r1-distill-qwen-14b}" "${WORKSPACE_NS}"
else
  echo "    skipping the AI secret - set MAAS_BASE_URL and MAAS_API_KEY for it"
fi

for f in cluster/3*-devworkspace-*.yaml; do
  sed "s|namespace: .*-devspaces.*|namespace: ${WORKSPACE_NS}|" "$f" | oc apply -f -
done

cat <<MSG

==> Done. One thing is still manual, because it has to be:

    Build the dependency base image once, before the first CI run:

      tkn pipeline start build-base-image -n ${NS} \\
        --workspace name=shared-workspace,claimName=ice-demo-workspace \\
        --workspace name=dockerconfig,secret=quay-push-secret \\
        --serviceaccount pipeline --showlog

MSG
