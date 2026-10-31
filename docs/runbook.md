# Migration runbook

Five phases. Each phase ends with a check that decides whether to continue, and
every phase has a rollback that is cheaper than pushing forward on a bad day.

| Phase | Goal | Rollback |
|---|---|---|
| 0. Foundations | Hardware racked, network and VPN up, Talos cluster built | Nothing to roll back |
| 1. Platform | Platform components healthy, data replication running | Delete the on-prem cluster; EKS untouched |
| 2. Stateless traffic | Services run at both sites; traffic shifted in steps | `dc1_traffic_percent` back to the previous step |
| 3. Stateful cutover | PostgreSQL, Kafka and buckets switched to on-prem | Reverse replication: switch the secret back |
| 4. Decommission | EKS removed after the rollback window | Rebuild from git + backups (slow, last resort) |

## Phase 0: foundations

1. Rack and cable the nodes. Two ToR switches per rack, BGP to each node
   (ASN 64600 on the switches, 64512 on the nodes).
2. Site-to-site connectivity to the VPC: Direct Connect or two IPsec tunnels.
   On-prem services talk to RDS and MSK over it until phase 3, so measure the
   round-trip time now. Above ~10 ms, latency-sensitive services wait for the
   database cutover before taking traffic.
3. Build the cluster:
   ```bash
   make talos                                    # configs from talos/patches
   talosctl apply-config --insecure -n <node> --file .talos/controlplane.yaml
   talosctl bootstrap -n <first-control-plane>
   talosctl kubeconfig -n <first-control-plane>
   ```
   Storage nodes get `.talos/worker-storage.yaml`.
4. Store `secrets.yaml` and `talosconfig` in the password manager of the
   platform team. Losing them means losing administrative access to the nodes.

**Exit check:** all nodes registered (they stay `NotReady` until Cilium is
installed in phase 1), etcd healthy on three members (`talosctl etcd members`).

## Phase 1: platform

1. `make bootstrap`: Gateway API CRDs, Cilium, Argo CD, then the `platform`
   ApplicationSet takes over.
2. Initialise OpenBao once and distribute the unseal keys:
   ```bash
   kubectl -n openbao exec openbao-0 -- bao operator init -key-shares=5 -key-threshold=3
   ```
   Each of five key holders gets one share. Unseal every pod after any full
   restart (`bao operator unseal`, three holders).
3. Enable Kubernetes auth, the `external-secrets` role and the KV engine at
   `secret/`, then enter the secrets the services need.
4. Register both clusters in Argo CD as `eks-prod` and `dc1-prod`
   (`argocd cluster add`), apply `platform/bootstrap/workloads.yaml`.
5. Run `migration/postgres/rds-source.sql` on RDS, then sync the `migration`
   Application. CloudNativePG imports the schema and the subscription starts
   the initial copy. MirrorMaker 2 starts copying topics. rclone starts the
   bucket copies.

**Exit check:**
- BGP sessions established on both ToR switches for every node.
- Ceph `HEALTH_OK`, OSDs on every storage node
  (`kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status`).
- `migration/postgres/cutover.sh check` shows 0 tables still copying and the
  lag stays under a few MB.
- MirrorMaker 2 lag per partition is stable and close to 0.
- A test restore of a CloudNativePG backup to a scratch cluster succeeds.
- A Velero restore of one EKS volume into a scratch namespace succeeds.

## Phase 2: stateless traffic

1. Add `workloads/<service>/overlays/dc1-prod` for one low-risk service.
   It still uses RDS and MSK through the VPN.
2. Shift traffic with `terraform/traffic-shift`, one step per change:
   `0 -> 1 -> 5 -> 25 -> 50`. Soak at least one business day at 5% and 25%,
   including a peak.
3. At each step compare the two sites: error rate, p99 latency, saturation.
   Session affinity keeps a user on one site, so a regression shows up as a
   difference between the pools rather than as random noise.
4. Repeat for the next services. Read-heavy services first, services with
   tight database latency budgets last.

**Rollback:** set `dc1_traffic_percent` to the previous step and apply.
Cloudflare also fails over on its own when the dc1 pool health check fails.

**Exit check:** all services run at both sites, dc1 at 50% for a full week
without a site-specific incident.

## Phase 3: stateful cutover

One maintenance window per data store, announced in advance. PostgreSQL:

1. Put the service into maintenance mode (writes rejected, reads served).
2. `CNPG_PUBLIC_URL=... ./migration/postgres/cutover.sh cutover`
   - waits for the replication lag to reach 0,
   - copies sequence values,
   - compares row counts per table,
   - disables the RDS -> CNPG subscription,
   - subscribes RDS to the `orders_rollback` publication (apply
     `rollback-publication.yaml` first).
3. Point the service at CloudNativePG:
   `bao kv patch secret/prod/orders/database url=postgres://...orders-db-rw...`.
   External Secrets refreshes within a minute; restart the pods to pick it up.
4. Leave maintenance mode. Merge the PR that removes `subscription.yaml`.

Kafka: stop producers on MSK, wait for MirrorMaker 2 lag 0, move producers and
consumers to `events-kafka-bootstrap` (the consumer offsets are already synced),
then stop MirrorMaker 2.

Buckets: switch writers to RGW, run a last `rclone copy` and a `rclone check`.

**Rollback (within the window):** switch the database secret back to RDS. The
reverse subscription kept RDS current. Sequences must be copied back the same
way as in step 2 before writes resume on RDS.

**Exit check:** two weeks at 100% on-prem with backups and restore tests
passing. Then drop the reverse subscription.

## Phase 4: decommission

1. `dc1_traffic_percent = 100`; the fallback pool becomes dc1 automatically.
2. Delete the `eks-prod` overlays. The ApplicationSet keeps the resources
   (`preserveResourcesOnDeletion`); scale them down and delete them by hand.
3. Final Velero backup of EKS to the migration bucket, kept for the audit
   retention period.
4. Delete EKS, RDS, MSK and the migration buckets with Terraform.
5. Remove the migration credentials from OpenBao (`migration/*`).

## Operating the new platform

| Event | Action |
|---|---|
| Node hardware failure | `talosctl reset` on the replacement after repair, or `kubectl drain` + remove; Ceph rebalances on its own |
| Disk failure (OSD down) | Ceph recovers from replicas; replace the disk, Rook creates a new OSD |
| Talos or Kubernetes upgrade | `talosctl upgrade` one node at a time; PDBs and Ceph's `managePodBudgets` stop unsafe drains |
| OpenBao sealed after power loss | Three key holders unseal each pod |
| Database primary failure | CloudNativePG promotes a replica; check `kubectl cnpg status orders-db -n orders` |
| Full data centre loss | Restore from the off-site backup copy; this is the scenario the off-site copy exists for |
