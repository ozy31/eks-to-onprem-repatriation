# 3. Ceph (via Rook) for block, file and object storage

Status: accepted

## Context

EBS, EFS and S3 have to be replaced. Buying a SAN for block and a separate
object store means two vendors and two failure models. Local disks alone lose
data with the node.

## Decision

One Ceph cluster on dedicated storage nodes, run by Rook: RBD for block
(`ceph-block`), CephFS for shared file systems (`ceph-filesystem`), RGW for S3
(`ceph-bucket`). Three replicas with host as the failure domain; erasure
coding (2+1) for the object store data pool. Messenger v2 encryption on.

## Consequences

- One storage system to learn, monitor and upgrade, managed with the same
  GitOps flow as everything else.
- Storage nodes are tainted and only run Ceph, so OSD latency does not depend
  on application load.
- Capacity planning has to account for replication: 3x raw for block, 1.5x
  for object.
- Ceph is operationally deep. The team runs restore and failure drills (pull a
  disk, power off a node) before phase 3.

## Alternatives considered

- **Longhorn.** Simpler, but block only, and weaker at large volumes.
- **MinIO for objects + a SAN.** Two systems; MinIO's community edition is in
  maintenance mode.
- **Local PVs only (OpenEBS LocalPV, TopoLVM).** Fine for databases that
  replicate themselves, but it leaves EFS and S3 unsolved.
