# 2. Talos Linux for the Kubernetes nodes

Status: accepted

## Context

On EKS, AWS operated the control plane and the node OS came as an AMI. On our
own hardware we operate both. A general-purpose distribution with SSH access
drifts: packages, hand edits, different kernel versions per node.

## Decision

Talos Linux on every node: immutable, no SSH, configured only through its API
from the machine configs generated from `talos/patches`. Kubernetes and OS
upgrades are `talosctl upgrade` and `talosctl upgrade-k8s`.

## Consequences

- The node configuration is code, reviewed in pull requests and validated in
  CI (`make talos`).
- Debugging works through `talosctl` (logs, dmesg, packet capture) and
  privileged debug pods, not a shell on the host. This takes adjustment.
- Losing `secrets.yaml` or the admin `talosconfig` means losing administrative
  access; both live in the team's password manager.

## Alternatives considered

- **Ubuntu + kubeadm.** Familiar, but configuration drift and patching are ours
  to solve.
- **RKE2 / k3s.** Good distributions; still a mutable OS underneath.
- **OpenShift.** Strong, but licence cost and a much larger platform than we need.
