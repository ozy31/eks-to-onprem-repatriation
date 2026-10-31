# AWS service mapping

What each managed service on the EKS side becomes in the data centre, how its
data moves, and what the team takes on by running it.

| AWS | On-prem | Where | How data moves | What we now own |
|---|---|---|---|---|
| EKS control plane | Talos Linux, 3 control-plane nodes | `talos/` | n/a (workloads redeploy from git) | etcd backups, Kubernetes upgrades (`talosctl upgrade-k8s`) |
| EKS managed nodes / Karpenter | Talos workers, fixed pools | `talos/patches/worker*.yaml` | n/a | Capacity planning, hardware failures |
| VPC CNI, kube-proxy | Cilium (native routing, kube-proxy replacement) | `platform/components/cilium` | n/a | Network policy and BGP config |
| NLB / ALB + Load Balancer Controller | Cilium BGP LoadBalancer IPs + Gateway API | `platform/manifests/cilium-bgp.yaml`, `gateway.yaml` | n/a | ToR switch BGP sessions |
| Route 53 records (external-dns) | Cloudflare DNS (external-dns) | `platform/components/external-dns` | DNS records recreated | Nothing new: Cloudflare was already the edge |
| ACM | cert-manager + Let's Encrypt (DNS-01) | `platform/manifests/cert-manager.yaml` | Certificates reissued | Renewal monitoring |
| EBS gp3 | Ceph RBD (`ceph-block`) | `platform/components/rook-ceph-cluster` | Velero data mover (CSI snapshot -> Kopia) | Disk failures, Ceph upgrades |
| EFS | CephFS (`ceph-filesystem`) | same | Velero data mover | same |
| S3 | Ceph RGW (`ceph-bucket`) | same | rclone `copy` every 15 min, final pass at cutover | Off-site copy of critical buckets |
| RDS PostgreSQL | CloudNativePG, 3 instances | `migration/postgres` | Logical replication, reverse replication for rollback | Failover tests, PITR drills, major upgrades |
| RDS automated backups | Barman Cloud plugin -> Ceph RGW | `migration/postgres/backups.yaml` | n/a | Restore tests |
| MSK | Strimzi Kafka (KRaft) | `migration/kafka/kafka.yaml` | MirrorMaker 2, identity topic names, offset sync | Broker upgrades, partition rebalancing |
| Secrets Manager | OpenBao + External Secrets | `platform/components/openbao`, `platform/manifests/external-secrets.yaml` | Secrets re-entered by key owners | Unsealing, OpenBao backups |
| KMS | OpenBao (transit engine for application-level encryption) | `platform/components/openbao` | Keys re-created, data re-encrypted by the services | Unseal key custody |
| IAM roles for service accounts | Kubernetes service accounts, OpenBao Kubernetes auth | `workloads/*/overlays/dc1-prod` | n/a | Access reviews |
| CloudWatch / Container Insights | Prometheus, Grafana, Loki (see [k8s-observability-stack](https://github.com/ozy31/k8s-observability-stack)) | | n/a | Retention and storage |
| AWS Backup | Velero -> Ceph RGW, plus an off-site copy | `platform/components/velero` | n/a | Restore tests |

## What stays in the cloud

- **Cloudflare** stays the edge for both sites: WAF, DDoS protection, the load
  balancer that splits traffic during the migration
  ([terraform-cloudflare-edge](https://github.com/ozy31/terraform-cloudflare-edge)).
- **An off-site copy of backups** in a second location (another data centre or
  an object store with object lock). A single data centre is a single failure
  domain; this is the part of "DR" that cannot be repatriated.
- **Burst or experimental workloads** that are cheaper on demand than on owned
  hardware, for example GPU training runs.
