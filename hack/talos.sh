#!/usr/bin/env bash
# Generate the Talos machine configs from the patches with throwaway secrets
# and validate them. Real clusters keep secrets.yaml in OpenBao, never in git.
set -euo pipefail

cd "$(dirname "$0")/.."
out=".talos"
rm -rf "$out" && mkdir -p "$out"

talosctl gen secrets -o "$out/secrets.yaml"
talosctl gen config dc1-prod https://api.dc1.example.com:6443 \
  --with-secrets "$out/secrets.yaml" \
  --config-patch @talos/patches/common.yaml \
  --config-patch-control-plane @talos/patches/controlplane.yaml \
  --config-patch-worker @talos/patches/worker.yaml \
  --output "$out"
talosctl machineconfig patch "$out/worker.yaml" \
  --patch @talos/patches/worker-storage.yaml \
  --output "$out/worker-storage.yaml"

for role in controlplane worker worker-storage; do
  talosctl validate --config "$out/$role.yaml" --mode metal --strict
done
