#!/usr/bin/env bash
# Validate every Kubernetes manifest in the repository against the Kubernetes
# and CRD schemas (run hack/schemas.sh and hack/render.sh first).
set -euo pipefail

cd "$(dirname "$0")/.."
K8S_VERSION="${K8S_VERSION:-1.37.1}"

kc() {
  kubeconform -strict -summary -kubernetes-version "$K8S_VERSION" \
    -schema-location default \
    -schema-location '.schemas/{{.Group}}_{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' "$@"
}

echo "==> platform, migration"
kc -ignore-filename-pattern 'config.yaml' -ignore-filename-pattern 'values.yaml' \
  platform/bootstrap platform/manifests migration

echo "==> workloads"
for overlay in workloads/*/overlays/*; do
  echo "--- $overlay"
  kustomize build "$overlay" | kc -
done

echo "==> rendered charts"
# Chart CRDs themselves have no schema here; everything else must validate.
kc -ignore-missing-schemas .rendered
