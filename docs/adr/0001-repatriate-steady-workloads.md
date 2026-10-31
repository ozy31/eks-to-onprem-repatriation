# 1. Move steady-state workloads from EKS to our own hardware

Status: accepted

## Context

The platform's load is predictable: a daily curve with known peaks, and growth
that is planned a year ahead. Most of the AWS bill is compute that runs all the
time, managed databases, and data transfer out. Discounts (Savings Plans,
Reserved Instances) were already applied, so the remaining gap to owned
hardware is structural, not a tuning problem.

The things the cloud is best at, elastic burst capacity and a broad catalogue
of managed services, are used by a small part of the estate.

## Decision

Run the steady-state platform (Kubernetes, PostgreSQL, Kafka, object storage)
on owned hardware in a colocation data centre. Keep Cloudflare as the edge,
keep an off-site backup copy outside the data centre, and keep the option to
burst to the cloud for workloads that are genuinely spiky.

The decision is gated by the TCO model in `tools/tco`: the move goes ahead only
if the payback period, including the months both sites run, is under 24 months
with a 10% growth assumption.

## Consequences

- We own capacity planning. Hardware lead times (6-10 weeks) mean ordering
  ahead of growth, and keeping 30% headroom.
- We own failures that AWS absorbed: disks, nodes, power, the network. The
  platform has to tolerate a rack loss without manual action.
- Two more FTEs of platform work, which the TCO model includes.
- Every managed service is replaced by an operator we run (docs/service-mapping.md).
  Each one needs restore drills, not just backups.

## Alternatives considered

- **Stay and optimise further.** Rightsizing and commitments were already in
  place; the remaining savings were estimated at 10-15%.
- **Another cloud.** Similar unit costs; the migration effort without the
  structural saving.
- **Hybrid for good.** Keeping both sites permanently doubles the operational
  surface. Hybrid is the migration path, not the target.
