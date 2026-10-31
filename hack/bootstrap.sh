#!/usr/bin/env bash
# First install on a fresh Talos cluster, before Argo CD exists:
#   1. Gateway API CRDs (Cilium's Gateway API support needs them at start-up)
#   2. Cilium, with the same values Argo CD will use later
#   3. Argo CD, then the AppProjects and ApplicationSets that take over
# Re-running is safe: every step is an upgrade/apply.
set -euo pipefail

cd "$(dirname "$0")/.."

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.7.0}"

component() { yq ".$2" "platform/components/$1/config.yaml"; }

install_component() {
  local name="$1"
  helm upgrade --install "$name" "$(component "$name" chart)" \
    --repo "$(component "$name" repoURL)" \
    --version "$(component "$name" version)" \
    --namespace "$(component "$name" namespace)" --create-namespace \
    --values "platform/components/$name/values.yaml" \
    --wait --timeout 10m
}

echo "==> Gateway API CRDs ${GATEWAY_API_VERSION}"
kubectl apply --server-side -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

echo "==> Cilium"
install_component cilium
kubectl -n kube-system rollout status ds/cilium --timeout 10m

echo "==> Argo CD"
install_component argo-cd

echo "==> Projects and ApplicationSets"
kubectl apply -f platform/bootstrap/project.yaml
kubectl apply -f platform/bootstrap/platform.yaml

cat <<'MSG'
Argo CD now owns the platform. Next:
  - register the EKS cluster as "eks-prod" and this cluster as "dc1-prod"
    (argocd cluster add), then apply platform/bootstrap/workloads.yaml
  - initialise and unseal OpenBao (docs/runbook.md, phase 1)
  - apply platform/bootstrap/migration.yaml when phase 1 is done
MSG
