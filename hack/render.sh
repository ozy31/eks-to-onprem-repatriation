#!/usr/bin/env bash
# Render every platform component with its pinned chart and values into
# .rendered/<name>.yaml. Fails on template or values-schema errors.
set -euo pipefail

cd "$(dirname "$0")/.."
out=".rendered"
rm -rf "$out" && mkdir -p "$out"

for cfg in platform/components/*/config.yaml; do
  dir="$(dirname "$cfg")"
  name="$(yq '.name' "$cfg")"
  helm template "$name" "$(yq '.chart' "$cfg")" \
    --repo "$(yq '.repoURL' "$cfg")" \
    --version "$(yq '.version' "$cfg")" \
    --namespace "$(yq '.namespace' "$cfg")" \
    --kube-version 1.35.0 \
    --api-versions monitoring.coreos.com/v1 \
    --api-versions gateway.networking.k8s.io/v1 \
    --values "$dir/values.yaml" >"$out/$name.yaml"
  echo "rendered $name"
done
