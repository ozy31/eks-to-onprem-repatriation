#!/usr/bin/env bash
# Download the CRDs pinned in hack/crds.txt and turn them into JSON schemas
# for kubeconform (.schemas/<group>_<kind>_<version>.json).
set -euo pipefail

cd "$(dirname "$0")/.."
out=".schemas"
rm -rf "$out" && mkdir -p "$out/crds"

i=0
while read -r url; do
  case "$url" in ""|"#"*) continue ;; esac
  i=$((i + 1))
  curl -sfL "$url" -o "$out/crds/$(printf '%02d' "$i").yaml"
done < hack/crds.txt

yq ea -o=json '[.]' "$out"/crds/*.yaml | python3 hack/crd2schema.py "$out"
